extends GdUnitTestSuite
## The zone task over the wire (#804, Generator G9: the checks of the zone scenarios and of the
## chaos run's freeze, which needed bots, moved here; the zone task ADR's §7 and ZE10's freeze row;
## ARCHITECTURE §4.6, §9.5): ClientSessions against a HostSession over a LoopbackHub, the
## harness's fixture mode with FixtureZoneModes' zone task dealt on `loading, all_loaded ->
## pregame` and TaskTicks in Round, on the harness's layouts with one `zone` marker ZONE_AT, clear
## of every player's spot. One client walks into the zone with its own claims:
## - it holds the zone until it fills, and what each client decoded (ZoneProgress counting, then
##   done, TaskState, TaskProgress) is its Match.view_of;
## - its process freezes inside the zone (it sends no claim while the host runs on): the zone gains
##   at most ZoneTask.STALE_TICKS after its last accepted claim and stops counting, and after the
##   thaw each client's view is still its view_of.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## The zone's marker: 4 m from the round_player markers' row ((10 + i, 0, 5)), so nobody stands in
## it before the walk.
const ZONE_AT := Vector3(11, 0, 9)
## The walker's pace, under the fixture's walk speed (4.5 m/s).
const PACE_MPS := 2.0
## A zone that needs longer than the freeze and the walk, for the freeze's test.
const LONG_SECONDS := 30.0
## How long the walker's process stays frozen: many times ZoneTask.STALE_TICKS.
const FREEZE_S := 2.0

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_zone_filled_by_a_walker_reaches_every_client_as_its_view() -> void:
	var walker := _in_round(FixtureZoneModes.SECONDS)
	var game := _h.session.game
	var task_state := FixtureZoneModes.state_of(game)
	_walk_into_zone(walker)
	assert_bool(_h.pump_until(func() -> bool: return task_state.done[0], 200)).is_true()
	_h.pump_seconds(0.5)
	for client: ClientSession in _h.clients:
		var progress := client.view.events_named(&"ZoneProgress")
		# The walker's start, then the done.
		assert_int(progress.size()).is_greater_equal(2)
		assert_bool(_counting_seen(progress)).is_true()
		var last := progress[progress.size() - 1].fields
		assert_int(last["ticks"] as int).is_equal(last["needed"] as int)
		assert_array(client.view.events_named(&"TaskState")).is_not_empty()
		assert_array(client.view.events_named(&"TaskProgress")).is_not_empty()
		assert_array(_h.mismatches(client)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()
	_assert_replays(game)


func test_a_client_frozen_in_a_zone_gains_it_at_most_the_stale_ticks() -> void:
	var walker := _in_round(LONG_SECONDS)
	var game := _h.session.game
	var task_state := FixtureZoneModes.state_of(game)
	var peer := _h.peer_of(walker)
	_walk_into_zone(walker)
	# The zone's tick count at the end of each host tick, from before the freeze: the gain is
	# counted from the tick of the last accepted claim itself, not from the pump that first sees it.
	var ticks_at: Dictionary[int, int] = {}
	for _i in ceili(0.5 * Harness.SECOND / Harness.FRAME_USEC):
		_h.pump()
		ticks_at[game.ticked_through()] = task_state.ticks[0]
	assert_bool(task_state.counting[0]).is_true()
	# The freeze: the walker's process stops (no claim, no poll); the host and the other client
	# run on. The zone's gain is counted from the host tick of the last accepted claim.
	_h.frozen.append(walker)
	var claimed := -1
	for _i in ceili(FREEZE_S * Harness.SECOND / Harness.FRAME_USEC):
		_h.pump()
		var now_tick := game.ticked_through()
		ticks_at[now_tick] = task_state.ticks[0]
		claimed = now_tick - MovementRule.claim_age(game.state, peer, now_tick)
	(
		assert_bool(ticks_at.has(claimed))
		. override_failure_message(
			"the last claim's tick %d was not at the end of a pump" % claimed
		)
		. is_true()
	)
	var gained := task_state.ticks[0] - ticks_at[claimed]
	(
		assert_int(gained)
		. override_failure_message(
			(
				"the zone gained %d ticks after the last claim, at most %d"
				% [gained, ZoneTask.STALE_TICKS]
			)
		)
		. is_less_equal(ZoneTask.STALE_TICKS)
	)
	assert_bool(task_state.counting[0]).is_false()
	assert_bool(task_state.done[0]).is_false()
	# The thaw: the walker polls and claims again where it stood, and the zone counts again.
	var corrected := walker.view.events_named(&"Correction").size()
	_h.frozen.clear()
	_h.pump_seconds(1.0)
	assert_bool(task_state.counting[0]).is_true()
	for client: ClientSession in _h.clients:
		var progress := client.view.events_named(&"ZoneProgress")
		assert_bool(_stopped_seen(progress)).is_true()
		assert_array(_h.mismatches(client)).is_empty()
	# The host corrects nothing after the thaw: the claim made where the walker stood is accepted.
	assert_int(walker.view.events_named(&"Correction").size()).is_equal(corrected)
	assert_array(Array(game.diagnostics)).is_empty()
	_assert_replays(game)


## The match replayed from its command log (the wire's commands alone drive this match) gives the
## same events, in order, to the same peers on the same ticks (ARCHITECTURE §3.3): the zone's
## tick-dependent counting, its 5-tick ZoneProgress window and STALE_TICKS stay deterministic.
func _assert_replays(game: Match) -> void:
	var replayed := Match.replay(game.command_log, game.mode)
	assert_array(Array(replayed.refusals)).is_empty()
	var errors: Array[String] = []
	for line: String in replayed.diagnostics:
		if line.begins_with("error:"):
			errors.append(line)
	assert_array(errors).is_empty()
	var recorded := game.emitted()
	var again := replayed.emitted()
	assert_int(again.size()).is_equal(recorded.size())
	for i in mini(recorded.size(), again.size()):
		var same := (
			again[i].event.describe() == recorded[i].event.describe()
			and again[i].recipients == recorded[i].recipients
			and again[i].tick == recorded[i].tick
		)
		if not same:
			fail(
				(
					"event %d differs in the replay: %s to %s on %d, recorded %s to %s on %d"
					% [
						i,
						again[i].event.describe(),
						again[i].recipients,
						again[i].tick,
						recorded[i].event.describe(),
						recorded[i].recipients,
						recorded[i].tick
					]
				)
			)
			return


## The harness on _mode(`seconds`) and _layouts() with a second client, both in the round, the
## zone dealt and nobody in it: returns the second, which walks.
func _in_round(seconds: float) -> ClientSession:
	_h = Harness.new(_mode(seconds), true, null, _layouts())
	assert_array(_h.session.errors).is_empty()
	assert_bool(_h.started).is_true()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(0.5)
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 800)).is_true()
	_h.pump_seconds(0.5)
	var game := _h.session.game
	assert_object(FixtureZoneModes.task_of(game)).is_not_null()
	var zone := FixtureZoneModes.zone_of(game, 0)
	for peer: int in game.state.peers():
		assert_bool(zone.contains(game.state.player(peer).position)).is_false()
	assert_bool(FixtureZoneModes.state_of(game).counting[0]).is_false()
	return second


## `client` walks from where the host has it to the zone's centre at PACE_MPS, its claims going
## out on its own client ticks, then stands there.
func _walk_into_zone(client: ClientSession) -> void:
	var game := _h.session.game
	var at := game.state.player(_h.peer_of(client)).position
	var to := FixtureZoneModes.zone_of(game, 0).position
	var step := PACE_MPS * Harness.FRAME_USEC / Harness.SECOND
	while not at.is_equal_approx(to):
		var left := to - at
		var move := left if left.length() <= step else left.normalized() * step
		at += move
		var velocity := move.normalized() * PACE_MPS
		client.set_motion(at, velocity, move.normalized(), false, true, true)
		_h.pump()
	client.set_motion(at, Vector3.ZERO, Vector3.FORWARD, false, false, true)
	_h.pump_seconds(0.2)


## The harness's fixture mode with FixtureZoneModes' zone task (one zone of `seconds`), the
## settings `tasks` (1), `banned_task_types` and `zones` (1), the deal first on the `all_loaded`
## row and TaskTicks in Round.
static func _mode(seconds: float) -> GameMode:
	var made := Harness.fixture_mode()
	if made.find_setting(&"tasks") == null:
		made.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if made.find_setting(&"banned_task_types") == null:
		made.settings.append(FixtureDealModes.banned_setting())
	made.settings.append(FixtureModes.setting(&"zones", 1, 1, 1))
	made.task_types = [FixtureZoneModes.zone_task(seconds)]
	var loaded := made.find_transition(&"loading", LoadingPhase.ALL_LOADED)
	loaded.actions.insert(0, FixtureDealModes.deal_tasks())
	made.find_phase(&"round").tick_systems.append(TaskTicks.new())
	return made


## The harness's layouts with one `zone` marker ZONE_AT on each map.
static func _layouts() -> Dictionary[String, LevelLayout]:
	var found := Harness.layouts()
	for map: String in [Harness.MAP, Harness.SMALL_MAP]:
		found[map].add_marker(&"zone", ZONE_AT)
	return found


static func _counting_seen(progress: Array[WireMessage]) -> bool:
	for event: WireMessage in progress:
		if event.fields["counting"] as bool:
			return true
	return false


## Whether a ZoneProgress not counting came after one counting.
static func _stopped_seen(progress: Array[WireMessage]) -> bool:
	var counted := false
	for event: WireMessage in progress:
		var counting := event.fields["counting"] as bool
		if counting:
			counted = true
		elif counted:
			return true
	return false
