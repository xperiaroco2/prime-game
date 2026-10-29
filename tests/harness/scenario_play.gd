class_name ScenarioPlay
extends RefCounted
## The steps of a bot scenario (ARCHITECTURE §9.7), apart from how a runner reaches the host: the
## core runner (ScenarioRunner, 2j) drives Match directly as a stand-in for server/, the bots
## runner (BotsRunner, 3h) plays through HostSession and a ClientSession per bot. Both play the same
## steps the same way, each bot learning only from the (name, fields) its peer received, and each
## runner names players through its own ScenarioPeers.
##
## A runner calls _act(bot, at_tick) for every bot once per tick of its clock, and supplies the
## hooks below (_send, _connect, _claim, _travel_ticks, _sprint_available, _jump, _leave,
## _answer_load, _stand).
##
## Fails, naming the bot, its step and its last events (with the seed): a step that sends an
## intent and gets a Rejected it did not expect, or succeeds when it expected one; a target the bot
## cannot know; a Correction outside a placement (an honest bot is never corrected); a step not
## done within the time limit.

enum Result { DONE, WAITING, FAILED }

const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const MATCH_ENDED := &"MatchEnded"
## A WalkTo is done within this much of its stop distance: float noise.
const ARRIVED_SLACK_M := 0.001
## The most steps one bot may finish in one tick, against a script that never waits.
const MAX_STEPS_PER_TICK := 32
## The fields that name a player: a scenario writes them as a bot's number, mapped through
## ScenarioPeers (`peer`; RaiseStarted's and RaiseStopped's `raiser` and `target`, M4-4).
const PLAYER_FIELDS: Array[String] = ["peer", "raiser", "target"]
## What a Join after the bot's own Leave tries again after, every RETRY_S seconds until its
## deadline_s (P12 (t2) of the returning-players ADR): a refused connection (the loopback's
## connect_failed, the core runner's refusal) and joins_closed (ENet's refusal frame, #1233; the
## WebRTC signalling's; or a Rejected Hello's). Anything else fails it at once.
const RETRIED: Array[StringName] = [ClientSession.CONNECT_FAILED, RejectReasons.JOINS_CLOSED]
const RETRY_S := 0.5

var scenario: BotScenario
var bots: Array[ScenarioBot] = []
var failures := PackedStringArray()
## The winning sides of the MatchEnded events, in order.
var ends: Array[StringName] = []
## Bot number -> peer id, this runner's (§4.6).
var peers: ScenarioPeers
## The tick of the runner's clock now, for a failure's report.
var tick_now := 0
## The fake world the host's match asks and the bots walk on (ScenarioLevels.world_of): one flat
## floor, or the House's storeys and stairs (#1209). A runner hands it to its match.
var world: WorldQuery


func _init(bot_scenario: BotScenario, bot_peers: ScenarioPeers) -> void:
	scenario = bot_scenario
	peers = bot_peers
	world = ScenarioLevels.world_of(scenario)


## Whether an event named `name` with payload `fields`, received by `receiver`, is `want_name`
## and matches `want` (a subset): a field that names a player (PLAYER_FIELDS) holds a bot's
## number, mapped through `bot_peers` to any peer that bot had (a bot that joined again is on a
## new one, and an event of its earlier connection names the old one); strings and StringNames
## compare as text; vectors and floats approximately.
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
		var got: Variant = (
			receiver.field_of(event, field) if receiver != null else event.fields.get(field)
		)
		if PLAYER_FIELDS.has(field) and wanted is int:
			if not names_bot(got, wanted as int, bot_peers):
				return false
		elif not same(got, wanted):
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
		var got: Variant = payload[field] if payload.has(field) else event.get(field)
		if PLAYER_FIELDS.has(field) and wanted is int:
			if not names_bot(got, wanted as int, bot_peers):
				return false
		elif not same(got, wanted):
			return false
	return true


## Whether a player field holding `got` names bot `bot`: one of the peers it had (peers_of), or 0
## while its peer is not known, as for a field that holds no player.
static func names_bot(got: Variant, bot: int, bot_peers: ScenarioPeers) -> bool:
	var had := bot_peers.peers_of(bot)
	if had.is_empty():
		return same(got, 0)
	return got is int and had.has(got as int)


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
	if bot.returns():
		# The tick after its Leave: all that reached its old connection was received by it.
		_begin_return(bot)
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
		if bot.gone:
			# Its Leave: a Join that follows starts a new connection, on the next tick.
			break
	if not bot.gone and not bot.dead and not bot.current_step() is StepWalkTo:
		_stand(bot)


## The host disconnected `bot` (core/'s DisconnectPeer, or its session ended): it acts no more. A
## WaitFor or Expect left in its script is checked on what it received before (Disconnecting,
## #119); any step still left then fails, so a script never ends unseen with its connection.
## Leftover steps are not started: each looks back from the cursors of the last step that started,
## so they are looser than live play (an event from before that step counts). Enough for one
## leftover wait; a script that needs order among leftovers needs a cursor per step here.
func _disconnected(bot: ScenarioBot, at_tick: int) -> void:
	tick_now = at_tick
	if bot.returning():
		# Its returning Join was refused after it connected (a Rejected Hello): tried again, or not.
		var rejected := String(bot.rejection_of(bot.sent_seq))
		_try_again(bot, rejected if not rejected.is_empty() else "disconnected", at_tick, false)
		return
	while failures.is_empty():
		var step := bot.current_step()
		if step == null:
			break
		var expected := step as StepWaitFor
		var expect := step as StepExpect
		var done := false
		if expected != null:
			done = _received(bot, bot.step_cursor, expected.event, expected.fields)
		elif expect != null:
			done = _received(bot, bot.previous_cursor, expect.event, expect.fields)
		if not done:
			_fail_step(bot, "the host disconnected the bot before this step was done")
			break
		bot.finish_step()
	bot.gone = true


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
	elif step is StepNextStage:
		result = _next_stage(bot, step as StepNextStage)
	elif step is StepWalkTo:
		result = _walk(bot, step as StepWalkTo)
	elif step is StepPickUp:
		result = _pick_up(bot, step as StepPickUp)
	elif step is StepPutDown:
		result = _put_down(bot, step as StepPutDown)
	elif step is StepThrow:
		result = _throw(bot, step as StepThrow)
	elif step is StepUse:
		result = _use(bot, step as StepUse)
	elif step is StepInteract:
		result = _interact(bot, step as StepInteract)
	elif step is StepRaise:
		result = _raise(bot, step as StepRaise, elapsed)
	elif step is StepStopRaise:
		result = _stop_raise(bot, step as StepStopRaise)
	elif step is StepGiveUp:
		result = _give_up(bot, step as StepGiveUp)
	elif step is StepSwap:
		result = _swap(bot, step as StepSwap)
	elif step is StepDraw:
		result = _draw(bot, step as StepDraw)
	elif step is StepJump:
		# D3 (a), the designer's answer on #96: the step says what a player does, and the bot
		# counts it as one more jump in its epoch, as a client's MoveClaim carries it (§4.3, E2).
		_jump(bot)
		result = Result.DONE
	elif step is StepLeave:
		bot.gone = true
		bot.left = true
		_leave(bot)
		result = Result.DONE
	elif step is StepTalk:
		bot.talking = (step as StepTalk).talking
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


## NextStage (#599): done when the next phase's PhaseChanged arrives, whichever phase it is.
func _next_stage(bot: ScenarioBot, step: StepNextStage) -> Result:
	if bot.sent_seq < 0:
		_send(bot, Intents.NEXT_STAGE, {})
		return Result.WAITING
	var moved := _received(bot, bot.step_cursor, &"PhaseChanged", {})
	return _intent_result(bot, step, moved)


func _join(bot: ScenarioBot, step: StepJoin, at_tick: int) -> Result:
	if not bot.lives.is_empty():
		return _rejoin(bot, step, at_tick)
	if not bot.connected:
		if at_tick < Ticks.from_seconds(step.at_s):
			return Result.WAITING
		var refused := _connect(bot)
		if not refused.is_empty():
			return _fail_step(bot, refused)
		return Result.WAITING
	return _intent_result(bot, step, bot.joined)


## A Join after the bot's own Leave (P12 (a), (t2)): from `at_s` it connects on a new connection;
## a refused connection or a joins_closed tries again RETRY_S later (_try_again), until
## `deadline_s`, past which it fails naming the last refusal. Done at its Welcome.
func _rejoin(bot: ScenarioBot, step: StepJoin, at_tick: int) -> Result:
	if bot.joined:
		return _intent_result(bot, step, true)
	if at_tick > Ticks.from_seconds(step.deadline_s):
		var last := bot.last_refusal if not bot.last_refusal.is_empty() else "never"
		return _fail_step(
			bot,
			(
				"its Join after its Leave did not join by its deadline (%s s); last refused: %s"
				% [step.deadline_s, last]
			)
		)
	var result := Result.WAITING
	if bot.connected:
		# A joins_closed Rejected: the host drops the connection next, and _disconnected tries again.
		if not RETRIED.has(bot.rejection_of(bot.sent_seq)):
			result = _intent_result(bot, step, false)
	elif at_tick >= Ticks.from_seconds(step.at_s) and at_tick >= bot.retry_tick:
		var refused := _connect(bot)
		if not refused.is_empty():
			result = _try_again(bot, refused, at_tick, true)
	return result


## The returning Join's try ended before its Welcome, for `reason`: a refused connection
## (`connection_refused`) or a reason in RETRIED tries again from RETRY_S later, on a new connection
## (_drop_try); any other reason fails the step.
func _try_again(bot: ScenarioBot, reason: String, at_tick: int, connection_refused: bool) -> Result:
	if not connection_refused and not RETRIED.has(StringName(reason)):
		var failed := _fail_step(bot, "its Join after its Leave ended (%s)" % reason)
		bot.gone = true
		return failed
	# A refused try is a connected peer that is no player: it decodes at most the Rejected of its
	# own Hello (§5), not another peer's (another seq) and not a second one.
	var rejecteds := 0
	for event: WireMessage in bot.events:
		if event.name != &"Rejected":
			bot.gone = true
			return _fail_step(
				bot, "its refused Join decoded %s, a peer that is not a player" % event.name
			)
		rejecteds += 1
		if rejecteds > 1 or event.fields.get("seq", -2) != bot.sent_seq:
			bot.gone = true
			return _fail_step(
				bot,
				(
					"its refused Join decoded a Rejected that is not the one of its own Hello"
					+ (
						" (seq %s, its Hello's %d, %d decoded)"
						% [event.fields.get("seq", "none"), bot.sent_seq, rejecteds]
					)
				)
			)
	var was_connected := bot.connected
	bot.refused(reason, at_tick + Ticks.from_seconds(RETRY_S))
	_drop_try(bot, was_connected)
	return Result.WAITING


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
	var cannot := _cannot_walk(bot)
	if not cannot.is_empty():
		return _fail_step(bot, cannot)
	var ticks := _travel_ticks(bot)
	if ticks <= 0:
		return Result.WAITING
	var rules := scenario.mode.player_rules
	var sprinting := step.sprint and _sprint_available(bot)
	var speed := rules.sprint_speed_mps if sprinting else rules.walk_speed_mps
	var direction := offset / distance
	var travel := minf(speed * ticks / Ticks.RATE, distance - step.stop_m)
	var to := bot.position + direction * travel
	# The claim stands on the fake world's floor there, as a client's capsule would: found from a
	# step and the steepest floor (45°, MovementRule's FLOOR_MAX_ANGLE) over the claim's travel above
	# the bot's feet, so it climbs a step or a flight of stairs (however many ticks one claim covers
	# after a stall) and walks down one (the House's storeys, #1209). A drop past that same reach is a
	# fall, which the host does not bound (§7.1) and no scenario takes: it fails, so a walk changes
	# storey only over the stairs.
	var reach := rules.step_height_m + travel
	var below := world.floor_below(Vector3(to.x, bot.position.y + reach, to.z))
	var falls := _fall(bot, to, below, reach)
	if not falls.is_empty():
		return _fail_step(bot, falls)
	to.y = below.y
	_claim(bot, to, direction * speed, sprinting)
	return Result.WAITING


## Why a bot cannot walk now, or "": the dead send no claims, and the downed only their look.
func _cannot_walk(bot: ScenarioBot) -> String:
	if bot.dead:
		return "a dead bot cannot walk: the dead send no claims"
	if bot.downed:
		return "a knocked-down bot cannot walk: the host takes only its look (KE4)"
	return ""


## Why a claim at `to` standing on `below` would fall, or "": no floor under it, or a drop deeper
## than `most_m` (a step and the claim's travel) below the bot's feet.
func _fall(bot: ScenarioBot, to: Vector3, below: Vector3, most_m: float) -> String:
	if below == WorldQuery.NO_FLOOR:
		return "no floor under the walk at %s" % to
	if bot.position.y - below.y > most_m:
		return (
			"the walk falls from %.2f to %.2f m at %s: route it over the stairs"
			% [bot.position.y, below.y, to]
		)
	return ""


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


## Faces the target flat, tilts that facing up by the step's pitch and sends Throw; done when the
## ItemThrown of the item it held arrives (the flight's ItemPlaced comes later: WaitFor it).
func _throw(bot: ScenarioBot, step: StepThrow) -> Result:
	if bot.sent_seq < 0:
		var flat := _facing(bot, step.towards)
		if flat == Vector3.INF:
			return _fail_step(bot, "the bot cannot know where to face")
		if flat == Vector3.ZERO and absf(step.pitch_deg) != 90.0:
			# Standing on the target: a flat facing of zero would make the host fall back to the
			# last facing, a direction the scenario did not ask for.
			return _fail_step(bot, "the bot cannot know where to throw")
		var pitch := deg_to_rad(step.pitch_deg)
		var facing := Vector3(flat.x * cos(pitch), sin(pitch), flat.z * cos(pitch))
		bot.sent_item = bot.held
		_send(bot, Intents.THROW, {"facing": facing})
		return Result.WAITING
	var item_id := bot.sent_item
	var peer := bot.peer
	var thrown := bot.find_since(
		bot.step_cursor,
		func(event: WireMessage) -> bool:
			return (
				event.name == &"ItemThrown"
				and event.fields["item"] == item_id
				and event.fields["peer"] == peer
			)
	)
	return _intent_result(bot, step, thrown != null)


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


## Sends Interact naming the station the bot knows by the step's kind and index, or the item it
## names (the nearest of its kind, #1209); done when the step's `until` event arrives for this bot
## (or one that names no peer), as for Use.
func _interact(bot: ScenarioBot, step: StepInteract) -> Result:
	if bot.sent_seq < 0:
		if step.item != null:
			var item := bot.item_of(step.item)
			if item < 0:
				return _fail_step(bot, "the bot cannot know which item to use")
			_send(bot, Intents.INTERACT, {"station": -1, "item": item})
			return Result.WAITING
		var station := bot.station_of(step.station)
		if station < 0:
			return _fail_step(bot, "the bot cannot know which station to use")
		_send(bot, Intents.INTERACT, {"station": station, "item": -1})
		return Result.WAITING
	var until := step.until
	var done := bot.find_since(
		bot.step_cursor,
		func(event: WireMessage) -> bool:
			if until.is_empty() or event.name != until:
				return false
			var by: Variant = bot.field_of(event, "peer")
			return not by is int or by == bot.peer
	)
	return _intent_result(bot, step, done != null)


## Sends Raise of the target bot's player, then holds it: done once its RaiseStarted arrived and
## hold_s passed since the step started, or the raise ended before (RaiseStopped, Revived).
func _raise(bot: ScenarioBot, step: StepRaise, elapsed: int) -> Result:
	if bot.sent_seq < 0:
		var other := peers.peer_of(step.target.bot)
		if other == 0:
			return _fail_step(bot, "the bot cannot know which player its target is")
		bot.sent_peer = other
		_send(bot, Intents.RAISE, {"target": other})
		return Result.WAITING
	var raiser := bot.peer
	var target := bot.sent_peer
	var started := bot.find_since(
		bot.step_cursor,
		func(event: WireMessage) -> bool:
			return (
				event.name == &"RaiseStarted"
				and event.fields["raiser"] == raiser
				and event.fields["target"] == target
			)
	)
	var result := _intent_result(bot, step, started != null)
	if result != Result.DONE or not step.expect_rejected.is_empty():
		return result
	var ended := bot.find_since(
		bot.step_cursor,
		func(event: WireMessage) -> bool:
			if event.name == &"RaiseStopped":
				return event.fields["raiser"] == raiser
			return event.name == &"Revived" and event.fields["peer"] == target
	)
	if ended != null or elapsed >= Ticks.from_seconds(step.hold_s):
		return Result.DONE
	return Result.WAITING


func _stop_raise(bot: ScenarioBot, step: StepStopRaise) -> Result:
	if bot.sent_seq < 0:
		_send(bot, Intents.STOP_RAISE, {})
		return Result.WAITING
	var raiser := bot.peer
	var stopped := bot.find_since(
		bot.step_cursor,
		func(event: WireMessage) -> bool:
			return event.name == &"RaiseStopped" and event.fields["raiser"] == raiser
	)
	return _intent_result(bot, step, stopped != null)


func _give_up(bot: ScenarioBot, step: StepGiveUp) -> Result:
	if bot.sent_seq < 0:
		_send(bot, Intents.GIVE_UP, {})
		return Result.WAITING
	return _intent_result(bot, step, _done_by(bot, &"Died", {}))


func _swap(bot: ScenarioBot, step: StepSwap) -> Result:
	if bot.sent_seq < 0:
		_send(bot, Intents.SWAP, {})
		return Result.WAITING
	return _intent_result(bot, step, _done_by(bot, &"Swapped", {}))


func _draw(bot: ScenarioBot, step: StepDraw) -> Result:
	if bot.sent_seq < 0:
		_send(bot, Intents.DRAW, {"place": step.place})
		return Result.WAITING
	return _intent_result(bot, step, _done_by(bot, &"Swapped", {"place": step.place}))


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


## A returning bot starts its next connection (ScenarioBot.begin_return), the tick after its Leave.
func _begin_return(bot: ScenarioBot) -> void:
	bot.begin_return(0)


## A returning Join's try was refused (ScenarioBot.refused): the runner drops what it made for it;
## `was_connected` when the host had seen the connection.
func _drop_try(_bot: ScenarioBot, _was_connected: bool) -> void:
	pass


## Connects the bot (a Join step's time has come): its Hello follows. Returns why the host refused
## it, or "".
func _connect(_bot: ScenarioBot) -> String:
	return "a runner connects bots"


## The bot moves to `to` (an honest MoveClaim), and takes it as its position.
func _claim(_bot: ScenarioBot, _to: Vector3, _velocity: Vector3, _sprint: bool) -> void:
	pass


## How many ticks of travel the bot may cover now: one per host tick in the core runner; over the
## network the client ticks the frame's claim covers (NetPlay._travel_ticks).
func _travel_ticks(_bot: ScenarioBot) -> int:
	return 1


## Whether the bot's next claim of travel would be in the sprint state if it held sprint: in the
## core runner the last SelfStatus says so (it answers the bot's claim of the tick before); a
## network bot predicts it from its own stamina (NetPlay, #155).
func _sprint_available(bot: ScenarioBot) -> bool:
	return bot.sprint_available


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
