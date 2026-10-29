extends GdUnitTestSuite
## The forest estate's box greybox (#1158) against its design doc (docs/design/estate-map.md §3):
## every module of the doc's table is its own scene, placed at its centre with no rotation and its
## footprint, showing its name; the creek's crossings stand at the doc's points; no tree stands in a
## clearing; the map only places pieces (docs/decisions/2026-10-09-level-piece-conventions.md).

const EstateDoc := preload("res://tests/fixtures/estate_doc.gd")
const NEAR := Vector3(1e-3, 1e-3, 1e-3)
## A tree trunk's half width: its side, not its centre, must stay out of a clearing.
const TRUNK_HALF_WIDTH := 0.4
## The map-wide pieces, each at the origin: the ground with its fence and roads, the creek, the
## paths, the tree strips, the base mode's markers (#1374) and the hidden passages (#1373).
const GROUNDS: Array[String] = ["Plot", "Creek", "Paths", "Trees", "Markers", "Passages"]


func test_the_doc_s_module_rows_all_parse() -> void:
	var modules := EstateDoc.modules()
	(
		assert_int(modules.size())
		. override_failure_message(
			"§3 has %d module rows but %d parse" % [EstateDoc.row_count(), modules.size()]
		)
		. is_equal(EstateDoc.row_count())
	)
	assert_int(modules.size()).is_greater(0)


func test_each_module_is_placed_at_its_centre_with_its_footprint() -> void:
	var map := _map()
	for module in EstateDoc.modules():
		var node := map.get_node_or_null(NodePath(EstateDoc.pascal(module.name))) as Node3D
		(
			assert_object(node)
			. override_failure_message("no module %s in the map" % module.name)
			. is_not_null()
		)
		if node == null:
			continue
		var at := Vector3(module.centre.x, 0, module.centre.y)
		(
			assert_vector(node.position)
			. override_failure_message(
				"%s is at %s, the doc says %s" % [module.name, node.position, at]
			)
			. is_equal_approx(at, NEAR)
		)
		(
			assert_bool(node.basis.is_equal_approx(Basis.IDENTITY))
			. override_failure_message("%s is rotated or scaled" % module.name)
			. is_true()
		)
		assert_str(node.scene_file_path).is_equal(
			EstateDoc.ROOMS + EstateDoc.snake(module.name) + ".tscn"
		)
		if module.size != Vector2i.ZERO:
			(
				assert_object(node.get_meta(&"size_m", null))
				. override_failure_message(
					(
						"%s: size_m %s, the doc says %s"
						% [module.name, node.get_meta(&"size_m", null), module.size]
					)
				)
				. is_equal(module.size)
			)


func test_each_module_shows_its_doc_name() -> void:
	# The greybox's floating names (#658): a walk finds its way by them until the art lands.
	var map := _map()
	for module in EstateDoc.modules():
		var label := map.get_node_or_null(NodePath(EstateDoc.pascal(module.name) + "/Name"))
		(
			assert_object(label)
			. override_failure_message("%s has no Name label" % module.name)
			. is_instanceof(Label3D)
		)
		if label is Label3D:
			assert_str((label as Label3D).text).is_equal(module.name)
			assert_bool((label as Label3D).visible).is_true()


func test_the_map_places_only_its_pieces_each_once() -> void:
	var map := _map()
	var expected: Array[String] = GROUNDS.duplicate()
	for module in EstateDoc.modules():
		expected.append(EstateDoc.pascal(module.name))
	var names: Array[String] = []
	for child in map.get_children():
		names.append(String(child.name))
		# The map holds no geometry of its own: each child is a piece's scene.
		(
			assert_str(child.scene_file_path)
			. override_failure_message("%s is not a piece of %s" % [child.name, EstateDoc.ROOMS])
			. starts_with(EstateDoc.ROOMS)
		)
	assert_array(names).contains_exactly_in_any_order(expected)
	for ground in GROUNDS:
		var node := map.get_node(NodePath(ground)) as Node3D
		assert_bool(node.transform.is_equal_approx(Transform3D.IDENTITY)).is_true()


func test_the_creek_s_crossings_stand_at_the_doc_s_points() -> void:
	var crossings := EstateDoc.crossings()
	assert_array(crossings.keys()).contains_exactly_in_any_order(
		["log bridge", "stepping stones", "drainage pipe", "plank footbridge"]
	)
	var creek := _map().get_node(^"Creek")
	for crossing in crossings:
		var node := creek.get_node_or_null(NodePath(EstateDoc.pascal(crossing))) as Node3D
		(
			assert_object(node)
			. override_failure_message("no crossing %s in the creek" % crossing)
			. is_not_null()
		)
		if node != null:
			var at := Vector3(crossings[crossing].x, 0, crossings[crossing].y)
			assert_vector(node.position).is_equal_approx(at, NEAR)


func test_no_tree_stands_in_a_clearing() -> void:
	# §1.2: trees grow in strips between the clearings, never in one.
	var trees := _map().get_node(^"Trees")
	assert_int(trees.get_child_count()).is_greater(0)
	for tree in trees.get_children():
		var at := (tree as Node3D).position
		for module in EstateDoc.modules():
			if module.radius <= 0:
				continue
			var off := Vector2(at.x, at.z).distance_to(module.centre) - TRUNK_HALF_WIDTH
			(
				assert_float(off)
				. override_failure_message(
					(
						"%s's side stands %.1f m from the %s, inside its %.0f m clearing"
						% [tree.name, off, module.name, module.radius]
					)
				)
				. is_greater_equal(module.radius)
			)


func test_six_cameras_one_in_each_place_of_the_camera_wall() -> void:
	# §5c (GDD §12): one camera each at the bonfire, the summer kitchen, the pantry, the
	# greenhouse, the garage and the roof terrace (the house); none anywhere else.
	var map := _map()
	var places: Array[String] = []
	for piece in map.get_children():
		var cameras := piece.get_node_or_null(^"CameraMarkers")
		if cameras != null:
			places.append(String(piece.name))
			assert_object(cameras.get_node_or_null(^"Camera01")).is_not_null()
			assert_object(cameras.get_node_or_null(^"Camera02")).is_null()
	assert_array(places).contains_exactly_in_any_order(
		["Bonfire", "SummerKitchen", "Pantry", "Greenhouse", "Garage", "House"]
	)


func _map() -> Node3D:
	return auto_free((load(EstateDoc.MAP) as PackedScene).instantiate()) as Node3D
