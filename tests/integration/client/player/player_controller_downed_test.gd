extends GdUnitTestSuite
## The downed player in the first-person controller over real physics steps (Jolt, headless).
## It crawls as the host's crawl check allows (§7.1 The crawl, M4-2): the living's
## gravity, floor, steps, slopes and walls at `crawl_speed_mps`, with no sprint and no jump, and its
## stamina regenerates as usual. It passes through players (the engineer's correction of
## 2026-09-30, #46: the downed do not fly). It lies down (its mesh; the capsule stays standing),
## and a raise holds it still (M4-9). A dead player has no body and does not look around, and
## look_level() levels a respawned head (#191), and the own placement's (#240). Forward is -Z. Each
## test builds its own small world.

const SPEED_TOLERANCE := 0.05
const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")

var _rules := FixtureModes.player_rules()
var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_downed_is_on_the_downed_layer_and_collides_with_the_level_only() -> void:
	# The living collide with the level only too: they push each other instead (the push suite).
	var player := _world.add_player(Vector3.ZERO)
	assert_int(player.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD)
	player.life = ClientModel.Life.DOWNED
	assert_int(player.collision_layer).is_equal(PhysicsLayers.DOWNED)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD)
	player.life = ClientModel.Life.ALIVE
	assert_int(player.collision_layer).is_equal(PhysicsLayers.LIVING)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.WORLD)


func test_the_crawl_speed_is_the_modes_1_mps_below_the_walk() -> void:
	# The vision revision's crawl (M4-2); the base speeds stay placeholders.
	assert_float(_rules.crawl_speed_mps).is_equal_approx(1.0, 0.0001)
	assert_float(_rules.crawl_speed_mps).is_less(_rules.walk_speed_mps)


func test_downed_crawls_on_the_floor_at_the_crawl_speed() -> void:
	var player := _world.add_downed(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	var speed: float = await _world.measure_speed(player)
	assert_float(speed).is_equal_approx(_rules.crawl_speed_mps, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.01)
	assert_bool(player.is_on_floor()).is_true()


func test_downed_falls_like_the_living() -> void:
	var living := _world.add_player(Vector3(-3.0, 2.0, 0.0))
	var downed := _world.add_downed(Vector3(3.0, 2.0, 0.0))
	for i: int in 45:
		await _world.frames(1)
		assert_float(downed.global_position.y).is_equal_approx(living.global_position.y, 0.0001)
	assert_float(downed.global_position.y).is_equal_approx(0.0, 0.01)
	assert_bool(downed.is_on_floor()).is_true()


func test_downed_looking_up_crawls_on_the_floor() -> void:
	var player := _world.add_downed(Vector3.ZERO)
	player.look(0.0, deg_to_rad(60.0))
	player.move_input = Vector2(0.0, 1.0)
	var highest := 0.0
	for i: int in 90:
		await _world.frames(1)
		highest = maxf(highest, player.global_position.y)
	assert_float(highest).is_less(0.01)
	assert_float(player.global_position.z).is_less(-1.0)


func test_downed_never_jumps_however_often_it_asks() -> void:
	# The host corrects any new jump of the downed (MovementRule).
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(10)
	var peak := 0.0
	for i: int in 90:
		player.jump_requested = true
		await _world.frames(1)
		peak = maxf(peak, player.global_position.y)
	assert_float(peak).is_less(0.01)
	assert_bool(player.is_on_floor()).is_true()


func test_downed_holding_sprint_crawls_with_full_or_no_stamina() -> void:
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(10)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var full: float = await _world.measure_speed(player)
	assert_float(full).is_equal_approx(_rules.crawl_speed_mps, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()
	_world.stand_in(player).set_status(Ticks.thousandths(0.0))
	var empty: float = await _world.measure_speed(player)
	assert_float(empty).is_equal_approx(_rules.crawl_speed_mps, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()


func test_downed_stamina_spends_nothing_and_regenerates() -> void:
	# The downed are never in the sprint state and spend none: their stamina regenerates as
	# usual (StaminaLedger), with sprint held and jumps asked for.
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(10)
	_world.stand_in(player).set_status(Ticks.thousandths(50.0))
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	for i: int in 60:
		player.jump_requested = true
		await _world.frames(1)
	var one_second := 50.0 + _rules.stamina_regen_per_s
	var regenerated := minf(float(_rules.stamina), one_second)
	# A second of 60 Hz steps settles 19 or 20 whole ticks, by where the carry stood.
	var one_tick := _rules.stamina_regen_per_s / float(Ticks.RATE)
	assert_float(player.stamina.get_stamina()).is_between(regenerated - one_tick, regenerated)
	assert_float(player.stamina.get_stamina()).is_greater(50.0)


func test_downed_crawls_up_stairs_like_the_living() -> void:
	var steps := 5
	_world.add_stairs(steps)
	var player := _world.add_downed(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	var lowest_eye := _rules.eye_height_m
	# Three seconds of the crawl end on the last, long tread, not past it.
	for i: int in 180:
		await _world.frames(1)
		var eye := player.get_camera().global_position.y - player.global_position.y
		lowest_eye = minf(lowest_eye, eye)
	assert_float(player.global_position.y).is_equal_approx(_rules.step_height_m * steps, 0.01)
	assert_bool(player.is_on_floor()).is_true()
	assert_float(lowest_eye).is_greater_equal(_rules.eye_height_m - _rules.step_height_m - 0.001)


func test_downed_stops_at_a_ledge_above_step_height() -> void:
	var height := _rules.step_height_m + 0.2
	_world.add_box(Vector3(0.0, height * 0.5, -3.0), Vector3(4.0, height, 2.0))
	var player := _world.add_downed(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(180)
	assert_float(player.global_position.y).is_less(0.01)
	assert_float(player.global_position.z).is_greater(-2.0 + _rules.capsule_radius_m - 0.02)
	# It reached the ledge: the crawl did not just fall short of it.
	assert_float(player.global_position.z).is_less(-2.0 + _rules.capsule_radius_m + 0.05)


func test_downed_cannot_get_onto_a_ledge_at_jump_height() -> void:
	# A ledge the living reach with a jump stops the downed, which never jump.
	var height := _rules.jump_height_m
	_world.add_box(Vector3(0.0, height * 0.5, -3.0), Vector3(4.0, height, 2.0))
	var player := _world.add_downed(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var highest := 0.0
	for i: int in 180:
		player.jump_requested = true
		await _world.frames(1)
		highest = maxf(highest, player.global_position.y)
	assert_float(highest).is_less(0.01)
	assert_float(player.global_position.z).is_greater(-2.0 + _rules.capsule_radius_m - 0.02)


func test_downed_crawls_up_a_ramp_at_the_steepest_walkable_angle_smoothly() -> void:
	# The slope, not a ledge's lift, carries the body: on the floor every step, no rise beyond the
	# slope's, and the view at eye height.
	var angle := deg_to_rad(44.0)
	_world.add_ramp(angle, -1.0)
	var player := _world.add_downed(Vector3.ZERO)
	assert_float(angle).is_less(player.floor_max_angle)
	player.move_input = Vector2(0.0, 1.0)
	# 1.25 s of the crawl puts it a quarter of a metre up the ramp.
	await _world.frames(75)
	var off_floor := 0
	var largest_rise := 0.0
	var eye_off := 0.0
	var last_y := player.global_position.y
	for i: int in 60:
		await _world.frames(1)
		if not player.is_on_floor():
			off_floor += 1
		largest_rise = maxf(largest_rise, player.global_position.y - last_y)
		last_y = player.global_position.y
		# A false step-up lowers the view; the slope never does.
		var eye := player.get_camera().global_position.y - last_y
		eye_off = maxf(eye_off, absf(eye - _rules.eye_height_m))
	assert_int(off_floor).is_equal(0)
	assert_float(eye_off).is_less(0.001)
	var slope_rise := _rules.crawl_speed_mps * tan(angle) / Engine.physics_ticks_per_second
	assert_float(largest_rise).is_less(slope_rise * 1.05)
	assert_float(last_y).is_greater(0.5)


func test_downed_crawls_over_a_low_round_pipe() -> void:
	_world.add_pipe(0.1, -2.0)
	var player := _world.add_downed(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(210)
	assert_float(player.global_position.z).is_less(-3.0)
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.01)


func test_downed_climbs_only_the_slopes_the_living_climb() -> void:
	# No steeper limit for the downed (the engineer, 2026-09-30, #46): the same floor angle, and it
	# does not get up a slope too steep to walk.
	var living := _world.add_player(Vector3(20.0, 0.0, 0.0))
	_world.add_ramp(deg_to_rad(50.0), -1.0)
	var player := _world.add_downed(Vector3.ZERO)
	assert_float(player.floor_max_angle).is_equal(living.floor_max_angle)
	player.move_input = Vector2(0.0, 1.0)
	var highest := 0.0
	for i: int in 180:
		await _world.frames(1)
		highest = maxf(highest, player.global_position.y)
	assert_float(highest).is_less(0.05)


func test_downed_passes_through_players() -> void:
	var other := _world.add_remote(Vector3(0.0, 0.0, -1.0))
	var player := _world.add_downed(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(150)
	assert_float(player.global_position.z).is_less(-2.0)
	assert_float(player.global_position.y).is_less(0.01)
	assert_vector(other.global_position).is_equal(Vector3(0.0, 0.0, -1.0))


func test_downed_is_stopped_by_walls() -> void:
	_world.add_box(Vector3(0.0, 1.5, -3.0), Vector3(6.0, 3.0, 0.2))
	var player := _world.add_downed(Vector3.ZERO)
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(240)
	assert_float(player.global_position.z).is_greater(-3.0 + 0.1 + _rules.capsule_radius_m - 0.02)
	assert_float(player.global_position.z).is_less(-3.0 + 0.1 + _rules.capsule_radius_m + 0.05)


func test_turning_back_into_the_living_limits_it_by_stamina_again() -> void:
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(10)
	_world.stand_in(player).set_status(Ticks.thousandths(0.0))
	player.life = ClientModel.Life.ALIVE
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var speed: float = await _world.measure_speed(player, 5, 10)
	assert_float(speed).is_equal_approx(_rules.walk_speed_mps, SPEED_TOLERANCE)
	assert_bool(player.is_sprinting()).is_false()


func test_only_the_downed_show_the_lying_mesh_and_the_dead_have_no_body() -> void:
	var player := _world.add_player(Vector3.ZERO)
	var lying := player.get_node("Lying") as MeshInstance3D
	assert_bool(lying.visible).is_false()
	player.life = ClientModel.Life.DOWNED
	assert_bool(lying.visible).is_true()
	# On its side along the body: as long as the capsule, no higher than its width.
	var box := lying.global_transform * lying.get_aabb()
	assert_float(box.size.z).is_equal_approx(_rules.capsule_height_m, 0.01)
	assert_float(box.end.y).is_equal_approx(_rules.capsule_radius_m * 2.0, 0.01)
	player.life = ClientModel.Life.DEAD
	assert_bool(lying.visible).is_false()
	assert_int(player.collision_layer).is_equal(0)
	assert_bool(player.is_living() or player.is_downed()).is_false()


func test_the_own_lying_mesh_wears_the_own_body_colour() -> void:
	# #551: offline the greybox colour; on a session the own colour from the roster, as the others
	# see the lying body.
	var player := _world.add_player(Vector3.ZERO)
	var lying := player.get_node("Lying") as MeshInstance3D
	var material := (lying.mesh as CapsuleMesh).material as StandardMaterial3D
	player.life = ClientModel.Life.DOWNED
	assert_object(material.albedo_color).is_equal(LifeLooks.PLAYER_COLOUR)
	player.life = ClientModel.Life.ALIVE
	var schema := WireSchema.game(OS.is_debug_build())
	var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
	var session := ClientSession.new(transport, FixtureBaseMode.mode(), schema)
	session.model.own_peer = 2
	session.model.fold(
		&"PlayerJoined", {"peer": 2, "name": "Me", "spot": Vector3.ZERO, "colour": 6}
	)
	player.attach(session)
	player.life = ClientModel.Life.DOWNED
	assert_object(material.albedo_color).is_equal(BodyColours.of(6))


func test_the_dead_never_move_however_they_are_driven() -> void:
	var player := _world.add_player(Vector3(0.0, 1.0, 0.0))
	player.life = ClientModel.Life.DEAD
	player.move_input = Vector2(0.0, 1.0)
	player.jump_requested = true
	await _world.frames(30)
	assert_vector(player.global_position).is_equal(Vector3(0.0, 1.0, 0.0))


func test_the_downed_look_around_and_the_dead_neither_turn_nor_tilt_the_head() -> void:
	# #191: the dead have no avatar; mouse motion while spectating tilted the hidden head.
	var player := _world.add_downed(Vector3.ZERO)
	player.look(0.5, 0.3)
	assert_float(player.rotation.y).is_equal_approx(0.5, 0.0001)
	assert_float(_pitch(player)).is_equal_approx(0.3, 0.0001)
	for life: ClientModel.Life in [ClientModel.Life.DEAD, ClientModel.Life.LEFT]:
		player.life = life
		player.look(0.9, 0.8)
		assert_float(player.rotation.y).is_equal_approx(0.5, 0.0001)
		assert_float(_pitch(player)).is_equal_approx(0.3, 0.0001)


func test_look_level_levels_the_head_and_keeps_the_yaw() -> void:
	# A respawn's look (the engineer's answer on #191): level, the yaw kept.
	var player := _world.add_player(Vector3.ZERO)
	player.look(-1.2, -0.7)
	player.look_level()
	assert_float(_pitch(player)).is_equal_approx(0.0, 0.0001)
	assert_float(player.rotation.y).is_equal_approx(-1.2, 0.0001)
	var ahead := Vector3(sin(1.2), 0.0, -cos(1.2))
	assert_vector(player.look_vector()).is_equal_approx(ahead, Vector3.ONE * 0.0001)


func test_only_the_own_respawn_and_placement_level_the_look() -> void:
	# #240 (the engineer's answer, option b): a PlayersPlaced naming the own player levels its look
	# as the own Respawned does (#191); another player's respawn or placement keeps it.
	var player := _world.add_player(Vector3.ZERO)
	var schema := WireSchema.game(OS.is_debug_build())
	var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
	var session := ClientSession.new(transport, FixtureBaseMode.mode(), schema)
	session.model.own_peer = 2
	player.attach(session)
	player.look(0.5, 0.4)
	var others: Dictionary[int, Vector3] = {3: Vector3.ONE}
	session.event_received.emit(&"PlayersPlaced", {"spots": others})
	session.event_received.emit(&"Respawned", {"peer": 3})
	assert_float(_pitch(player)).is_equal_approx(0.4, 0.0001)
	var everyone: Dictionary[int, Vector3] = {2: Vector3.ZERO, 3: Vector3.ONE}
	session.event_received.emit(&"PlayersPlaced", {"spots": everyone})
	assert_float(_pitch(player)).is_equal_approx(0.0, 0.0001)
	assert_float(player.rotation.y).is_equal_approx(0.5, 0.0001)


func test_a_held_downed_player_stands_still_while_asked_to_crawl() -> void:
	# A raise holds the downed in place (M4-4): every claim is where it lay.
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(10)
	var lay := player.global_position
	player.held = true
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	for i: int in 60:
		player.jump_requested = true
		await _world.frames(1)
		assert_vector(player.global_position).is_equal(lay)
	# Let go (RaiseStopped), it crawls on.
	player.held = false
	await _world.frames(30)
	assert_float(player.global_position.z).is_less(lay.z - 0.3)


## The head's pitch of `player`'s first-person view, in radians (up is positive).
func _pitch(player: PlayerController) -> float:
	return player.get_camera().get_parent_node_3d().rotation.x
