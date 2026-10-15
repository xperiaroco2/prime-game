extends GdUnitTestSuite
## LifeView's `view_camera` (#786, the photo camera's viewfinder; ARCHITECTURE §4.7.56): while the
## own life is living and the Callable gives a camera in the tree (PhotoViewfinder.live_camera, the
## lens while the view is up), that camera stays current instead of the own eye; null gives the eye
## back. The downed camera still wins over it.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const MODE := "res://content/modes/base_mode.tres"
const OWN := 1

var _mode: GameMode
var _model: ClientModel
var _world: Node3D
var _player: PlayerController
var _life: LifeView
var _lens: Camera3D
var _lens_up := false


func before_test() -> void:
	_mode = load(MODE) as GameMode
	_model = ClientModel.new(_mode)
	_model.own_peer = OWN
	var member := ClientModel.Member.new()
	member.name = "Player1"
	_model.roster[OWN] = member
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3(0, 0, 5)) as PlayerController
	_player.rules = _mode.player_rules
	var avatars := AvatarViews.new()
	avatars.model = _model
	avatars.buffer = SnapshotBuffer.new()
	avatars.rules = _mode.player_rules
	avatars.clock = func() -> int: return 1000000
	_world.add_child(avatars)
	_lens = Camera3D.new()
	_lens.position = Vector3(3, 1.6, 0)
	_world.add_child(_lens)
	_life = LifeView.new()
	_life.model = _model
	_life.mode = _mode
	_life.avatars = avatars
	_life.player = _player
	_life.reads_device_input = false
	_life.view_camera = func() -> Camera3D: return _lens if _lens_up else null
	_world.add_child(_life)


func after_test() -> void:
	_world.free()


func test_the_living_see_through_the_view_camera_while_it_is_given() -> void:
	await _drawn()
	assert_bool(_player.get_camera().current).is_true()
	_lens_up = true
	_lens.make_current()
	await _drawn()
	assert_int(_life.view()).is_equal(LifeView.View.FIRST_PERSON)
	assert_bool(_lens.current).is_true()
	assert_object(get_viewport().get_camera_3d()).is_same(_lens)


func test_no_view_camera_gives_the_eye_back() -> void:
	_lens_up = true
	await _drawn()
	assert_bool(_lens.current).is_true()
	_lens_up = false
	await _drawn()
	assert_bool(_player.get_camera().current).is_true()
	assert_bool(_lens.current).is_false()


func test_the_downed_camera_wins_over_the_view_camera() -> void:
	_lens_up = true
	_model.lives[OWN] = ClientModel.Life.DOWNED
	_player.life = ClientModel.Life.DOWNED
	await _drawn()
	assert_int(_life.view()).is_equal(LifeView.View.DOWNED)
	assert_bool(_lens.current).is_false()


func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
