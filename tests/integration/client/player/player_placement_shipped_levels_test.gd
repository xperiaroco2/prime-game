extends GdUnitTestSuite
## A player placed at the markers of the shipped lobby and greybox levels stands: the crouch plays
## everywhere (#991), so a placement takes the crouched capsule first and stands only where the
## stand-up test finds room (the crouch ADR, step 7). A marker under a lamp or sunk into the floor
## would spawn the player crouched; none does.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")

var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_a_player_placed_at_each_lobby_marker_stands() -> void:
	await _check_markers("res://levels/lobby/lobby.tscn", "spawn_lobby_player")


func test_a_player_placed_at_each_greybox_round_marker_stands() -> void:
	await _check_markers("res://levels/greybox/greybox.tscn", "spawn_round_player")


func _check_markers(scene_path: String, group: String) -> void:
	var level := (load(scene_path) as PackedScene).instantiate() as Node3D
	_world.add_child(level)
	var markers: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(group):
		if level.is_ancestor_of(node):
			markers.append(node as Node3D)
	assert_int(markers.size()).is_greater(0)
	var player := _world.add_player(Vector3(0.0, 0.0, 40.0))
	await _world.frames(3)
	for marker: Node3D in markers:
		player.teleport(marker.global_transform)
		assert_bool(player.is_crouched()).is_false()
