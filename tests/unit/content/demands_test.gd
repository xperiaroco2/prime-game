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
		assert_array(HostText.to_dicts(demands.shortfalls(layout)))
		. is_equal(
			[
				{
					"id": &"markers",
					"ids": PackedStringArray(["package"]),
					"numbers": {&"need": 4, &"have": 2}
				},
				{
					"id": &"colours",
					"ids": PackedStringArray(["circle"]),
					"numbers": {&"need": 3, &"have": 2}
				},
			]
		)
	)
	for i in 2:
		layout.add_marker(&"package", Vector3(i, 0, 1))
	circle.palette = PackedColorArray([Color.RED, Color.BLUE, Color.GREEN])
	demands.add_colours(circle, 0)
	assert_array(Array(demands.shortfalls(layout))).is_empty()


func test_an_exact_demand_names_any_other_count_as_markers_exact() -> void:
	var demands := Demands.new(null)
	demands.add_markers(&"switch", 4, true)
	demands.add_markers(&"package", 1)
	for have: int in [3, 5, 4]:
		var layout := LevelLayout.new()
		for i in have:
			layout.add_marker(&"switch", Vector3(i, 0, 0))
		for i in 3:
			layout.add_marker(&"package", Vector3(i, 0, 1))
		var expected: Array[Dictionary] = []
		if have != 4:
			expected.append(
				{
					"id": &"markers_exact",
					"ids": PackedStringArray(["switch"]),
					"numbers": {&"need": 4, &"have": have}
				}
			)
		assert_array(HostText.to_dicts(demands.shortfalls(layout))).is_equal(expected)
