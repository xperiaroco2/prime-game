extends GdUnitTestSuite
## StripLayout, StripLooks and BoothUse (#1397, ARCHITECTURE §4.7.62): the strip image's frames from
## 1 to 8, a missed frame blank, each frame faced to the camera from its record alone; the strip's
## look; the strip kind read from the mode.

const BASE_MODE := "res://content/modes/base_mode.tres"


func _row(position: Vector3, facing: Vector3) -> Dictionary:
	return {"peer": 1, "colour": 0, "position": position, "facing": facing}


func test_the_frames_stack_inside_the_strip_without_overlap_for_1_to_8() -> void:
	for frames in range(1, StripLayout.MAX_FRAMES + 1):
		var bounds := Rect2i(Vector2i.ZERO, StripLayout.size(frames))
		for index in frames:
			var rect := StripLayout.frame_rect(index)
			assert_bool(bounds.encloses(rect)).is_true()
			if index > 0:
				assert_bool(rect.intersects(StripLayout.frame_rect(index - 1))).is_false()
	assert_that(StripLayout.size(0)).is_equal(StripLayout.size(1))
	assert_that(StripLayout.size(20)).is_equal(StripLayout.size(StripLayout.MAX_FRAMES))


func test_compose_puts_each_frame_in_its_rectangle_and_a_missed_one_blank() -> void:
	var pictures: Dictionary[int, Image] = {}
	for index: int in [0, 2]:
		var picture := Image.create_empty(64, 48, false, Image.FORMAT_RGBA8)
		picture.fill(Color.RED if index == 0 else Color.BLUE)
		pictures[index] = picture
	var image := StripLayout.compose(3, pictures)
	assert_that(image.get_size()).is_equal(StripLayout.size(3))
	assert_that(image.get_pixelv(StripLayout.frame_rect(0).get_center())).is_equal(Color.RED)
	assert_that(image.get_pixelv(StripLayout.frame_rect(2).get_center())).is_equal(Color.BLUE)
	var blank := image.get_pixelv(StripLayout.frame_rect(1).get_center())
	assert_float(blank.r).is_equal_approx(StripLayout.MISSED.r, 0.01)
	assert_float(image.get_pixel(1, 1).r).is_equal_approx(StripLayout.PAPER.r, 0.01)


func test_the_mean_facing_turns_to_the_camera_for_any_yaw() -> void:
	for degrees: float in [0.0, 37.0, 90.0, 180.0, -120.0]:
		var facing := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(degrees))
		var rows: Array[Dictionary] = [
			_row(Vector3(10, 2, 5), facing), _row(Vector3(11, 2, 5), facing)
		]
		var view := StripLayout.view_of(rows)
		var local := StripLayout.local_row(rows[0], view)
		var turned := local["facing"] as Vector3
		assert_vector(turned).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)
		var centre_offset := (local["position"] as Vector3).length()
		assert_float(centre_offset).is_equal_approx(0.5, 0.001)


func test_the_rows_centre_sits_at_the_origin() -> void:
	var rows: Array[Dictionary] = [
		_row(Vector3(4, 1, 0), Vector3.BACK), _row(Vector3(6, 1, 2), Vector3.BACK)
	]
	var view := StripLayout.view_of(rows)
	assert_vector(view.centre).is_equal(Vector3(5, 1, 1))
	var sum := Vector3.ZERO
	for row: Dictionary in rows:
		sum += StripLayout.local_row(row, view)["position"] as Vector3
	assert_vector(sum).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_zero_vertical_or_opposite_facings_turn_nothing() -> void:
	var rows: Array[Dictionary] = [_row(Vector3.ZERO, Vector3.ZERO), _row(Vector3.ONE, Vector3.UP)]
	assert_that(StripLayout.view_of(rows).turn).is_equal(Basis.IDENTITY)
	var opposite: Array[Dictionary] = [
		_row(Vector3.ZERO, Vector3.FORWARD), _row(Vector3.ONE, Vector3.BACK)
	]
	assert_that(StripLayout.view_of(opposite).turn).is_equal(Basis.IDENTITY)
	assert_that(StripLayout.view_of([] as Array[Dictionary]).turn).is_equal(Basis.IDENTITY)


func test_the_camera_looks_at_the_group_from_the_front() -> void:
	var camera := StripLayout.camera_transform()
	assert_float(camera.origin.z).is_greater(0.0)
	var forward := -camera.basis.z
	assert_float(forward.dot(Vector3.FORWARD)).is_greater(0.9)


func test_the_strip_look_has_a_picture_slot_and_its_size() -> void:
	var look: Node3D = auto_free(StripLooks.build(StripLooks.STRIP))
	assert_object(PhotoLooks.picture_of(look)).is_not_null()
	assert_bool(StripLooks.has(&"strip")).is_true()
	assert_bool(StripLooks.has(&"photo")).is_false()
	assert_that(ItemView.size_of(&"strip")).is_equal(StripLooks.SIZE)
	var texture := ImageTexture.create_from_image(
		Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	)
	PhotoLooks.set_picture(look, texture)
	var material := PhotoLooks.picture_of(look).material_override as StandardMaterial3D
	assert_object(material.albedo_texture).is_same(texture)
	assert_bool(material.no_depth_test).is_false()


func test_the_base_modes_strip_kind_is_the_looks_kind() -> void:
	var mode := load(BASE_MODE) as GameMode
	assert_array(BoothUse.strip_kinds(mode)).contains_exactly([StripLooks.STRIP])
	assert_bool(BoothUse.is_strip(mode, &"strip")).is_true()
	assert_bool(BoothUse.is_strip(mode, &"photo")).is_false()
	assert_bool(BoothUse.is_strip(null, &"strip")).is_false()
