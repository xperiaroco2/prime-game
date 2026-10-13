extends GdUnitTestSuite
## The body in motion in core/ (the knockdown rework's §4, KE3, KE9, KE12, KE14, KE15; ARCHITECTURE
## §9.4; #847), with scripted reports: the test plays server/, feeding BodyMoved. On a map
## PlayerRules.motion_maps leaves out (FixtureModes.MAP) a knockdown is today's; on the listed one
## (FixtureModes.MOTION_MAP) it starts a motion with KE9's launch, LaunchBody, and a Raise is
## rejected `moving` until the body rests. The knife launches 3 m/s away and 2 m/s up here; the
## fixture's rest is 0.1 m/s for 0.5 s (10 reports), its longest motion 8 s (160 ticks).

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]
const NORTH := Vector3(0, 0, 1)
const STANDS := Vector3(0, 0, 1)
## P1 at the origin strikes P2 at STANDS: away is +z.
const LAUNCH := Vector3(0, 2, 3)
const REST_REPORTS := 10
const LONGEST_TICKS := 160
const SLOW := Vector3(0.05, 0, 0)
const FAST := Vector3(0, 0, 1)


func test_on_a_map_motion_maps_leaves_out_the_knockdown_is_todays() -> void:
	var game := _knocked_down(FixtureModes.MAP)
	var downed := game.state.player(P2)
	assert_object(downed.motion).is_null()
	assert_vector(downed.position).is_equal(STANDS)
	assert_vector(downed.velocity).is_equal(Vector3.ZERO)
	var correction := FixtureCombatModes.received(game, P2, &"Correction").back() as CorrectionEvent
	assert_vector(correction.velocity).is_equal(Vector3.ZERO)
	assert_array(_emitted(game, &"LaunchBody")).is_empty()
	# A report names nothing in motion: dropped, no error.
	_report(game, P2, downed.epoch, Vector3(0, 0, 5), FAST)
	assert_vector(downed.position).is_equal(STANDS)
	assert_array(Array(game.diagnostics)).is_empty()


func test_on_the_listed_map_a_launching_strike_starts_a_motion_and_launch_body() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	var downed := game.state.player(P2)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_object(downed.motion).is_not_null()
	assert_int(downed.motion.epoch).is_equal(downed.epoch)
	assert_vector(downed.motion.fallback).is_equal(STANDS)
	# The body starts at the last accepted position with KE9's launch.
	assert_vector(downed.position).is_equal(STANDS)
	assert_vector(downed.velocity).is_equal(LAUNCH)
	var knocked := FixtureCombatModes.received(game, P3, &"KnockedDown").back() as KnockedDownEvent
	assert_vector(knocked.position).is_equal(STANDS)
	var correction := FixtureCombatModes.received(game, P2, &"Correction").back() as CorrectionEvent
	assert_vector(correction.velocity).is_equal(LAUNCH)
	var launched := _emitted(game, &"LaunchBody")
	assert_int(launched.size()).is_equal(1)
	assert_array(Array(launched[0].recipients)).is_empty()
	var launch := launched[0].event as LaunchBodyEvent
	assert_int(launch.peer).is_equal(P2)
	assert_int(launch.epoch).is_equal(downed.epoch)
	assert_vector(launch.origin).is_equal(STANDS)
	assert_vector(launch.velocity).is_equal(LAUNCH)
	# No peer receives the directive.
	for peer: int in PEERS:
		assert_array(FixtureCombatModes.received(game, peer, &"LaunchBody")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_an_empty_motion_maps_moves_bodies_on_every_map() -> void:
	var mode := _mode()
	mode.player_rules.motion_maps = PackedStringArray()
	var game := _knocked_down(FixtureModes.MAP, mode)
	assert_object(game.state.player(P2).motion).is_not_null()
	assert_int(_emitted(game, &"LaunchBody").size()).is_equal(1)


func test_a_raise_of_a_moving_body_is_rejected_moving_until_it_rests() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	FixtureItemModes.stand(game, P3, Vector3(1, 0, 1))
	FixtureCombatModes.raise(game, P3, P2)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([TargetDowned.MOVING])
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	_rest_by_reports(game, STANDS)
	FixtureCombatModes.raise(game, P3, P2)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([TargetDowned.MOVING])
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()


func test_reports_move_the_point_and_the_velocity_where_everyone_sees_it() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	var downed := game.state.player(P2)
	var flying := Vector3(0, 1.2, 1.6)
	_report(game, P2, downed.epoch, flying, Vector3(0, 0.5, 2.5))
	assert_vector(downed.position).is_equal(flying)
	assert_vector(downed.velocity).is_equal(Vector3(0, 0.5, 2.5))
	assert_object(downed.motion).is_not_null()
	FixtureModes.run_ticks(game, 1)
	for peer: int in PEERS:
		var avatars: Dictionary = game.snapshot_for(peer)["avatars"]
		assert_vector(avatars[P2]["position"] as Vector3).is_equal(flying)
	# The own avatar reaches the knocked-down viewer (KE5), and only it.
	assert_bool((game.snapshot_for(P1)["avatars"] as Dictionary).has(P1)).is_false()
	assert_bool((game.snapshot_for(P2)["avatars"] as Dictionary).has(P2)).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_report_of_an_old_epoch_or_of_a_body_at_rest_is_dropped_silently() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	var downed := game.state.player(P2)
	_report(game, P2, downed.epoch - 1, Vector3(0, 0, 4), FAST)
	assert_vector(downed.position).is_equal(STANDS)
	assert_vector(downed.velocity).is_equal(LAUNCH)
	_rest_by_reports(game, Vector3(0, 0, 2))
	_report(game, P2, downed.epoch, Vector3(0, 0, 6), FAST)
	assert_vector(downed.position).is_equal(Vector3(0, 0, 2))
	assert_vector(downed.velocity).is_equal(Vector3.ZERO)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_report_that_is_not_finite_rests_at_the_fallback_with_an_error() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	var downed := game.state.player(P2)
	_report(game, P2, downed.epoch, Vector3(0, 0, 3), FAST)
	var stops := _emitted(game, &"StopBody").size()
	_report(game, P2, downed.epoch, Vector3(NAN, 0, 3), FAST)
	assert_object(downed.motion).is_null()
	assert_vector(downed.position).is_equal(STANDS)
	assert_vector(downed.velocity).is_equal(Vector3.ZERO)
	assert_int(_emitted(game, &"StopBody").size()).is_equal(stops + 1)
	assert_int(game.diagnostics.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("BodyMoved: player 2 reported")


func test_the_rest_comes_once_the_reports_stay_slow_for_the_rest_time_and_not_before() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	var downed := game.state.player(P2)
	var lying := Vector3(0.5, 0.02, 2.5)
	for i in REST_REPORTS - 1:
		_report(game, P2, downed.epoch, lying, SLOW)
	assert_object(downed.motion).is_not_null()
	# A fast report starts the rest time again.
	_report(game, P2, downed.epoch, lying, FAST)
	for i in REST_REPORTS - 1:
		_report(game, P2, downed.epoch, lying, SLOW)
	assert_object(downed.motion).is_not_null()
	assert_array(_emitted(game, &"StopBody")).is_empty()
	_report(game, P2, downed.epoch, lying, SLOW)
	# At rest on the standing floor under its capsule, still, and server/ frees the body.
	assert_object(downed.motion).is_null()
	assert_vector(downed.position).is_equal(Vector3(0.5, 0, 2.5))
	assert_vector(downed.velocity).is_equal(Vector3.ZERO)
	var stopped := _emitted(game, &"StopBody")
	assert_int(stopped.size()).is_equal(1)
	assert_int((stopped[0].event as StopBodyEvent).peer).is_equal(P2)
	assert_array(Array(stopped[0].recipients)).is_empty()
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_array(Array(game.diagnostics)).is_empty()


func test_ticks_without_reports_count_to_the_longest_motion_never_to_the_rest() -> void:
	# A slow report at an apex, then a host freeze's catch-up ticks with no report: no rest.
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	var downed := game.state.player(P2)
	var apex := Vector3(0, 1.5, 2)
	_report(game, P2, downed.epoch, apex, SLOW)
	FixtureModes.run_ticks(game, REST_REPORTS * 2)
	assert_object(downed.motion).is_not_null()
	assert_vector(downed.position).is_equal(apex)
	# The longest motion: every tick counts, so it ends LONGEST_TICKS after the knockdown.
	FixtureModes.run_ticks(game, LONGEST_TICKS - 1 - downed.motion.ticks)
	assert_object(downed.motion).is_not_null()
	FixtureModes.run_ticks(game, 1)
	assert_object(downed.motion).is_null()
	assert_vector(downed.position).is_equal(Vector3(0, 0, 2))
	assert_vector(downed.velocity).is_equal(Vector3.ZERO)
	assert_int(_emitted(game, &"StopBody").size()).is_equal(1)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_array(Array(game.diagnostics)).is_empty()


func test_no_floor_under_the_rest_rests_at_the_fallback_with_an_error() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	var downed := game.state.player(P2)
	var fallen := Vector3(0, -5, 3)
	for i in REST_REPORTS:
		_report(game, P2, downed.epoch, fallen, SLOW)
	assert_object(downed.motion).is_null()
	assert_vector(downed.position).is_equal(STANDS)
	assert_int(_emitted(game, &"StopBody").size()).is_equal(1)
	assert_int(game.diagnostics.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("rest: no floor under the body of player 2")


func test_a_death_during_a_motion_emits_stop_body() -> void:
	# KD8: the knockdown time runs out before the longest motion, and the body dies in motion.
	var mode := _mode()
	mode.player_rules.knockdown_s = 2.0
	var game := _knocked_down(FixtureModes.MOTION_MAP, mode)
	var downed := game.state.player(P2)
	_report(game, P2, downed.epoch, Vector3(0, 0, 2), FAST)
	FixtureModes.run_ticks(game, downed.life_deadline - game.ticked_through())
	assert_int(downed.life).is_equal(PlayerState.Life.DEAD)
	assert_object(downed.motion).is_null()
	assert_int(_emitted(game, &"StopBody").size()).is_equal(1)
	assert_bool(game.state.bodies.has(P2)).is_true()
	# The body dies where it was last reported (KD8 (a)), not at the knockdown's fallback.
	var body: Vector3 = game.state.bodies[P2]
	assert_float(body.x).is_equal_approx(0.0, 0.05)
	assert_float(body.z).is_equal_approx(2.0, 0.05)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_negated_target_downed_refuses_not_allowed() -> void:
	var negated := TargetDowned.new()
	negated.negate = true
	assert_str(negated.rejection_reason_in(null)).is_equal(String(RejectReasons.NOT_ALLOWED))
	assert_str(TargetDowned.new().rejection_reason()).is_equal(String(TargetDowned.NOT_DOWNED))


func test_a_give_up_during_a_motion_emits_stop_body() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	FixtureCombatModes.give_up(game, P2)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_object(game.state.player(P2).motion).is_null()
	assert_int(_emitted(game, &"StopBody").size()).is_equal(1)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_leave_during_a_motion_emits_stop_body() -> void:
	var game := _knocked_down(FixtureModes.MOTION_MAP)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_object(game.state.player(P2).motion).is_null()
	assert_int(_emitted(game, &"StopBody").size()).is_equal(1)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_command_log_replays_the_same_rest_with_no_physics() -> void:
	# Everything by commands, so the log holds it all: the placement, the host's NextStage whose
	# KnockDown downs P2 where the markers put it (no launch), and the reports.
	var mode := FixtureStageModes.staged([FixtureStageModes.knock_down(1)])
	_play_first(mode, FixtureModes.MOTION_MAP)
	var game := FixtureModes.in_round(mode, PEERS)
	FixtureStageModes.next_stage(game, P1)
	var downed := game.state.player(P2)
	assert_object(downed.motion).is_not_null()
	var fell := downed.position + Vector3(0.3, 0.01, 1.2)
	_report(game, P2, downed.epoch, downed.position + Vector3(0, 0.8, 1), FAST)
	_rest_by_reports(game, fell)
	FixtureModes.run_ticks(game, 3)
	var replayed := Match.replay(game.command_log, mode)
	assert_array(Array(replayed.refusals)).is_empty()
	assert_array(FixtureModes.names(replayed)).is_equal(FixtureModes.names(game))
	var again := replayed.state.player(P2)
	assert_vector(again.position).is_equal(downed.position)
	assert_vector(again.position).is_equal(Vector3(fell.x, 0, fell.z))
	assert_object(again.motion).is_null()


## The fixture combat mode with the raise (FixtureCombatModes.raising) whose knife launches LAUNCH.
func _mode() -> GameMode:
	var mode := FixtureCombatModes.raising()
	var strike := mode.find_item_kind(&"knife").actions[0].effects[0] as Strike
	strike.launch_mps = LAUNCH.z
	strike.launch_up_mps = LAUNCH.y
	return mode


## A round of `mode` (_mode() by default) on `map`, put first among the mode's maps so the match
## starts there, P1 armed at the origin, P2 at STANDS knocked down by two hits facing north, P3
## far away.
func _knocked_down(map: String, mode: GameMode = null) -> Match:
	var played := mode if mode != null else _mode()
	_play_first(played, map)
	var game := Match.new(played, 7, FlatWorldQuery.new(), FixtureModes.layouts())
	game.keep_history = true
	game.start(0)
	for peer: int in PEERS:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in PEERS:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(str(game.state.map)).is_equal(map)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, STANDS)
	FixtureItemModes.stand(game, P3, Vector3(8, 0, 8))
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	return game


## server/'s report of `peer`'s body, logged and applied on the next tick.
func _report(game: Match, peer: int, epoch: int, at: Vector3, velocity: Vector3) -> void:
	var args := {"epoch": epoch, "position": at, "velocity": velocity}
	game.apply(MatchCommand.new(Intents.BODY_MOVED, peer, game.ticked_through() + 1, args))


## Slow reports of P2's body at `at` for the rest time: it rests.
func _rest_by_reports(game: Match, at: Vector3) -> void:
	var downed := game.state.player(P2)
	for i in REST_REPORTS:
		_report(game, P2, downed.epoch, at, SLOW)
	assert_object(downed.motion).is_null()


## Every emitted event named `event_name`, recipients included.
func _emitted(game: Match, event_name: StringName) -> Array[EmittedEvent]:
	var found: Array[EmittedEvent] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event.event_name() == event_name:
			found.append(emitted)
	return found


## Puts `map` first among `mode`'s maps (the match starts on the first, GameMode.default_map),
## keeping the others: both fixture maps stay the mode's.
static func _play_first(mode: GameMode, map: String) -> void:
	var maps := PackedStringArray([map])
	for other: String in mode.maps:
		if other != map:
			maps.append(other)
	mode.maps = maps
