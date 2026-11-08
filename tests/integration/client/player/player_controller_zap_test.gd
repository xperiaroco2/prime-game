extends GdUnitTestSuite
## The ship zap's shake on the own controller (#1585; ZapShake's suite has the maths): the camera
## turns under the head, no yaw, the look vector (the claim's facing) stays the head's, the shake
## ends level with no _process running on; a downed player's does not start; ShipZapScreen starts
## it.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
const SECONDS := 0.4

var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_the_camera_shakes_under_the_head_and_ends_level() -> void:
	var player := _world.add_player(Vector3.ZERO)
	await _world.frames(2)
	var look := player.look_vector()
	player.shake(SECONDS)
	assert_bool(player.is_processing()).is_true()
	assert_float(player.shake_left()).is_equal(SECONDS)
	var moved := false
	for _i in 8:
		await get_tree().process_frame
		moved = moved or not player.get_camera().rotation.is_zero_approx()
		assert_float(player.get_camera().rotation.y).is_equal(0.0)
		assert_vector(player.look_vector()).is_equal_approx(look, Vector3.ONE * 0.0001)
	assert_bool(moved).is_true()
	player.shake(0.001)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(player.shake_left()).is_equal(0.0)
	assert_vector(player.get_camera().rotation).is_equal(Vector3.ZERO)
	assert_bool(player.is_processing()).is_false()


func test_the_downed_do_not_shake() -> void:
	var player := _world.add_downed(Vector3.ZERO)
	await _world.frames(2)
	player.shake(SECONDS)
	assert_float(player.shake_left()).is_equal(0.0)
	assert_bool(player.is_processing()).is_false()


func test_the_zap_screen_shakes_the_own_camera_for_the_modes_seconds() -> void:
	var player := _world.add_player(Vector3.ZERO)
	await _world.frames(2)
	var screen: ShipZapScreen = auto_free(ShipZapScreen.new())
	add_child(screen)
	screen.player = player
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.crystal()]
	screen.set_mode(FixtureEngineKindModes.of(kinds))
	screen.on_event(&"ShipZapped", {})
	assert_float(player.shake_left()).is_equal(FixtureEngineKindModes.ZAP_FLASH_SECONDS)
