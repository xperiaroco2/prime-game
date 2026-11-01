extends GdUnitTestSuite
## GameLevel.sync (#1520): the lobby is loaded again on every lobby phase, so a player back from a
## round (End -> Lobby) stands in the same lit hall as before it, not in an empty World.

const BASE_MODE := "res://content/modes/base_mode.tres"

var _world: Node3D
var _levels: GameLevel


func before_test() -> void:
	_world = auto_free(Node3D.new()) as Node3D
	add_child(_world)
	var items := auto_free(ItemWorld.new()) as ItemWorld
	var ui := auto_free(GameUi.new()) as GameUi
	_world.add_child(items)
	_levels = GameLevel.new()
	_levels.setup(_world, items, ui)


func test_the_lobby_loads_again_after_a_round() -> void:
	var lobby := (load(BASE_MODE) as GameMode).lobby_level
	_levels.sync(PhaseSpec.Level.LOBBY, lobby)
	var first := _levels.node
	assert_object(first).is_not_null()
	assert_str(first.scene_file_path).is_equal(lobby)
	_levels.sync(PhaseSpec.Level.MAP, lobby)
	first.free()
	assert_object(_levels.node).is_null()
	assert_int(_levels.kind).is_equal(PhaseSpec.Level.NONE)
	_levels.sync(PhaseSpec.Level.LOBBY, lobby)
	assert_object(_levels.node).is_not_null()
	assert_object(_levels.node).is_not_same(first)
	assert_str(_levels.node.scene_file_path).is_equal(lobby)
	assert_int(_levels.kind).is_equal(PhaseSpec.Level.LOBBY)
	assert_object(_levels.node.get_parent()).is_same(_world)
	var last := _levels.node
	_levels.clear()
	last.free()
