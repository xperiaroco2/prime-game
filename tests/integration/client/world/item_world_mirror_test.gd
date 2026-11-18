extends GdUnitTestSuite
## ItemWorld wires the lobby mirror's reflection (#1395, ARCHITECTURE §4.7.68): setup gives it the
## model, the mode and the avatars' character; set_player the local player; set_level the level its
## glass marker is in; reset forgets them.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const MODE := "res://content/modes/base_mode.tres"

var _world: Node3D
var _player: PlayerController
var _harness: Harness
var _items: ItemWorld
var _avatars: AvatarViews


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"lobby")
	_items = ItemWorld.new()
	_world.add_child(_items)
	_avatars = AvatarViews.new()
	_world.add_child(_avatars)


func after_test() -> void:
	_world.free()
	_harness.close()


func test_setup_player_level_and_reset_reach_the_mirror() -> void:
	var mode := load(MODE) as GameMode
	_items.setup(_harness.session, mode, _avatars)
	_items.set_player(_player)
	var mirror := _items.mirror
	assert_object(mirror.model).is_same(_harness.session.model)
	assert_object(mirror.mode).is_same(mode)
	assert_object(mirror.character).is_same(_avatars.character)
	assert_object(mirror.player).is_same(_player)
	var level := Node3D.new()
	_world.add_child(level)
	var marker := Marker3D.new()
	marker.add_to_group(MirrorReflection.GLASS_GROUP)
	marker.position = Vector3(0, 1.25, -5)
	level.add_child(marker)
	_items.set_level(level)
	assert_object(mirror.level).is_same(level)
	assert_bool(mirror.glass.visible).is_true()
	_items.reset()
	assert_object(mirror.model).is_null()
	assert_object(mirror.mode).is_null()
	assert_object(mirror.player).is_null()
	_items.set_level(null)
	assert_bool(mirror.glass.visible).is_false()
