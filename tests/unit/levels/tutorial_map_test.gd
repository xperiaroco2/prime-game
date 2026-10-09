extends GdUnitTestSuite
## The tutorial's room against its design (#600; docs/design/tutorial.md §4, D33, D34) and the level
## piece conventions (#607): the map places one room, at the origin with no rotation, about 12 x
## 10 m; the room passes the host's level check (#112: layer-1 colliders, no CSG collision); its
## markers are the design's stations, each on the floor inside the room, no `lobby_player`;
## the drop-off is across the room from the shelf, and the respawn marker is farther than the
## mode's respawn_free_m from the corner's stand-in and within the voice radius of it.

const MAP := "res://levels/tutorial/tutorial.tscn"
const ROOM := "res://levels/tutorial/rooms/tutorial_room.tscn"
const MODE := "res://content/modes/tutorial_mode.tres"


func test_the_map_places_one_room_at_the_origin() -> void:
	var map: Node3D = auto_free((load(MAP) as PackedScene).instantiate())
	assert_int(map.get_child_count()).is_equal(1)
	var room := map.get_child(0) as Node3D
	assert_str(room.scene_file_path).is_equal(ROOM)
	assert_bool(room.transform.is_equal_approx(Transform3D.IDENTITY)).is_true()
	assert_object(room.get_meta(&"size_m")).is_equal(Vector2i(12, 10))
	assert_str((room.get_node(^"Name") as Label3D).text).is_equal("Tutorial")


func test_the_room_passes_the_host_s_level_check() -> void:
	var world := LevelWorld.build(MAP)
	assert_array(Array(world.errors)).is_empty()
	assert_int(world.body_count()).is_greater(0)


func test_the_markers_are_the_design_s_stations_on_the_floor() -> void:
	var layout := _layout()
	var counts := {}
	for tag: StringName in layout.tags():
		counts[tag] = layout.count(tag)
		for at: Vector3 in layout.positions(tag):
			assert_float(at.y).override_failure_message(str(tag)).is_equal_approx(0.0, 1e-6)
			var inside := at.x > 0.0 and at.x < 12.0 and at.z > 0.0 and at.z < 10.0
			assert_bool(inside).override_failure_message("%s at %s" % [tag, at]).is_true()
	assert_dict(counts).is_equal(
		{&"round_player": 3, &"package": 1, &"knife": 1, &"circle": 1, &"respawn": 1}
	)


func test_the_drop_off_is_across_the_room_from_the_shelf() -> void:
	# The design: a package put down by the shelf in lesson 2 is not delivered by chance.
	var layout := _layout()
	var shelf := layout.positions(&"package")[0]
	var drop_off := layout.positions(&"circle")[0]
	assert_bool(shelf.z < 5.0 and drop_off.z > 5.0).is_true()


func test_the_respawn_is_free_of_the_corner_and_within_its_voice_radius() -> void:
	var mode := load(MODE) as GameMode
	var layout := _layout()
	var corner := layout.positions(&"round_player")[2]
	var respawn := layout.positions(&"respawn")[0]
	var radius := (mode.find_phase(&"death_stage").voice_rule as RoundVoice).living_m
	var apart := corner.distance_to(respawn)
	assert_float(apart).is_greater(mode.player_rules.respawn_free_m)
	assert_float(apart).is_less(radius)


func _layout() -> LevelLayout:
	var levels := MarkerReader.read_levels(load(MODE) as GameMode, FlatWorldQuery.new())
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts[MAP]
