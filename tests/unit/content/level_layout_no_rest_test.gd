extends GdUnitTestSuite
## LevelLayout's no-rest volumes (ARCHITECTURE §7.1.16, §9.6; the throwing ADR's TD5 (b)): boxes in
## level order, a point inside any of them, faces included, and the plain data the command log
## keeps, which CommandLog reads back.

const BOX := AABB(Vector3(0, 6, 0), Vector3(4, 2, 3))


func test_a_layout_without_volumes_bars_nothing_and_its_data_is_unchanged() -> void:
	var layout := LevelLayout.new("res://map.tscn")
	assert_bool(layout.is_no_rest(Vector3.ZERO)).is_false()
	assert_array(layout.no_rest_volumes()).is_empty()
	assert_dict(layout.to_dict()).is_equal({"path": "res://map.tscn", "markers": {}})


func test_a_point_inside_a_volume_or_on_its_faces_is_barred_and_one_beyond_is_not() -> void:
	var layout := LevelLayout.new()
	layout.add_no_rest(BOX)
	assert_bool(layout.is_no_rest(Vector3(2, 7, 1.5))).is_true()
	# Every face, edge and corner is inside: a floor lying on the box's bottom face is in it.
	assert_bool(layout.is_no_rest(Vector3(2, 6, 1.5))).is_true()
	assert_bool(layout.is_no_rest(Vector3(2, 8, 1.5))).is_true()
	assert_bool(layout.is_no_rest(Vector3(0, 7, 1.5))).is_true()
	assert_bool(layout.is_no_rest(Vector3(4, 7, 3))).is_true()
	assert_bool(layout.is_no_rest(Vector3(0, 6, 0))).is_true()
	assert_bool(layout.is_no_rest(Vector3(4, 8, 3))).is_true()
	for beyond: Vector3 in [
		Vector3(2, 5.999, 1.5),
		Vector3(2, 8.001, 1.5),
		Vector3(-0.001, 7, 1.5),
		Vector3(4.001, 7, 1.5),
		Vector3(2, 7, -0.001),
		Vector3(2, 7, 3.001),
	]:
		assert_bool(layout.is_no_rest(beyond)).override_failure_message(str(beyond)).is_false()


func test_a_point_in_either_of_two_volumes_is_barred() -> void:
	var layout := LevelLayout.new()
	layout.add_no_rest(BOX)
	layout.add_no_rest(AABB(Vector3(10, 0, 10), Vector3(1, 1, 1)))
	assert_bool(layout.is_no_rest(Vector3(1, 7, 1))).is_true()
	assert_bool(layout.is_no_rest(Vector3(10.5, 0.5, 10.5))).is_true()
	assert_bool(layout.is_no_rest(Vector3(7, 3, 7))).is_false()


func test_the_volumes_are_a_copy_in_level_order() -> void:
	var layout := LevelLayout.new()
	var second := AABB(Vector3(-5, 0, 0), Vector3(1, 1, 1))
	layout.add_no_rest(BOX)
	layout.add_no_rest(second)
	var volumes := layout.no_rest_volumes()
	assert_array(volumes).is_equal([BOX, second])
	volumes.clear()
	assert_int(layout.no_rest_volumes().size()).is_equal(2)


func test_the_volumes_are_in_the_plain_data_and_read_back_by_the_command_log() -> void:
	var layout := LevelLayout.new("res://map.tscn")
	layout.add_marker(&"package", Vector3(1, 0, 0))
	layout.add_no_rest(BOX)
	var data := layout.to_dict()
	assert_array(data["no_rest"] as Array).is_equal([BOX])
	var log := CommandLog.new()
	log.layouts["res://map.tscn"] = layout
	var read := CommandLog.from_dict(log.to_dict())
	var back := read.layouts["res://map.tscn"]
	assert_array(back.no_rest_volumes()).is_equal([BOX])
	assert_bool(back.is_no_rest(Vector3(1, 7, 1))).is_true()
	assert_dict(back.to_dict()).is_equal(data)


func test_a_saved_layout_without_volumes_reads_back_with_none() -> void:
	var read := CommandLog.from_dict(
		{"layouts": {"res://map.tscn": {"path": "res://map.tscn", "markers": {}}}}
	)
	assert_array(read.layouts["res://map.tscn"].no_rest_volumes()).is_empty()
