class_name ScenarioPlay
extends RefCounted
## The steps of a bot scenario (ARCHITECTURE §9.7), apart from how a runner reaches the host: the
## core runner (ScenarioRunner, 2j) drives Match directly as a stand-in for server/, the bots
## runner (BotsRunner, 3h) plays through HostSession and a ClientSession per bot. Both play the same
## steps the same way, each bot learning only from the (name, fields) its peer received, and each
## runner names players through its own ScenarioPeers.
##
## A runner calls _act(bot, at_tick) for every bot once per tick of its clock, and supplies the
## hooks below (_send, _connect, _claim, _travel_ticks, _jump, _leave, _answer_load, _stand).
##
## Fails, naming the bot, its step and its last events (with the seed): a step that sends an
## intent and gets a Rejected it did not expect, or succeeds when it expected one; a target the bot
## cannot know; a Correction outside a placement (an honest bot is never corrected); a step not
## done within the time limit.

enum Result { DONE, WAITING, FAILED }

const MATCH_ENDED := &"MatchEnded"
## A WalkTo is done within this much of its stop distance: float noise.
const ARRIVED_SLACK_M := 0.001
## The most steps one bot may finish in one tick, against a script that never waits.
const MAX_STEPS_PER_TICK := 32

var scenario: BotScenario
var bots: Array[ScenarioBot] = []
var failures := PackedStringArray()
## The winning sides of the MatchEnded events, in order.
var ends: Array[StringName] = []
## Bot number -> peer id, this runner's (§4.6).
var peers: ScenarioPeers
## The tick of the runner's clock now, for a failure's report.
var tick_now := 0


func _init(bot_scenario: BotScenario, bot_peers: ScenarioPeers) -> void:
	scenario = bot_scenario
	peers = bot_peers


## Whether an event named `name` with payload `fields`, received by `receiver`, is `want_name`
## and matches `want` (a subset): a field that names a player (`peer`) holds a bot's number, mapped
## through `bot_peers`; strings and StringNames compare as text; vectors and floats approximately.
static func matches_fields(
	event: WireMessage,
	receiver: ScenarioBot,
	want_name: StringName,
	want: Dictionary,
	bot_peers: ScenarioPeers
) -> bool:
	if event.name != want_name:
		return false
	for key: Variant in want:
		var field := str(key)
		var wanted: Variant = want[key]
		if field == "peer" and wanted is int:
			wanted = bot_peers.peer_of(wanted as int)
		var got: Variant = (
			receiver.field_of(event, field) if receiver != null else event.fields.get(field)
		)
		if not same(got, wanted):
			return false
	return true


## The same match on one MatchEvent object: its payload, then its properties, so `peer` works on
## an event whose payload names none (SelfStatus). ScenarioInvariants' `never` check uses it.
static func event_matches(
	event: MatchEvent, want_name: StringName, want: Dictionary, bot_peers: ScenarioPeers
) -> bool:
	if event.event_name() != want_name:
		return false
	var payload := event.to_dict()
	for key: Variant in want:
		var field := str(key)
		var wanted: Variant = want[key]
		if field == "peer" and wanted is int:
			wanted = bot_peers.peer_of(wanted as int)
		var got: Variant = payload[field] if payload.has(field) else event.get(field)
		if not same(got, wanted):
			return false
	return true


static func same(got: Variant, want: Variant) -> bool:
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


## Runs the bot's steps from its current one until a step waits or sends.
func _act(bot: ScenarioBot, at_tick: int) -> void:
	tick_now = at_tick
	_before_steps(bot)
	for i in MAX_STEPS_PER_TICK:
		var step := bot.current_step()
		if step == null:
			break
		if not bot.joined and not step is StepJoin:
			break
		if bot.step_started < 0:
			bot.start_step(at_tick)
		var result := _run_step(bot, step, at_tick)
		if result != Result.DONE:
			break
		bot.finish_step()
	if not bot.gone and not bot.current_step() is StepWalkTo:
		_stand(bot)


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
		# D3 (a), the designer's answer on #96: the step says what a player does, and the bot
		# counts it as one more jump in its epoch, as a client's MoveClaim carries it (§4.3, E2).
		_jump(bot)
		result = Result.DONE
	elif step is StepLeave:
		bot.gone = true
		_leave(bot)
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
		result = _fail_step(bot, "the runner has no rule for this step")
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
		func(event: WireMessage) -> bool:
			if event.name != &"SettingsChanged":
				return false
			var settings: Dictionary = event.fields["settings"]
			for id: Variant in settings:
				if str(id) == String(step.id):
					return settings[id] == step.value
			return false
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
		var refused := _connect(bot)
		if not refused.is_empty():
			return _fail_step(bot, refused)
		return Result.WAITING
	return _intent_result(bot, step, bot.joined)


func _load_ack(bot: ScenarioBot, step: StepLoadAck) -> Result:
	var answering := bot.unanswered_load
	if answering < 0 and bot.phase == &"loading" and bot.auto_acked_match == bot.match_id:
		# A LoadAck answers the LoadMatch that arrives while it is the current step (§9.7).
		return _fail_step(
			bot,
			"this loading's LoadMatch arrived before the LoadAck step and was acknowledged at once"
		)
	if answering < 0:
		return Result.WAITING
	bot.unanswered_load = -1
	_answer_load(bot, answering, step.skip)
	return Result.DONE


func _walk(bot: ScenarioBot, step: StepWalkTo) -> Result:
	var target := bot.where_is(step.target)
	if target == Vector3.INF:
		return _fail_step(bot, "the bot cannot know where its target is")
	var offset := Vector3(target.x - bot.position.x, 0.0, target.z - bot.position.z)
	var distance := offset.length()
	if distance <= step.stop_m + ARRIVED_SLACK_M:
		return Result.DONE
	var ticks := _travel_ticks(bot)
	if ticks <= 0:
		return Result.WAITING
	var rules := scenario.mode.player_rules
	var sprinting := step.sprint and (bot.downed or bot.sprint_available)
	var speed := rules.sprint_speed_mps if sprinting else rules.walk_speed_mps
	if bot.downed:
		speed *= rules.ghost_speed_factor
	var direction := offset / distance
	var travel := minf(speed * ticks / Ticks.RATE, distance - step.stop_m)
	_claim(bot, bot.position + direction * travel, direction * speed, sprinting)
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
	var own := bot.peer
	var picked := bot.find_since(
		bot.step_cursor,
		func(event: WireMessage) -> bool:
			return (
				event.name == &"ItemPickedUp"
				and event.fields["peer"] == own
				and event.fields["item"] == item_id
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
		func(event: WireMessage) -> bool:
			return (
				event.name == &"ItemPlaced"
				and event.fields["item"] == item_id
				and str(event.fields["cause"]) == String(Items.PUT_DOWN)
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
	var until := step.until
	var done := bot.find_since(
		bot.step_cursor,
		func(event: WireMessage) -> bool:
			if event.name != until:
				return false
			var by: Variant = bot.field_of(event, "peer")
			return not by is int or by == bot.peer
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


func _received(bot: ScenarioBot, from: int, event_name: StringName, fields: Dictionary) -> bool:
	var found := bot.find_since(
		from,
		func(event: WireMessage) -> bool:
			return matches_fields(event, bot, event_name, fields, peers)
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
			% [bot.number, bot.peer, where, tick_now, why, bot.last_events(), scenario.session_seed]
		)
	)
	return Result.FAILED


# The hooks a runner supplies.


## Before the bot's steps run this tick (the core runner acknowledges a LoadMatch at once here).
func _before_steps(_bot: ScenarioBot) -> void:
	pass


## Sends `kind` with `args` from the bot as the current step's intent: sets bot.sent_seq.
func _send(_bot: ScenarioBot, _kind: StringName, _args: Dictionary) -> void:
	assert(false, "a runner sends intents")


## Connects the bot (a Join step's time has come): its Hello follows. Returns why the host refused
## it, or "".
func _connect(_bot: ScenarioBot) -> String:
	return "a runner connects bots"


## The bot moves to `to` (an honest MoveClaim), and takes it as its position.
func _claim(_bot: ScenarioBot, _to: Vector3, _velocity: Vector3, _sprint: bool) -> void:
	pass


## How many ticks of travel the bot may cover now: one per host tick in the core runner, the
## client ticks since its last move over the network.
func _travel_ticks(_bot: ScenarioBot) -> int:
	return 1


## The bot jumps where it stands: one more jump in its epoch.
func _jump(_bot: ScenarioBot) -> void:
	pass


## The bot disconnects.
func _leave(_bot: ScenarioBot) -> void:
	pass


## The bot's LoadAck step answers the LoadMatch of `match_id`: acknowledges it, or with `skip`
## never does.
func _answer_load(_bot: ScenarioBot, _match_id: int, _skip: bool) -> void:
	pass


## The bot is not walking this tick: it stands still.
func _stand(_bot: ScenarioBot) -> void:
	pass
