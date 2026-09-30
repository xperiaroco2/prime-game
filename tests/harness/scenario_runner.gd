class_name ScenarioRunner
extends RefCounted
## The core runner of bot scenarios (ARCHITECTURE §9.7, stage 2j): plays a BotScenario by driving
## Match directly, as server/ would. Each host tick, every bot acts on what it received so far
## (its script's current step becomes intents, stamped with the tick), the commands are applied in
## bot order, the tick runs, and each emitted event reaches exactly its recorded recipients: a bot
## sees only its peer's `view_of`. The geometry is a flat fake world (FlatWorldQuery, one floor at
## y = 0), and the levels are the mode's real ones, read by server/'s MarkerReader.
##
## Fails, naming the bot, its step and its last events (with the seed): a step that sends an
## intent and gets a Rejected it did not expect, or succeeds when it expected one; a target the bot
## cannot know; a Correction outside a placement (an honest bot is never corrected); a step not
## done within the time limit. Always asserted: the expected ends; no match error in
## `Match.diagnostics` (every `push_error` of core/ is one); the §5 invariants on every bot's stream
## (ScenarioInvariants); and that each bot received exactly its peer's `view_of` events.
##
## Server-side behaviour it stands in for: joins at tick 0 (PeerConnected, then Hello) unless a
## Join step says later; the setup's settings and map in one ChangeSettings from the host's bot
## right after its join (bot 1 joins at the start then); a LoadAck at once for every LoadMatch
## that no LoadAck step answers; RefuseJoins and AllowJoins; DisconnectPeer ends that bot, and its
## PeerLeft follows on the next tick.

enum Result { DONE, WAITING, FAILED }

## Bot 1 is the host (peer 1); bot i > 1 is peer PEER_BASE + i, so a scenario that confuses bot
## numbers with peer ids fails.
const PEER_BASE := 1000
const MATCH_ENDED := &"MatchEnded"
## A WalkTo is done within this much of its stop distance: float noise.
const ARRIVED_SLACK_M := 0.001
## The most steps one bot may finish in one tick, against a script that never waits.
const MAX_STEPS_PER_TICK := 32

var scenario: BotScenario
var game: Match
var bots: Array[ScenarioBot] = []
var failures := PackedStringArray()
## The winning sides of the MatchEnded events, in order.
var ends: Array[StringName] = []
var ticks_run := 0

var _invariants: ScenarioInvariants
var _commands: Array[MatchCommand] = []
var _to_leave: Array[int] = []
var _refusing := false


func _init(bot_scenario: BotScenario) -> void:
	scenario = bot_scenario


## Plays `bot_scenario` to its end; see `failures`.
static func play(bot_scenario: BotScenario) -> ScenarioRunner:
	var runner := ScenarioRunner.new(bot_scenario)
	runner.run()
	return runner


## The peer id of bot `bot`.
static func peer_of(bot: int) -> int:
	return 1 if bot == 1 else PEER_BASE + bot


## Whether `event` is named `event_name` and its payload matches `fields` (a subset): a field that
## names a player (`peer`) holds a bot's number; strings and StringNames compare as text; vectors
## and floats approximately.
static func matches(event: MatchEvent, event_name: StringName, fields: Dictionary) -> bool:
	if event.event_name() != event_name:
		return false
	var payload := event.to_dict()
	for key: Variant in fields:
		var field := str(key)
		var want: Variant = fields[key]
		if field == "peer" and want is int:
			want = peer_of(want as int)
		var got: Variant = payload[field] if payload.has(field) else event.get(field)
		if not _same(got, want):
			return false
	return true


func run() -> void:
	var problems := scenario.problems()
	for problem: String in problems:
		failures.append("scenario: %s" % problem)
	if not problems.is_empty():
		return
	var world := FlatWorldQuery.new()
	var levels := MarkerReader.read_levels(scenario.mode, world)
	for error: String in levels.errors:
		failures.append("level: %s" % error)
	if not levels.errors.is_empty():
		return
	game = Match.new(scenario.mode, scenario.session_seed, world, levels.layouts)
	for refusal: String in game.refusals:
		failures.append("mode: %s" % refusal)
	if not game.refusals.is_empty():
		return
	var forced: Dictionary[int, StringName] = {}
	for bot: int in scenario.forced_roles:
		forced[peer_of(bot)] = scenario.forced_roles[bot]
	game.force_roles(forced)
	_invariants = ScenarioInvariants.new(game, scenario)
	for number in range(1, scenario.bots + 1):
		bots.append(ScenarioBot.new(number, peer_of(number), scenario.steps_of(number)))
	if not game.start(0):
		failures.append("the match did not start")
		return
	_deliver()
	var limit := Ticks.from_seconds(scenario.time_limit_s)
	for at_tick in range(0, limit + 1):
		_run_tick(at_tick)
		ticks_run = at_tick + 1
		if not failures.is_empty() or _ended():
			break
	if failures.is_empty() and not _ended():
		_fail_time_limit()
	if failures.is_empty():
		_check_after()


func _run_tick(at_tick: int) -> void:
	_commands.clear()
	for peer: int in _to_leave:
		_queue(Intents.PEER_LEFT, peer)
	_to_leave.clear()
	if at_tick == 0:
		_join_at_start()
	for bot: ScenarioBot in bots:
		if not bot.gone and failures.is_empty():
			_act(bot, at_tick)
	for command: MatchCommand in _commands:
		game.apply(command)
		_deliver()
	game.tick(at_tick)
	_deliver()
	for problem: String in _invariants.check_tick():
		failures.append("tick %d: %s" % [at_tick, problem])
	for bot: ScenarioBot in bots:
		if not bot.gone and bot.joined:
			bot.see(game.snapshot_for(bot.peer))


## Every bot without a Join step connects and says Hello; then the host's bot sends the setup's
## settings and map.
func _join_at_start() -> void:
	for bot: ScenarioBot in bots:
		if not bot.joins_late():
			_connect(bot)
	if scenario.settings.is_empty() and scenario.map.is_empty():
		return
	var host := bots[0]
	var values := {}
	for id: StringName in scenario.settings:
		values[String(id)] = scenario.settings[id]
	var args := {"settings": values}
	if not scenario.map.is_empty():
		args["map"] = scenario.map
	_queue(Intents.CHANGE_SETTINGS, host.peer, args, host.next_seq())


func _connect(bot: ScenarioBot) -> void:
	bot.connected = true
	_queue(Intents.PEER_CONNECTED, bot.peer)
	bot.sent_seq = bot.next_seq()
	_queue(
		Intents.HELLO,
		bot.peer,
		{"name": "bot%d" % bot.number, "version": JoinRules.PROTOCOL_VERSION},
		bot.sent_seq
	)


## Runs the bot's steps from its current one until a step waits or sends.
func _act(bot: ScenarioBot, at_tick: int) -> void:
	if bot.load_ack_due and bot.joined:
		bot.load_ack_due = false
		_queue(Intents.LOAD_ACK, bot.peer, {"match_id": bot.match_id}, bot.next_seq())
	for i in MAX_STEPS_PER_TICK:
		var step := bot.current_step()
		if step == null:
			return
		if not bot.joined and not step is StepJoin:
			return
		if bot.step_started < 0:
			bot.start_step(at_tick)
		var result := _run_step(bot, step, at_tick)
		if result != Result.DONE:
			return
		bot.finish_step()


func _run_step(bot: ScenarioBot, step: ScenarioStep, at_tick: int) -> Result:
	var elapsed := at_tick - bot.step_started
	var result := Result.WAITING
	if step is StepJoin:
		result = _join(bot, step as StepJoin, at_tick)
	elif step is StepLoadAck:
		result = _load_ack(bot, step as StepLoadAck)
	elif step is StepReady:
		result = _ready_step(bot, step as StepReady)
	elif step is StepSetting:
		result = _setting(bot, step as StepSetting)
	elif step is StepReturnToLobby:
		result = _return_to_lobby(bot, step as StepReturnToLobby)
	elif step is StepWalkTo:
		result = _walk(bot, step as StepWalkTo)
	elif step is StepPickUp:
		result = _pick_up(bot, step as StepPickUp)
	elif step is StepPutDown:
		result = _put_down(bot, step as StepPutDown)
	elif step is StepUse:
		result = _use(bot, step as StepUse)
	elif step is StepJump:
		_claim(bot, bot.position, Vector3.ZERO, false, true)
		result = Result.DONE
	elif step is StepLeave:
		bot.gone = true
		_queue(Intents.PEER_LEFT, bot.peer)
		result = Result.DONE
	else:
		result = _check(bot, step, elapsed)
	return result


## The steps that only wait or check: WaitFor, Wait, Expect, ExpectNone.
func _check(bot: ScenarioBot, step: ScenarioStep, elapsed: int) -> Result:
	var result := Result.WAITING
	if step is StepWaitFor:
		var wait_for := step as StepWaitFor
		if _received(bot, bot.step_cursor, wait_for.event, wait_for.fields):
			result = Result.DONE
	elif step is StepWait:
		if elapsed >= Ticks.from_seconds((step as StepWait).seconds):
			result = Result.DONE
	elif step is StepExpect:
		var expect := step as StepExpect
		if _received(bot, bot.previous_cursor, expect.event, expect.fields):
			result = Result.DONE
		elif elapsed >= Ticks.from_seconds(expect.within_s):
			result = _fail_step(bot, "no %s matching %s arrived" % [expect.event, expect.fields])
	elif step is StepExpectNone:
		var none := step as StepExpectNone
		if _received(bot, bot.step_cursor, none.event, none.fields):
			result = _fail_step(bot, "%s matching %s arrived" % [none.event, none.fields])
		elif elapsed >= Ticks.from_seconds(none.for_s):
			result = Result.DONE
	else:
		result = _fail_step(bot, "the core runner has no rule for this step")
	return result


func _ready_step(bot: ScenarioBot, step: StepReady) -> Result:
	if bot.sent_seq < 0:
		_send(bot, Intents.SET_READY, {"ready": step.ready})
		return Result.WAITING
	return _intent_result(bot, step, _done_by(bot, &"ReadyChanged", {"ready": step.ready}))


func _setting(bot: ScenarioBot, step: StepSetting) -> Result:
	if bot.sent_seq < 0:
		_send(bot, Intents.CHANGE_SETTINGS, {"settings": {String(step.id): step.value}})
		return Result.WAITING
	var changed := bot.find_since(
		bot.step_cursor,
		func(event: MatchEvent) -> bool:
			return (
				event is SettingsChangedEvent
				and (event as SettingsChangedEvent).settings.get(step.id, -1) == step.value
			)
	)
	return _intent_result(bot, step, changed != null)


func _return_to_lobby(bot: ScenarioBot, step: StepReturnToLobby) -> Result:
	if bot.sent_seq < 0:
		_send(bot, Intents.RETURN_TO_LOBBY, {})
		return Result.WAITING
	var back := _received(bot, bot.step_cursor, &"PhaseChanged", {"phase": "lobby"})
	return _intent_result(bot, step, back)


func _join(bot: ScenarioBot, step: StepJoin, at_tick: int) -> Result:
	if not bot.connected:
		if at_tick < Ticks.from_seconds(step.at_s):
			return Result.WAITING
		if _refusing:
			return _fail_step(bot, "the host refuses new connections (Loading, Round or End)")
		_connect(bot)
		return Result.WAITING
	return _intent_result(bot, step, bot.joined)


func _load_ack(bot: ScenarioBot, step: StepLoadAck) -> Result:
	var load := bot.unanswered_load
	if load == null:
		return Result.WAITING
	bot.unanswered_load = null
	if not step.skip:
		_send(bot, Intents.LOAD_ACK, {"match_id": load.match_id})
	return Result.DONE


func _walk(bot: ScenarioBot, step: StepWalkTo) -> Result:
	var target := bot.where_is(step.target)
	if target == Vector3.INF:
		return _fail_step(bot, "the bot cannot know where its target is")
	var offset := Vector3(target.x - bot.position.x, 0.0, target.z - bot.position.z)
	var distance := offset.length()
	if distance <= step.stop_m + ARRIVED_SLACK_M:
		return Result.DONE
	var rules := game.mode.player_rules
	var sprinting := step.sprint and (bot.ghost or bot.sprint_available)
	var speed := rules.sprint_speed_mps if sprinting else rules.walk_speed_mps
	if bot.ghost:
		speed *= rules.ghost_speed_factor
	var direction := offset / distance
	var travel := minf(speed / Ticks.RATE, distance - step.stop_m)
	_claim(bot, bot.position + direction * travel, direction * speed, sprinting, false)
	return Result.WAITING


func _pick_up(bot: ScenarioBot, step: StepPickUp) -> Result:
	if bot.sent_seq < 0:
		var item := bot.item_of(step.target)
		if item < 0:
			return _fail_step(bot, "the bot cannot know which item its target is")
		bot.sent_item = item
		_send(bot, Intents.PICK_UP, {"item": item})
		return Result.WAITING
	var item_id := bot.sent_item
	var picked := bot.find_since(
		bot.step_cursor,
		func(event: MatchEvent) -> bool:
			return (
				event is ItemPickedUpEvent
				and (event as ItemPickedUpEvent).peer == bot.peer
				and (event as ItemPickedUpEvent).item == item_id
			)
	)
	return _intent_result(bot, step, picked != null)


func _put_down(bot: ScenarioBot, step: StepPutDown) -> Result:
	if bot.sent_seq < 0:
		var facing := _facing(bot, step.towards)
		if facing == Vector3.INF:
			return _fail_step(bot, "the bot cannot know where to face")
		bot.sent_item = bot.held
		_send(bot, Intents.PUT_DOWN, {"facing": facing})
		return Result.WAITING
	var item_id := bot.sent_item
	var placed := bot.find_since(
		bot.step_cursor,
		func(event: MatchEvent) -> bool:
			return (
				event is ItemPlacedEvent
				and (event as ItemPlacedEvent).item == item_id
				and (event as ItemPlacedEvent).cause == Items.PUT_DOWN
			)
	)
	return _intent_result(bot, step, placed != null)


func _use(bot: ScenarioBot, step: StepUse) -> Result:
	if bot.sent_seq < 0:
		var facing := _facing(bot, step.towards)
		if facing == Vector3.INF:
			return _fail_step(bot, "the bot cannot know where to face")
		_send(bot, Intents.USE, {"facing": facing})
		return Result.WAITING
	var own := bot.peer
	var until := step.until
	var done := bot.find_since(
		bot.step_cursor,
		func(event: MatchEvent) -> bool:
			if event.event_name() != until:
				return false
			var by: Variant = event.get("peer")
			return not by is int or by == own
	)
	return _intent_result(bot, step, done != null)


## The horizontal unit direction from the bot to `target`; zero when it stands on it; INF when it
## cannot know the target.
func _facing(bot: ScenarioBot, target: ScenarioTarget) -> Vector3:
	var at := bot.where_is(target)
	if at == Vector3.INF:
		return Vector3.INF
	var ahead := Vector3(at.x - bot.position.x, 0.0, at.z - bot.position.z)
	return Vector3.ZERO if ahead.is_zero_approx() else ahead.normalized()


## An honest MoveClaim of the bot to `to`, which it then takes as its position.
func _claim(bot: ScenarioBot, to: Vector3, velocity: Vector3, sprint: bool, jumped: bool) -> void:
	var facing := velocity.normalized() if not velocity.is_zero_approx() else Vector3.FORWARD
	var args := {
		"epoch": bot.epoch,
		"client_tick": bot.next_client_tick(),
		"position": to,
		"velocity": velocity,
		"facing": facing,
		"sprint": sprint,
		"moving": not velocity.is_zero_approx(),
		"jumped": jumped,
		"on_floor": true,
	}
	_queue(Intents.MOVE_CLAIM, bot.peer, args, bot.next_seq())
	bot.position = to


## Whether the intent the step sent is answered: DONE when it succeeded as the step expects (or was
## refused with the reason it expects), FAILED on any other answer, else WAITING.
func _intent_result(bot: ScenarioBot, step: ScenarioStep, succeeded: bool) -> Result:
	var reason := bot.rejection_of(bot.sent_seq)
	if not reason.is_empty():
		if reason == step.expect_rejected:
			return Result.DONE
		var wanted := (
			"" if step.expect_rejected.is_empty() else ", expected %s" % step.expect_rejected
		)
		return _fail_step(bot, "Rejected (%s)%s" % [reason, wanted])
	if succeeded:
		if not step.expect_rejected.is_empty():
			return _fail_step(bot, "succeeded, but expected Rejected (%s)" % step.expect_rejected)
		return Result.DONE
	return Result.WAITING


func _send(bot: ScenarioBot, kind: StringName, args: Dictionary) -> void:
	bot.sent_seq = bot.next_seq()
	_queue(kind, bot.peer, args, bot.sent_seq)


func _queue(kind: StringName, peer: int, args: Dictionary = {}, seq: int = 0) -> void:
	_commands.append(MatchCommand.new(kind, peer, game.ticked_through() + 1, args, seq))


## Hands the events emitted since the last call to their recipients, as server/ would.
func _deliver() -> void:
	var batch := game.take_outbox()
	for bot: ScenarioBot in bots:
		bot.begin_batch()
	for emitted: EmittedEvent in batch:
		for problem: String in _invariants.check_event(emitted):
			failures.append("invariant: %s" % problem)
		if emitted.is_directive:
			_carry_out(emitted.event)
			continue
		if emitted.event.event_name() == MATCH_ENDED:
			ends.append(StringName(str(emitted.event.to_dict().get("side", ""))))
		for peer: int in emitted.recipients:
			var bot := _bot_of(peer)
			if bot == null:
				continue
			var problem := bot.receive(emitted.event)
			if not problem.is_empty():
				_fail_step(bot, problem)
			var rejected := emitted.event as RejectedEvent
			if rejected != null and rejected.seq != bot.sent_seq:
				_fail_step(bot, "Rejected (%s) for intent %d" % [rejected.reason, rejected.seq])


func _carry_out(directive: MatchEvent) -> void:
	if directive is RefuseJoinsEvent:
		_refusing = true
	elif directive is AllowJoinsEvent:
		_refusing = false
	elif directive is DisconnectPeerEvent:
		var peer := (directive as DisconnectPeerEvent).peer
		var bot := _bot_of(peer)
		if bot != null and not bot.gone:
			bot.gone = true
			_to_leave.append(peer)


func _bot_of(peer: int) -> ScenarioBot:
	for bot: ScenarioBot in bots:
		if bot.peer == peer:
			return bot
	return null


## Every script is done and every expected side has won.
func _ended() -> bool:
	for bot: ScenarioBot in bots:
		if not bot.finished():
			return false
	return ends.size() >= _expected_sides().size()


func _expected_sides() -> Array[StringName]:
	var sides: Array[StringName] = []
	for end: StringName in scenario.expected_ends:
		if end != BotScenario.NONE:
			sides.append(end)
	return sides


func _fail_time_limit() -> void:
	for bot: ScenarioBot in bots:
		if not bot.finished():
			_fail_step(bot, "not done within the time limit (%s s)" % scenario.time_limit_s)
	if failures.is_empty():
		failures.append(
			"the ends %s did not arrive within the time limit; got %s" % [_expected_sides(), ends]
		)


func _check_after() -> void:
	if ends != _expected_sides():
		failures.append("expected the ends %s, got %s" % [scenario.expected_ends, ends])
	for line: String in game.diagnostics:
		if line.begins_with("error:"):
			failures.append("match %s" % line)
	for bot: ScenarioBot in bots:
		var view := game.view_of(bot.peer).events
		var received := bot.events
		if view != received:
			failures.append(
				(
					"bot %d received %d events, but view_of(%d) holds %d"
					% [bot.number, received.size(), bot.peer, view.size()]
				)
			)


func _received(bot: ScenarioBot, from: int, event_name: StringName, fields: Dictionary) -> bool:
	var found := bot.find_since(
		from, func(event: MatchEvent) -> bool: return matches(event, event_name, fields)
	)
	return found != null


## Whether the bot received its own `event_name` matching `fields` since the step started.
func _done_by(bot: ScenarioBot, event_name: StringName, fields: Dictionary) -> bool:
	var own := fields.duplicate()
	own["peer"] = bot.number
	return _received(bot, bot.step_cursor, event_name, own)


func _fail_step(bot: ScenarioBot, why: String) -> Result:
	var step := bot.current_step()
	var where := (
		"step %d (%s)" % [bot.step_index + 1, step.step_name()] if step != null else "no step"
	)
	failures.append(
		(
			"bot %d (peer %d), %s at tick %d: %s; its last events %s; seed %d"
			% [
				bot.number,
				bot.peer,
				where,
				game.ticked_through() + 1,
				why,
				bot.last_events(),
				scenario.session_seed
			]
		)
	)
	return Result.FAILED


static func _same(got: Variant, want: Variant) -> bool:
	if (got is String or got is StringName) and (want is String or want is StringName):
		return str(got) == str(want)
	if got is Vector3 and want is Vector3:
		return (got as Vector3).is_equal_approx(want as Vector3)
	if (got is float or got is int) and (want is float or want is int):
		var got_number: float = got
		var want_number: float = want
		return is_equal_approx(got_number, want_number)
	if typeof(got) != typeof(want):
		return false
	return got == want
