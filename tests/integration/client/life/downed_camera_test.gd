extends GdUnitTestSuite
## The downed camera against a fixture wall over real physics steps (Jolt, headless; ARCHITECTURE
## §4.7, the engineer's answer 9 (a), the M4 ADR's §3 item 3): for every look, never above the
## body's standing eye height and never through the wall; and while it is in use, a view the arm's
## end could see past the end of a short wall but the body's eye could not is hidden (SightHider),
## while one in the open stays drawn. Forward is -Z.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
## The fixture wall behind the body: its near face, in metres from the body along +Z.
const WALL_NEAR_Z := 1.0
const WALL_THICK := 0.2

var _rules := FixtureModes.player_rules()
var _world: PlayerTestWorld
var _rig: DownedCamera


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)
	_rig = DownedCamera.new()
	_world.add_child(_rig)


func after_test() -> void:
	_world.free()


func test_never_above_eye_height_and_never_through_the_wall_behind() -> void:
	# A tall wall 1 m behind the body: the arm, 2 m long, would end inside or past it.
	_world.add_box(Vector3(0.0, 1.5, WALL_NEAR_Z + WALL_THICK * 0.5), Vector3(6.0, 3.0, WALL_THICK))
	var eye := Vector3(0.0, _rules.eye_height_m, 0.0)
	var pitches: Array[float] = [-1.5, -0.8, -0.3, 0.0, 0.3, 0.8, 1.2, 1.5]
	for yaw: float in [0.0, 0.3, -0.3]:
		for pitch: float in pitches:
			_rig.place(eye, yaw, pitch)
			await _world.frames(2)
			var at := _rig.camera().global_position
			var label := "yaw %s pitch %s at %s" % [yaw, pitch, at]
			assert_float(at.y).override_failure_message(label).is_less_equal(eye.y + 0.001)
			assert_float(at.y).override_failure_message(label).is_greater(0.0)
			assert_float(at.z).override_failure_message(label).is_less(WALL_NEAR_Z)
			# Nothing of the level between the eye and the camera.
			var space := _rig.get_world_3d().direct_space_state
			assert_bool(SightHider.sees(space, eye, at)).override_failure_message(label).is_true()


func test_in_the_open_the_arm_reaches_its_length_behind_the_look() -> void:
	var eye := Vector3(0.0, _rules.eye_height_m, 0.0)
	_rig.place(eye, 0.0, -0.5)
	await _world.frames(2)
	var at := _rig.camera().global_position
	assert_float(_rig.arm_length()).is_equal_approx(DownedCamera.ARM_LENGTH_M, 0.01)
	assert_vector(at).is_equal_approx(eye + Vector3(0.0, 0.0, 2.0), Vector3.ONE * 0.02)
	# Looking down tilts the camera only: it looks down from level.
	var look := -_rig.camera().global_basis.z
	assert_float(look.y).is_less(-0.4)


func test_a_view_seen_past_a_short_wall_from_the_arm_but_not_the_eye_is_hidden() -> void:
	# The body lies against the end of a short wall on its right (x 0.3 to 0.5, ending at z 0.2).
	_world.add_box(Vector3(0.4, 1.5, -1.4), Vector3(0.2, 3.0, 3.2))
	var eye := Vector3(0.0, _rules.eye_height_m, 0.0)
	var hidden := _view(Vector3(2.0, 0.2, -2.0))
	var open := _view(Vector3(-2.0, 0.2, -2.0))
	var hider := SightHider.new()
	_world.add_child(hider)
	_rig.place(eye, 0.0, 0.0)
	await _world.frames(2)
	var space := _rig.get_world_3d().direct_space_state
	var arm_end := _rig.camera().global_position
	assert_float(arm_end.z).is_greater(1.9)
	# The precondition: from the arm's end the item is in sight past the wall's end; from the eye
	# it is behind the wall.
	assert_bool(SightHider.sees(space, arm_end, hidden.global_position)).is_true()
	assert_bool(SightHider.sees(space, eye, hidden.global_position)).is_false()
	hider.watch_from(_rig.pivot())
	await _world.frames(1)
	assert_bool(hidden.visible).is_false()
	assert_bool(open.visible).is_true()
	# Standing up (the camera out of use): everything shows again.
	hider.stop()
	assert_bool(hidden.visible).is_true()


func test_a_turn_toward_the_wall_is_cast_in_the_same_physics_step() -> void:
	# The arm at its full length in the open (looking toward the wall puts the arm in the open),
	# then a turn the other way placed from LifeView's priority: the camera is in front of the wall
	# when the step ends, not one step later (the reviews of M4-9).
	_world.add_box(Vector3(0.0, 1.5, WALL_NEAR_Z + WALL_THICK * 0.5), Vector3(6.0, 3.0, WALL_THICK))
	var eye := Vector3(0.0, _rules.eye_height_m, 0.0)
	_rig.place(eye, PI, 0.0)
	await _world.frames(2)
	assert_float(_rig.arm_length()).is_equal_approx(DownedCamera.ARM_LENGTH_M, 0.01)
	var turner := Turner.new(_rig, eye)
	var probe := Probe.new(_rig)
	_world.add_child(turner)
	_world.add_child(probe)
	await _world.frames(2)
	assert_bool(probe.seen_after_turn).is_true()
	var label := "camera at %s right after the turn" % probe.at
	assert_float(probe.at.z).override_failure_message(label).is_less(WALL_NEAR_Z)


## An item-like view in SightHider's group at `at`: a small box mesh, no collision.
func _view(at: Vector3) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	view.mesh = box
	view.position = at
	view.add_to_group(SightHider.GROUP)
	_world.add_child(view)
	return view


## Turns the rig toward the wall once, from LifeView's physics priority, as LifeView places it.
class Turner:
	extends Node

	var _rig: DownedCamera
	var _eye: Vector3

	func _init(rig: DownedCamera, eye: Vector3) -> void:
		_rig = rig
		_eye = eye
		process_physics_priority = LifeView.PHYSICS_PRIORITY

	func _physics_process(_delta: float) -> void:
		_rig.place(_eye, 0.0, 0.0)
		set_physics_process(false)


## Reads the camera after the turn in the same physics step, before SightHider would cast.
class Probe:
	extends Node

	var seen_after_turn := false
	var at := Vector3.ZERO
	var _rig: DownedCamera

	func _init(rig: DownedCamera) -> void:
		_rig = rig
		process_physics_priority = SightHider.PHYSICS_PRIORITY - 1

	func _physics_process(_delta: float) -> void:
		at = _rig.camera().global_position
		seen_after_turn = true
		set_physics_process(false)
