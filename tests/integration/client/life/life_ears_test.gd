extends GdUnitTestSuite
## LifeView's ears (E40, the M5 ADR §3 item 4 and §5's M5-5 row), without the network: a LifeView
## over AvatarViews of a hand-folded ClientModel places the current AudioListener3D at the own eye
## while living, at the own body's head where it lies while downed (not at the downed camera up to
## 2 m behind and 1.6 m above it), at a spectated living target's eye and at a downed target's
## head; and it lets go of the ears when the session ends. World sounds measure from there.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const MODE := "res://content/modes/base_mode.tres"
const OWN := 1
const TARGET := 2
const TICK_USEC := 50000

var _mode: GameMode
var _model: ClientModel
var _world: Node3D
var _player: PlayerController
var _avatars: AvatarViews
var _life: LifeView
var _now := 1000000


func before_test() -> void:
	_mode = load(MODE) as GameMode
	_model = ClientModel.new(_mode)
	_model.own_peer = OWN
	for peer: int in [OWN, TARGET]:
		var member := ClientModel.Member.new()
		member.name = "Player%d" % peer
		_model.roster[peer] = member
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3(0, 0, 5)) as PlayerController
	_player.rules = _mode.player_rules
	_avatars = AvatarViews.new()
	_avatars.model = _model
	_avatars.buffer = SnapshotBuffer.new()
	_avatars.rules = _mode.player_rules
	_avatars.clock = func() -> int: return _now
	_world.add_child(_avatars)
	_life = LifeView.new()
	_life.model = _model
	_life.mode = _mode
	_life.avatars = _avatars
	_life.player = _player
	_life.reads_device_input = false
	_world.add_child(_life)


func after_test() -> void:
	_world.free()


func test_the_living_hear_from_their_eye() -> void:
	await _drawn()
	var ears := _life.ears()
	assert_bool(ears.is_current()).is_true()
	assert_object(get_viewport().get_audio_listener_3d()).is_same(ears)
	var eye := _player.get_camera().global_position
	assert_vector(ears.global_position).is_equal_approx(eye, Vector3.ONE * 1e-3)


func test_the_downed_hear_from_their_body_not_from_the_downed_camera() -> void:
	_model.lives[OWN] = ClientModel.Life.DOWNED
	_player.life = ClientModel.Life.DOWNED
	await _drawn()
	assert_int(_life.view()).is_equal(LifeView.View.DOWNED)
	var ears := _life.ears().global_position
	var head := Ears.lying_head(_player.global_transform, _mode.player_rules)
	assert_vector(ears).is_equal_approx(head, Vector3.ONE * 1e-3)
	assert_float(ears.y).is_less(_mode.player_rules.eye_height_m * 0.5)
	# The plant this guards against: the ears left at the camera of the downed.
	var camera := _life.downed_camera().camera().global_position
	assert_float(ears.distance_to(camera)).is_greater(0.5)


func test_the_dead_hear_from_a_living_targets_eye_then_from_its_body_when_it_goes_down() -> void:
	_others_at(Vector3(4, 0, 0))
	_model.lives[OWN] = ClientModel.Life.DEAD
	_model.bodies[OWN] = Vector3(0, 0, 5)
	_player.life = ClientModel.Life.DEAD
	await _drawn()
	assert_int(_life.target()).is_equal(TARGET)
	var eye := Vector3(4, _mode.player_rules.eye_height_m, 0)
	assert_vector(_life.ears().global_position).is_equal_approx(eye, Vector3.ONE * 1e-3)
	_model.lives[TARGET] = ClientModel.Life.DOWNED
	await _drawn()
	# The only other player, so it stays the target from the downed pool: its body's head.
	assert_int(_life.target()).is_equal(TARGET)
	var body := _avatars.body_of(TARGET)
	var head := Ears.lying_head(body.global_transform, _mode.player_rules)
	assert_vector(_life.ears().global_position).is_equal_approx(head, Vector3.ONE * 1e-3)


func test_the_dead_with_no_target_hear_from_their_own_body_not_the_controller() -> void:
	# Nobody else: no target. The body lies where it died, away from the controller, which is turned.
	_model.roster.erase(TARGET)
	_player.look(1.2, 0.0)
	_model.lives[OWN] = ClientModel.Life.DEAD
	_model.bodies[OWN] = Vector3(3, 0, -2)
	_player.life = ClientModel.Life.DEAD
	await _drawn()
	assert_int(_life.target()).is_equal(0)
	var own := Ears.lying_head(Transform3D(Basis.IDENTITY, Vector3(3, 0, -2)), _mode.player_rules)
	assert_vector(_life.ears().global_position).is_equal_approx(own, Vector3.ONE * 1e-3)


func test_the_ears_turn_with_the_current_camera_living_and_downed() -> void:
	# Left and right match the screen: a sound on the screen's left is heard on the left.
	_player.look(PI / 2.0, 0.3)
	await _drawn()
	_assert_ears_turned_with_the_camera()
	_model.lives[OWN] = ClientModel.Life.DOWNED
	_player.life = ClientModel.Life.DOWNED
	_player.look(-0.7, 0.0)
	await _drawn()
	assert_object(get_viewport().get_camera_3d()).is_same(_life.downed_camera().camera())
	_assert_ears_turned_with_the_camera()


func test_the_ears_are_let_go_when_the_session_ends() -> void:
	await _drawn()
	assert_bool(_life.ears().is_current()).is_true()
	_life.reset()
	assert_bool(_life.ears().is_current()).is_false()


func test_world_sounds_measure_from_the_ears() -> void:
	_model.lives[OWN] = ClientModel.Life.DOWNED
	_player.life = ClientModel.Life.DOWNED
	await _drawn()
	var sounds: WorldSounds = auto_free(WorldSounds.new())
	_world.add_child(sounds)
	sounds.model = _model
	var ears := _life.ears().global_position
	var camera := _life.downed_camera().camera().global_position
	# A put-down just inside the range from the ears and beyond it from the camera, on the far
	# side of the body from the camera: heard, since the ears decide (E40's amendment of E33).
	var away := (ears - camera) * Vector3(1, 0, 1)
	var direction := away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var at := ears + direction * (SoundChooser.HEARING_RANGE_M - 0.05)
	assert_float(at.distance_to(camera)).is_greater(SoundChooser.HEARING_RANGE_M)
	sounds.on_event(&"ItemPlaced", {"item": 5, "position": at, "cause": &"put_down"})
	assert_int(sounds.played()).is_equal(1)


func _assert_ears_turned_with_the_camera() -> void:
	var camera := get_viewport().get_camera_3d().global_basis
	var ears := _life.ears().global_basis
	assert_float(camera.x.dot(Vector3.RIGHT)).is_less(0.9)
	for axis: int in 3:
		assert_vector(ears[axis]).is_equal_approx(camera[axis], Vector3.ONE * 1e-3)


func _others_at(at: Vector3) -> void:
	for tick: int in range(1, 4):
		_now += TICK_USEC
		var avatars := {
			TARGET:
			{
				"position": at,
				"velocity": Vector3.ZERO,
				"facing": Vector3.FORWARD,
				"downed": false,
				"held_item": -1,
			}
		}
		_model.fold_snapshot({"tick": tick, "avatars": avatars})
		_avatars.buffer.add(tick, avatars, _now)
	_now += TICK_USEC * 10


func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
