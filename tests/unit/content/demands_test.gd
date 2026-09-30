extends GdUnitTestSuite
## Demands and LevelLayout (ARCHITECTURE §9.4, §9.6): what a match needs of a map, compared per
## spawn tag with the map's markers, and colours with a station kind's palette.


func test_a_layout_keeps_markers_per_tag_in_level_order() -> void:
	var layout := LevelLayout.new("res://map.tscn")
	layout.add_marker(&"package", Vector3(1, 0, 0))
	layout.add_marker(&"circle", Vector3(5, 0, 0))
	layout.add_marker(&"package", Vector3(2, 0, 0))
	assert_array(Array(layout.positions(&"package"))).is_equal([Vector3(1, 0, 0), Vector3(2, 0, 0)])
	assert_int(layout.count(&"circle")).is_equal(1)
	assert_int(layout.count(&"knife")).is_equal(0)
	assert_array(layout.tags()).is_equal([&"circle", &"package"])
	(
		assert_dict(layout.to_dict())
		. is_equal(
			{
				"path": "res://map.tscn",
				"markers":
				{
					"circle": PackedVector3Array([Vector3(5, 0, 0)]),
					"package": PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)]),
				},
			}
		)
	)


func test_demands_add_up_and_name_every_shortfall() -> void:
	var circle := StationKind.new()
	circle.id = &"circle"
	circle.palette = PackedColorArray([Color.RED, Color.BLUE])
	var demands := Demands.new(null)
	demands.add_markers(&"package", 3)
	demands.add_markers(&"package", 1)
	demands.add_markers(&"knife", 1)
	demands.add_colours(circle, 3)
	var layout := LevelLayout.new()
	for i in 2:
		layout.add_marker(&"package", Vector3(i, 0, 0))
	layout.add_marker(&"knife", Vector3.ZERO)
	(
		assert_array(Array(demands.shortfalls(layout)))
		. is_equal(
			[
				"4 package marker(s) needed, the map has 2",
				"3 circle colour(s) needed, the palette has 2",
			]
		)
	)
	for i in 2:
		layout.add_marker(&"package", Vector3(i, 0, 1))
	circle.palette = PackedColorArray([Color.RED, Color.BLUE, Color.GREEN])
	demands.add_colours(circle, 0)
	assert_array(Array(demands.shortfalls(layout))).is_empty()
