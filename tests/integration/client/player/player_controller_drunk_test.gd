extends GdUnitTestSuite
## The drunk controller (#1391; ARCHITECTURE §4.7.6 "Drunk"; DrunkFeel's own suite has the maths):
## sober nothing differs, no _process runs and the camera never turns on its head; drunk, the
## strength eases up to the value's, the camera sways within the tuning's caps while the look
## vector (the claim's facing) stays the head's, and the walk drifts off the keys' line, never
## faster than the walk; no keys, no drift; the value's decay eases it out and a knockdown or a
## placement ends it at once; the walk out of `movers` is the sober one. The rules are the fixture
## mode's with the base mode's bar (drunk 0..100, too much at 90).

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
## The highest drunk value below "too much".
const DRUNK := 89
const DT := 1.0 / 60.0

var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	_world.rules.drunk_max = 100
	_world.rules.drunk_too_much_at = 90
	_world.rules.drunk_point_s = 1.0
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_sober_nothing_sways_or_drifts_and_no_process_runs() -> void:
	var player := _world.add_player(Vector3.ZERO)
	await _world.frames(2)
	assert_bool(player.is_processing()).is_false()
	player.move_input = Vector2(0.0, 1.0)
	await _world.frames(120)
	await _process_frames()
	assert_bool(player.is_processing()).is_false()
	assert_float(player.drunk_strength()).is_equal(0.0)
	assert_vector(player.get_camera().rotation).is_equal(Vector3.ZERO)
	# Straight down the keys' line.
	assert_float(player.global_position.x).is_equal_approx(0.0, 0.0001)
	assert_float(player.global_position.z).is_less(-5.0)
	assert_vector(player.look_vector()).is_equal_approx(_camera_look(player), Vector3.ONE * 0.0001)


func test_drunk_the_camera_sways_within_its_caps_and_the_facing_does_not() -> void:
	var player := _world.add_player(Vector3.ZERO)
	player.drunk = DRUNK
	player.look(0.3, 0.2)
	var facing := player.look_vector()
	var roll_cap := deg_to_rad(player.tuning.sway_roll_max_deg)
	var pitch_cap := deg_to_rad(player.tuning.sway_pitch_max_deg)
	var top_roll := 0.0
	for i: int in 300:
		await _world.frames(1)
		await get_tree().process_frame
		var sway := player.get_camera().rotation
		assert_float(absf(sway.y)).is_equal(0.0)
		assert_float(absf(sway.z)).is_less_equal(roll_cap + 0.000001)
		assert_float(absf(sway.x)).is_less_equal(pitch_cap + 0.000001)
		top_roll = maxf(top_roll, absf(sway.z))
		assert_vector(player.look_vector()).is_equal_approx(facing, Vector3.ONE * 0.0001)
	assert_bool(player.is_processing()).is_true()
	assert_float(player.drunk_strength()).is_equal_approx(DRUNK / 90.0, 0.001)
	assert_float(top_roll).is_greater(roll_cap * 0.3)


func test_drunk_the_walk_drifts_off_the_keys_line_never_faster_than_the_walk() -> void:
	var player := _world.add_player(Vector3.ZERO)
	player.drunk = DRUNK
	player.move_input = Vector2(0.0, 1.0)
	var widest := 0.0
	var last := player.global_position
	# Steps after the first: at walk speed, at most one step's travel each.
	var most := _world.rules.walk_speed_mps * DT + 0.0001
	for i: int in 300:
		await _world.frames(1)
		var now := player.global_position
		if i > 0:
			assert_float(Vector2(now.x - last.x, now.z - last.z).length()).is_less_equal(most)
		widest = maxf(widest, absf(now.x))
		last = now
	assert_float(widest).is_greater(0.3)
	# No keys, no drift: it comes to rest and stays there.
	player.move_input = Vector2.ZERO
	await _world.frames(30)
	var rest := player.global_position
	await _world.frames(60)
	assert_vector(player.global_position).is_equal_approx(rest, Vector3.ONE * 0.0001)


func test_the_decay_eases_it_out_and_a_knockdown_or_a_placement_ends_it_at_once() -> void:
	var player := _world.add_player(Vector3.ZERO)
	player.drunk = DRUNK
	await _world.frames(90)
	assert_float(player.drunk_strength()).is_greater(0.9)
	# Sobered: the strength falls over drunk_ease_seconds, not at once.
	player.drunk = 0
	await _world.frames(10)
	assert_float(player.drunk_strength()).is_between(0.5, 0.9)
	var ease_frames := ceili(player.tuning.drunk_ease_seconds / DT)
	await _world.frames(ease_frames)
	await _process_frames()
	assert_float(player.drunk_strength()).is_equal(0.0)
	assert_bool(player.is_processing()).is_false()
	assert_vector(player.get_camera().rotation).is_equal(Vector3.ZERO)
	# A knockdown: at once, and none while downed even if the value were still up.
	player.drunk = DRUNK
	await _world.frames(60)
	await _process_frames()
	assert_bool(player.get_camera().rotation.is_zero_approx()).is_false()
	player.life = ClientModel.Life.DOWNED
	assert_float(player.drunk_strength()).is_equal(0.0)
	assert_vector(player.get_camera().rotation).is_equal(Vector3.ZERO)
	await _world.frames(30)
	await _process_frames()
	assert_float(player.drunk_strength()).is_equal(0.0)
	assert_bool(player.is_processing()).is_false()
	# A respawn's or a placement's level look: at once too.
	player.life = ClientModel.Life.ALIVE
	await _world.frames(60)
	assert_float(player.drunk_strength()).is_greater(0.5)
	player.look_level()
	assert_float(player.drunk_strength()).is_equal(0.0)
	assert_vector(player.get_camera().rotation).is_equal(Vector3.ZERO)
	assert_bool(player.is_processing()).is_false()


func test_the_walk_out_of_movers_is_the_sober_one() -> void:
	var sober := _world.add_player(Vector3(-10.0, 0.0, 0.0))
	var drunk := _world.add_player(Vector3(10.0, 0.0, 0.0))
	drunk.drunk = DRUNK
	drunk.tuning.drunk_ease_seconds = 0.0
	# A wide lean, so a drift during the walk-out would show at once.
	drunk.tuning.drift_lean_deg = 30.0
	await _world.frames(2)
	for player: PlayerController in [sober, drunk]:
		_add_mover(player.global_position)
		player.teleport(player.global_transform)
		player.drunk = DRUNK if player == drunk else 0
		player.move_input = Vector2(0.0, 1.0)
	await _world.frames(1)
	assert_float(drunk.drunk_strength()).is_greater(0.9)
	for i: int in 6:
		await _world.frames(1)
		var offset := drunk.global_position - Vector3(20.0, 0.0, 0.0)
		assert_vector(offset).is_equal_approx(sober.global_position, Vector3.ONE * 0.0001)
	# It did walk out, at the walk's speed toward the clear floor.
	assert_float(sober.global_position.distance_to(Vector3(-10.0, 0.0, 0.0))).is_greater(0.2)


## A box on the `movers` layer around `feet`, as the car repair's raised car is (KD15 (b2)).
func _add_mover(feet: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.MOVERS
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.position = feet + Vector3(0.0, 0.5, 0.0)
	_world.add_child(body)
	body.force_update_transform()


func _camera_look(player: PlayerController) -> Vector3:
	return -player.get_camera().global_basis.z.normalized()


## Two process frames: the sway is set in _process, after the physics steps (tests.md, #222).
func _process_frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
