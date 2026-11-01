extends GdUnitTestSuite
## LevelLayout's facings (ARCHITECTURE §9.6, #1522): each marker's yaw as a level unit vector,
## parallel to its positions, none (Vector3.ZERO) for a marker added without one.


func test_a_marker_keeps_its_facing_level_and_unit() -> void:
	var layout := LevelLayout.new("res://map.tscn")
	layout.add_marker(&"respawn", Vector3(1, 0, 0), Vector3(0, 0, 2))
	layout.add_marker(&"respawn", Vector3(2, 0, 0), Vector3(-3, 4, 0))
	layout.add_marker(&"respawn", Vector3(3, 0, 0))
	layout.add_marker(&"respawn", Vector3(4, 0, 0), Vector3.UP)
	assert_array(Array(layout.facings(&"respawn"))).is_equal(
		[Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3.ZERO, Vector3.ZERO]
	)
	assert_vector(layout.facing_at(&"respawn", 0)).is_equal(Vector3(0, 0, 1))
	assert_vector(layout.facing_at(&"respawn", 4)).is_equal(Vector3.ZERO)
	assert_vector(layout.facing_at(&"knife", 0)).is_equal(Vector3.ZERO)
	assert_vector(layout.facing_at(&"respawn", -1)).is_equal(Vector3.ZERO)


func test_the_dict_carries_the_facings_of_faced_tags_only() -> void:
	var layout := LevelLayout.new("res://map.tscn")
	layout.add_marker(&"package", Vector3(1, 0, 0))
	layout.add_marker(&"respawn", Vector3(2, 0, 0))
	layout.add_marker(&"respawn", Vector3(3, 0, 0), Vector3.BACK)
	(
		assert_dict(layout.to_dict())
		. is_equal(
			{
				"path": "res://map.tscn",
				"markers":
				{
					"package": PackedVector3Array([Vector3(1, 0, 0)]),
					"respawn": PackedVector3Array([Vector3(2, 0, 0), Vector3(3, 0, 0)]),
				},
				"facings": {"respawn": PackedVector3Array([Vector3.ZERO, Vector3.BACK])},
			}
		)
	)


func test_a_log_reads_the_facings_back_and_none_when_missing() -> void:
	var layout := LevelLayout.new("res://map.tscn")
	layout.add_marker(&"respawn", Vector3(2, 0, 0), Vector3.LEFT)
	layout.add_marker(&"lobby_player", Vector3(3, 0, 0))
	var saved := CommandLog.new()
	saved.layouts[layout.path] = layout
	var data := saved.to_dict()
	var read := CommandLog.from_dict(data)
	assert_dict(read.to_dict()).is_equal(data)
	assert_vector(read.layouts[layout.path].facing_at(&"respawn", 0)).is_equal(Vector3.LEFT)
	var older: Dictionary = data.duplicate(true)
	(older["layouts"][layout.path] as Dictionary).erase("facings")
	var old_read := CommandLog.from_dict(older)
	assert_vector(old_read.layouts[layout.path].facing_at(&"respawn", 0)).is_equal(Vector3.ZERO)
	assert_vector(old_read.layouts[layout.path].positions(&"respawn")[0]).is_equal(Vector3(2, 0, 0))
