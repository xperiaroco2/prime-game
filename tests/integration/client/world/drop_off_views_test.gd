extends GdUnitTestSuite
## The client's view of Delivery by meaning (DE11 of the delivery-by-meaning ADR, #830), on fixture
## modes (#767): a drop-off is told from a circle by which of the mode's Delivery types lists its
## kind; a drop-off is an open tube of its kind's size in one neutral colour, never
## StationPlaced's, dimmed when done; a circle beside it keeps its coloured cylinder; an item of
## this Delivery is a box labelled with its kind's name, never tinted by ItemSpawned's colour;
## nothing draws through walls (the M4 ADR's §3 item 5).

const DROP_OFF := 0
const CIRCLE := 1
const WINE := 3
const RED := Color(0.9, 0.2, 0.2)
const MAGENTA := Color(0.9, 0.1, 0.9)
const NAME := "Fixture wine"

var _mode: GameMode
var _model: ClientModel
var _world: Node3D
var _circles: CircleViews
var _items: ItemViews


func before_test() -> void:
	_mode = FixtureMeaningModes.basic()
	_mode.find_item_kind(&"wine").display_name = NAME
	var colours := FixtureDeliveryModes.delivery(_mode.find_item_kind(&"package"))
	colours.id = &"colour_delivery"
	_mode.task_types.append(colours)
	_model = ClientModel.new(_mode)
	_model.own_peer = 1
	_world = Node3D.new()
	add_child(_world)
	_circles = CircleViews.new()
	_circles.model = _model
	_circles.mode = _mode
	_world.add_child(_circles)
	_items = ItemViews.new()
	_items.model = _model
	_items.mode = _mode
	_world.add_child(_items)
	# A drop-off's StationPlaced colour is white (DE5 (b)); any other colour is not drawn either.
	_station(DROP_OFF, &"drop_a", MAGENTA, Vector3(5, 0, 5))
	_station(CIRCLE, &"circle", RED, Vector3(-5, 0, -5))


func after_test() -> void:
	_world.free()


func test_the_mode_tells_a_drop_off_from_a_circle_by_its_delivery_types() -> void:
	for kind: StringName in FixtureMeaningModes.DROP_OFFS:
		assert_bool(CircleViews.is_drop_off(_mode, kind)).override_failure_message(kind).is_true()
	assert_bool(CircleViews.is_drop_off(_mode, &"circle")).is_false()
	assert_bool(CircleViews.is_drop_off(_mode, &"zone")).is_false()
	assert_bool(CircleViews.is_drop_off(null, &"drop_a")).is_false()


func test_a_drop_off_is_an_open_neutral_tube_and_a_circle_keeps_its_coloured_cylinder() -> void:
	await _drawn()
	var drop_off := _circles.view_of(DROP_OFF)
	var tube := drop_off.mesh as CylinderMesh
	assert_float(tube.top_radius).is_equal(FixtureMeaningModes.RADIUS_M)
	assert_float(tube.bottom_radius).is_equal(FixtureMeaningModes.RADIUS_M)
	assert_float(tube.height).is_equal(FixtureMeaningModes.HEIGHT_M)
	assert_bool(tube.cap_top).is_false()
	assert_bool(tube.cap_bottom).is_false()
	assert_vector(drop_off.global_position).is_equal(
		Vector3(5, FixtureMeaningModes.HEIGHT_M / 2, 5)
	)
	var neutral := _colour(drop_off)
	assert_float(neutral.r).is_equal_approx(CircleViews.DROP_OFF_COLOUR.r, 1e-5)
	assert_float(neutral.g).is_equal_approx(CircleViews.DROP_OFF_COLOUR.g, 1e-5)
	assert_float(neutral.b).is_equal_approx(CircleViews.DROP_OFF_COLOUR.b, 1e-5)
	var circle := _circles.view_of(CIRCLE)
	assert_bool((circle.mesh as CylinderMesh).cap_top).is_true()
	assert_bool((circle.mesh as CylinderMesh).cap_bottom).is_true()
	assert_float(_colour(circle).r).is_equal_approx(RED.r, 1e-5)
	assert_float(_colour(circle).g).is_equal_approx(RED.g, 1e-5)
	assert_str(String(drop_off.name)).is_not_equal(String(circle.name))


func test_a_drop_off_dims_when_done() -> void:
	_spawn_wine(Vector3(5, 0, 5))
	await _drawn()
	var view := _circles.view_of(DROP_OFF)
	var open := _colour(view)
	_model.fold(&"PackageDelivered", {"item": WINE, "station": DROP_OFF})
	await _drawn()
	var done := _colour(view)
	assert_float(done.a).is_less(open.a)
	assert_float(done.r).is_less(open.r)


func test_an_item_of_this_delivery_is_a_box_labelled_with_its_name_never_tinted() -> void:
	_spawn_wine(Vector3(1, 0, 1))
	await _drawn()
	var view := _items.view_of(WINE)
	var labels := view.find_children("*", "Label3D", true, false)
	assert_int(labels.size()).is_equal(1)
	var label := labels[0] as Label3D
	assert_str(label.text).is_equal(ContentNames.text(ContentNames.item(&"wine", _mode)))
	assert_str(label.text).is_not_equal("wine")
	assert_bool(label.no_depth_test).is_false()
	var box := view.look().get_node(^"Box") as MeshInstance3D
	var colour := ((box.mesh as BoxMesh).material as StandardMaterial3D).albedo_color
	assert_that(colour).is_equal(ItemView.UNKNOWN_COLOUR)
	assert_that(colour).is_not_equal(MAGENTA)


func test_nothing_of_either_look_draws_through_walls() -> void:
	_spawn_wine(Vector3(1, 0, 1))
	await _drawn()
	for node: Node in _world.find_children("*", "", true, false):
		var label := node as Label3D
		if label != null:
			assert_bool(label.no_depth_test).override_failure_message(str(node.name)).is_false()
		var mesh_view := node as MeshInstance3D
		if mesh_view == null:
			continue
		var material := mesh_view.material_override as BaseMaterial3D
		if material != null:
			assert_bool(material.no_depth_test).override_failure_message(str(node.name)).is_false()


func _spawn_wine(at: Vector3) -> void:
	_model.fold(
		&"ItemSpawned",
		{"item": WINE, "kind": &"wine", "position": at, "station": DROP_OFF, "colour": MAGENTA}
	)


func _station(id: int, kind: StringName, colour: Color, at: Vector3) -> void:
	_model.fold(&"StationPlaced", {"station": id, "kind": kind, "colour": colour, "position": at})


func _colour(view: MeshInstance3D) -> Color:
	return (view.material_override as StandardMaterial3D).albedo_color


func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
