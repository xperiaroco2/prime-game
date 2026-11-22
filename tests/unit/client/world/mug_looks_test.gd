extends GdUnitTestSuite
## The mug's placeholder look (client/world/MugLooks, #1678): both kinds of the base mode, a
## cylinder with a handle on its +X side standing on its origin, and ItemView draws it with no
## label or box.


func test_both_kinds_of_the_base_mode_are_mugs() -> void:
	var mode := load("res://content/modes/base_mode.tres") as GameMode
	for kind: StringName in MugLooks.KINDS:
		assert_bool(MugLooks.has(kind)).is_true()
		assert_object(mode.find_item_kind(kind)).override_failure_message(String(kind)).is_not_null()
	assert_bool(MugLooks.has(&"knife")).is_false()


func test_the_mug_stands_on_its_origin_with_the_handle_on_its_side() -> void:
	var mug: Node3D = auto_free(MugLooks.build(&"mug"))
	var body := mug.get_node(^"Body") as MeshInstance3D
	var handle := mug.get_node(^"Handle") as MeshInstance3D
	var body_box := body.transform * body.get_aabb()
	assert_float(body_box.position.y).is_equal_approx(0.0, 1e-4)
	assert_vector(body_box.size).is_equal_approx(MugLooks.SIZE, Vector3.ONE * 1e-4)
	var handle_box := handle.transform * handle.get_aabb()
	# It stands up on the +X side, past the body and within its height, flat in Z.
	assert_float(handle_box.end.x).is_greater(body_box.end.x)
	assert_float(handle_box.position.y).is_greater(0.0)
	assert_float(handle_box.end.y).is_less(MugLooks.SIZE.y)
	assert_float(handle_box.size.z).is_less(handle_box.size.y)


func test_an_item_view_of_a_mug_is_the_placeholder_with_no_label() -> void:
	for kind: StringName in MugLooks.KINDS:
		var view: ItemView = auto_free(ItemView.make(3, kind, Color.WHITE))
		assert_object(view.look().find_child("Mug", false, false)).is_not_null()
		assert_object(view.look().find_child("Box", true, false)).is_null()
		assert_int(view.find_children("*", "Label3D", true, false).size()).is_zero()
		assert_vector(ItemView.size_of(kind)).is_equal(MugLooks.SIZE)
