extends GdUnitTestSuite
## LevelScenes.children_read (#1489): a piece may name in `metadata/host_skips` the children its own
## script frees on the client (the ship inside the dead's hall). Neither of the host's level readers
## takes them. Scenes built in code: a part's test never loads levels/ (ARCHITECTURE §9.6).

const LEVEL := "res://levels/test_level.tscn"


func test_the_marker_reader_skips_what_host_skips_names() -> void:
	var root := _scene()
	var result := MarkerReader.read(root, LEVEL, FlatWorldQuery.new())
	assert_array(Array(result.errors)).is_empty()
	assert_array(Array(result.layout.positions(&"dead"))).is_equal([Vector3(1, 0, 0)])


func test_the_level_world_holds_no_collider_of_what_host_skips_names() -> void:
	var root := _scene()
	assert_int(LevelWorld.from_scene(root, LEVEL).body_count()).is_equal(1)
	(root.get_child(0) as Node).remove_meta(&"host_skips")
	assert_int(LevelWorld.from_scene(root, LEVEL).body_count()).is_equal(2)


func _scene() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	var piece := Node3D.new()
	piece.name = "Hall"
	piece.set_meta(&"host_skips", PackedStringArray(["Ship"]))
	root.add_child(piece)
	piece.add_child(_named("Kept", Vector3(1, 0, 0)))
	piece.add_child(_named("Ship", Vector3(2, 0, 0)))
	return root


## A body with a collider and a `dead` marker under it.
func _named(node_name: String, at: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	var marker := Marker3D.new()
	marker.position = at
	marker.add_to_group(&"spawn_dead")
	body.add_child(marker)
	return body
