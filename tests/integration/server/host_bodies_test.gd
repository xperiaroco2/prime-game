extends GdUnitTestSuite
## The host's bodies (HostBodies; the knockdown rework's KE13, KE15, KD11, KD13 (a), §9; #847) in
## the host's world: first the probe that a rigid body in a World3D.new() space falls as the
## physics frames step it; then, on the fixture level body_rest_course.tscn (a ledge, a ramp,
## stairs, a wall, a hole, a low table, a low ceiling and a thin railing), through HostBodies and a
## Match on a fixture mode whose motion_maps lists it, a knife's launching blow and the host's loop
## written out (three physics frames per host tick, the bodies' reports at the head of each tick's
## batch, LaunchBody and StopBody carried out as HostSession carries them out). Each case waits
## real physics frames and asserts where the body may rest (on a floor, inside the level, within
## the longest motion, a crouching player's capsule fitting there), never an exact point. A
## StopBody, a death and a level change free the host's body.

const COURSE := "res://tests/fixtures/levels/body_rest_course.tscn"
const P1 := 1
const P2 := 2
## 60 physics frames a second, 20 host ticks.
const FRAMES_PER_TICK := 3
## The fixture's longest motion here (2 s, 40 ticks): a placeholder of the test.
const LONGEST_S := 2.0
## A frame budget past the longest motion: a motion still running then is a failure.
const FRAME_LIMIT := 200
## FixtureModes.player_rules(): the capsule's radius and the crouching height.
const RADIUS := 0.4
const CROUCH_HEIGHT := 1.2
## The course's ground: x from -20 to 40, z from -30 to 30 (with the hole from z 10 to 14).
const GROUND := AABB(Vector3(-20, -0.01, -30), Vector3(60, 20, 60))

var _game: Match
var _world: HostWorldQuery
var _level: LevelWorld
var _strike: Strike
var _seen := 0
## Whether a body ever turned (its basis left the identity).
var _turned := false
## The highest top of P2's body seen, and the physics frames its motion lasted.
var _highest_top := -INF
var _frames := 0


func after_test() -> void:
	if _world != null:
		_world.bodies.clear()
	_game = null
	_world = null
	_level = null


func test_a_rigid_body_in_a_new_world_falls_as_the_physics_frames_step() -> void:
	var world := World3D.new()
	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_space(body, world.space)
	var start := Transform3D(Basis.IDENTITY, Vector3(0, 10, 0))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, start)
	for i in 30:
		await get_tree().physics_frame
	var placed: Transform3D = PhysicsServer3D.body_get_state(
		body, PhysicsServer3D.BODY_STATE_TRANSFORM
	)
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	assert_float(placed.origin.y).is_less(9.5)


func test_with_no_world_a_launched_body_is_held_still_and_reported_at_rest() -> void:
	# A host on a world with no physics (the bots' FlatWorldQuery), or with no level: nothing moves
	# the body, so it is reported where it started, still, until StopBody.
	var bodies := HostBodies.new()
	bodies.launch(P2, 4, Vector3(1, 0, 2), Vector3(3, 1, 0))
	assert_array(bodies.peers()).is_equal([P2])
	var reports := bodies.reports()
	assert_int(reports.size()).is_equal(1)
	assert_int(reports[0].peer).is_equal(P2)
	assert_str(str(reports[0].kind)).is_equal(str(Intents.BODY_MOVED))
	assert_int(reports[0].get_int("epoch")).is_equal(4)
	assert_vector(reports[0].get_vector3("position")).is_equal(Vector3(1, 0, 2))
	assert_vector(reports[0].get_vector3("velocity")).is_equal(Vector3.ZERO)
	bodies.stop(P2)
	assert_array(bodies.reports()).is_empty()


func test_a_body_launched_off_the_ledge_rests_on_the_floor_below() -> void:
	_start()
	_knock_down(Vector3(1, 2, 0), Vector3.RIGHT, 4.0, 1.0)
	await _until_rest()
	var at := _rest_point()
	_assert_rests_well(at)
	assert_float(at.y).is_less(0.05)
	assert_float(at.x).is_greater(2.0)


func test_a_body_launched_down_the_ramp_ends_lower_on_it_or_at_its_foot() -> void:
	_start()
	var start := Vector3(28, 1.84, 0)
	_knock_down(start, Vector3.RIGHT, 6.0, 1.5, Vector3(27.3, 2.09, 0))
	await _until_rest()
	var at := _rest_point()
	_assert_rests_well(at)
	assert_float(at.y).is_less(start.y - 0.3)


func test_a_body_launched_down_the_stairs_ends_lower_on_them_or_at_their_foot() -> void:
	_start()
	var start := Vector3(-0.6, 1, -10)
	_knock_down(start, Vector3.RIGHT, 5.0, 2.0)
	await _until_rest()
	var at := _rest_point()
	_assert_rests_well(at)
	assert_float(at.y).is_less_equal(0.81)
	assert_float(at.x).is_greater(0.0)


func test_a_body_with_no_launch_on_a_flat_floor_rests_where_it_stood_upright() -> void:
	_start()
	var start := Vector3(-10, 0, 5)
	_knock_down(start, Vector3.RIGHT, 0.0, 0.0)
	await _until_rest()
	var at := _rest_point()
	_assert_rests_well(at)
	assert_float(Vector2(at.x - start.x, at.z - start.z).length()).is_less(0.1)
	assert_float(at.y).is_less(0.05)


func test_a_body_launched_at_the_wall_rests_on_its_near_side() -> void:
	_start()
	_knock_down(Vector3(8, 0, 0), Vector3.RIGHT, 6.0, 1.0)
	await _until_rest()
	var at := _rest_point()
	_assert_rests_well(at)
	assert_float(at.x).is_less(9.85)


func test_a_body_launched_at_the_low_table_never_rests_under_it() -> void:
	# The table's underside (1 m) is lower than a crouching player is tall (1.2 m) and higher than
	# the capsule is wide (0.8 m): a capsule free to turn would roll under it (KD11).
	_start()
	_knock_down(Vector3(17.5, 0, 0), Vector3.RIGHT, 6.0, 0.5)
	await _until_rest()
	var at := _rest_point()
	_assert_rests_well(at)
	# Its centre under the top, below its underside: rolled under.
	var under := absf(at.x - 20.0) < 1.0 and absf(at.z) < 1.0 and at.y < 1.0
	assert_bool(under).override_failure_message("rests under the table at %s" % at).is_false()


func test_a_body_crouched_under_a_low_ceiling_starts_below_it() -> void:
	_start()
	_game.state.player(P1).crouched = true
	_game.state.player(P2).crouched = true
	_knock_down(Vector3(-9, 0, -20), Vector3.RIGHT, 2.0, 1.0, Vector3(-10, 0, -20))
	await _until_rest()
	var at := _rest_point()
	_assert_rests_well(at)
	# Its capsule's top never rose through the ceiling's underside (1.3 m).
	assert_float(_highest_top).is_less(1.3 + 0.05)
	assert_float(at.y).is_less(0.05)


func test_a_body_over_the_hole_ends_at_the_longest_motion_at_the_fallback() -> void:
	_start()
	var start := Vector3(0, 0, 9.5)
	_knock_down(start, Vector3.BACK, 5.0, 2.0)
	await _until_rest()
	var downed := _game.state.player(P2)
	assert_object(downed.motion).is_null()
	assert_int(_frames).is_greater_equal(int(LONGEST_S * 20) * FRAMES_PER_TICK - FRAMES_PER_TICK)
	assert_vector(downed.position).is_equal_approx(start, Vector3.ONE * 0.001)
	assert_array(_world.bodies.peers()).is_empty()
	assert_int(_game.diagnostics.size()).is_equal(1)
	assert_str(_game.diagnostics[0]).contains("rest: no floor under the body of player 2")


func test_a_body_on_a_stairs_nosing_with_its_centre_past_the_edge_rests_on_the_step() -> void:
	# Scripted reports in the host's world (KE15's stand_floor_below): the step's top is 0.6 m, the
	# step below 0.4 m.
	_start()
	_knock_down(Vector3(-5, 0, -5), Vector3.RIGHT, 0.0, 0.0)
	_report_until_rest(Vector3(1.1, 0.6, -10))
	assert_float(_rest_point().y).is_equal_approx(0.6, 0.01)


func test_a_body_on_a_thin_railing_with_its_centre_past_it_rests_on_the_railing() -> void:
	_start()
	_knock_down(Vector3(-5, 0, -5), Vector3.RIGHT, 0.0, 0.0)
	_report_until_rest(Vector3(-9.6, 1.025, -10))
	assert_float(_rest_point().y).is_equal_approx(1.025, 0.01)


func test_a_stop_body_a_death_and_a_level_change_free_the_hosts_body() -> void:
	_start()
	_knock_down(Vector3(-10, 0, 5), Vector3.RIGHT, 3.0, 1.0)
	assert_array(_world.bodies.peers()).is_equal([P2])
	for i in 6:
		await get_tree().physics_frame
	# A death (the give-up): StopBody, carried out.
	FixtureCombatModes.give_up(_game, P2)
	_carry_out()
	assert_int(_game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_array(_world.bodies.peers()).is_empty()
	# StopBody alone, and a level change, with the directive carried out by hand.
	_world.bodies.launch(P1, 1, Vector3(-10, 0, 8), Vector3.ZERO)
	assert_array(_world.bodies.peers()).is_equal([P1])
	_world.bodies.stop(P1)
	assert_array(_world.bodies.peers()).is_empty()
	_world.bodies.launch(P1, 2, Vector3(-10, 0, 8), Vector3.ZERO)
	_world.use_level(COURSE)
	assert_array(_world.bodies.peers()).is_equal([P1])
	_world.use_level(FixtureModes.LOBBY)
	assert_array(_world.bodies.peers()).is_empty()


## A round of the fixture raise mode on the course alone, P1 and P2 in it, the knife's launch set
## per case. The lobby is the course's world under the lobby's path.
func _start() -> void:
	_turned = false
	_highest_top = -INF
	_frames = 0
	var mode := FixtureCombatModes.raising()
	mode.maps = PackedStringArray([COURSE])
	mode.player_rules.motion_maps = PackedStringArray([COURSE])
	mode.player_rules.longest_motion_s = LONGEST_S
	_strike = mode.find_item_kind(&"knife").actions[0].effects[0] as Strike
	var layouts := FixtureModes.layouts()
	layouts.erase(FixtureModes.MAP)
	layouts.erase(FixtureModes.MOTION_MAP)
	var course := LevelLayout.new(COURSE)
	for i in 4:
		course.add_marker(&"round_player", Vector3(-15 + i, 0, -28))
	for spot: Vector3 in FixtureModes.RESPAWNS:
		course.add_marker(FixtureModes.RESPAWN_TAG, spot)
	layouts[COURSE] = course
	_world = HostWorldQuery.new(RADIUS, CROUCH_HEIGHT)
	_level = LevelWorld.build(COURSE)
	assert_array(Array(_level.errors)).is_empty()
	_world.add_level(_level)
	var lobby := LevelWorld.build(COURSE)
	lobby.path = FixtureModes.LOBBY
	_world.add_level(lobby)
	_game = Match.new(mode, 7, _world, layouts)
	assert_array(Array(_game.refusals)).is_empty()
	_game.keep_history = true
	_game.start(0)
	for peer: int in [P1, P2]:
		FixtureModes.send(_game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in [P1, P2]:
		FixtureModes.send(_game, Intents.SET_READY, peer, {"ready": true})
	assert_str(_world.level_path()).is_equal(COURSE)
	_seen = _game.emitted().size()


## P1, armed 1 m behind `at` along `towards` (or at `attacker_at`), knocks P2 at `at` down with two
## blows of the knife launching `launch_mps` along `towards` and `launch_up_mps` up.
func _knock_down(
	at: Vector3,
	towards: Vector3,
	launch_mps: float,
	launch_up_mps: float,
	attacker_at := Vector3.INF
) -> void:
	_strike.launch_mps = launch_mps
	_strike.launch_up_mps = launch_up_mps
	var behind := at - towards * 1.0 if attacker_at == Vector3.INF else attacker_at
	FixtureCombatModes.arm(_game, P1, behind)
	FixtureItemModes.stand(_game, P2, at)
	var facing := (at - behind).normalized()
	FixtureCombatModes.use(_game, P1, facing)
	FixtureModes.run_ticks(_game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(_game, P1, facing)
	_carry_out()
	assert_int(_game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_object(_game.state.player(P2).motion).is_not_null()


## The host's loop until P2's motion ends: physics frames, and every FRAMES_PER_TICK of them a host
## tick headed by the bodies' reports.
func _until_rest() -> void:
	_frames = 0
	while _game.state.player(P2).motion != null and _frames < FRAME_LIMIT:
		await get_tree().physics_frame
		_frames += 1
		_watch(P2)
		if _frames % FRAMES_PER_TICK == 0:
			_host_tick()
	assert_object(_game.state.player(P2).motion).is_null()


## One host tick: the reports, stamped with it, then the tick, then the directives.
func _host_tick() -> void:
	var at_tick := _game.ticked_through() + 1
	for report: MatchCommand in _world.bodies.reports():
		report.tick = at_tick
		_game.apply(report)
	_carry_out()
	_game.tick(at_tick)
	_carry_out()


## LaunchBody and StopBody emitted since the last call, carried out as HostSession does.
func _carry_out() -> void:
	var emitted := _game.emitted()
	for i in range(_seen, emitted.size()):
		var event := emitted[i].event
		if event is LaunchBodyEvent:
			var launch := event as LaunchBodyEvent
			_world.bodies.launch(launch.peer, launch.epoch, launch.origin, launch.velocity)
		elif event is StopBodyEvent:
			_world.bodies.stop((event as StopBodyEvent).peer)
	_seen = emitted.size()


func _watch(peer: int) -> void:
	if not _world.bodies.peers().has(peer):
		return
	var placed := _world.bodies.transform_of(peer)
	if not placed.basis.is_equal_approx(Basis.IDENTITY):
		_turned = true
	_highest_top = maxf(_highest_top, placed.origin.y + CROUCH_HEIGHT / 2.0)


## Slow reports of P2's body at `at` (no physics) until it rests: KE15's rest in the host's world.
func _report_until_rest(at: Vector3) -> void:
	var downed := _game.state.player(P2)
	for i in 20:
		if downed.motion == null:
			break
		var args := {"epoch": downed.motion.epoch, "position": at, "velocity": Vector3.ZERO}
		var at_tick := _game.ticked_through() + 1
		_game.apply(MatchCommand.new(Intents.BODY_MOVED, P2, at_tick, args))
		_game.tick(at_tick)
		_carry_out()
	assert_object(downed.motion).is_null()
	assert_array(_world.bodies.peers()).is_empty()
	assert_array(Array(_game.diagnostics)).is_empty()


func _rest_point() -> Vector3:
	return _game.state.player(P2).position


## Where a body may rest: still, its host body freed, within the longest motion, upright all the
## way, inside the level, on the standing floor under its capsule, and with a crouching player's
## capsule there (lifted by Items.SURFACE_CLEARANCE_M and narrowed by it: touching a floor, a wall
## or an underside is not a hit) clear of the level.
func _assert_rests_well(at: Vector3) -> void:
	var downed := _game.state.player(P2)
	assert_object(downed.motion).is_null()
	assert_vector(downed.velocity).is_equal(Vector3.ZERO)
	assert_array(_world.bodies.peers()).is_empty()
	assert_int(_frames).is_less_equal(int(LONGEST_S * 20) * FRAMES_PER_TICK + FRAMES_PER_TICK)
	assert_bool(_turned).override_failure_message("the body turned").is_false()
	assert_bool(GROUND.has_point(at)).override_failure_message("outside: %s" % at).is_true()
	var floor_at := _world.stand_floor_below(Items.lifted(at + Vector3.UP * RADIUS))
	assert_vector(floor_at).is_equal_approx(at, Vector3.ONE * 0.01)
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS - Items.SURFACE_CLEARANCE_M
	capsule.height = CROUCH_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := at + Vector3.UP * (CROUCH_HEIGHT / 2.0 + Items.SURFACE_CLEARANCE_M)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	var hits := _level.space_state().intersect_shape(query, 1)
	(
		assert_array(hits)
		. override_failure_message("a crouching player does not fit at %s" % at)
		. is_empty()
	)
	assert_array(Array(_game.diagnostics)).is_empty()
