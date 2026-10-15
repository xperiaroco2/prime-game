extends GdUnitTestSuite
## The viewfinder's framing (#786, photo P7; ARCHITECTURE §4.7.56; the photo ADR §3.1): the lens's
## vertical field of view for a screen (PhotoViewfinder.fov_for) and where the photo shows on it
## (photo_rect, the mask's opening). The frame's four corners, the host's PhotoFrame edges at any
## depth, project onto the opening's four corners through a Camera3D set up as the viewfinder sets
## its lens (`keep_aspect` KEEP_HEIGHT, `fov` from fov_for, at the frame's pose), on a screen wider
## than the photo and on one narrower.

const FOV_DEG := 60.0
const ASPECT := 1.5


func test_a_screen_as_wide_as_the_photo_or_wider_keeps_the_frame_s_fov() -> void:
	assert_float(PhotoViewfinder.fov_for(FOV_DEG, ASPECT, Vector2(1920, 1080))).is_equal(FOV_DEG)
	assert_float(PhotoViewfinder.fov_for(FOV_DEG, ASPECT, Vector2(1500, 1000))).is_equal(FOV_DEG)


func test_a_narrower_screen_widens_the_fov_until_the_frame_s_width_fits() -> void:
	var fov := PhotoViewfinder.fov_for(FOV_DEG, ASPECT, Vector2(900, 1000))
	assert_float(fov).is_greater(FOV_DEG)
	var half_width := tan(deg_to_rad(fov) / 2.0) * 0.9
	assert_float(half_width).is_equal_approx(tan(deg_to_rad(FOV_DEG) / 2.0) * ASPECT, 1e-5)


func test_a_degenerate_screen_keeps_the_frame_s_fov() -> void:
	assert_float(PhotoViewfinder.fov_for(FOV_DEG, ASPECT, Vector2.ZERO)).is_equal(FOV_DEG)
	assert_float(PhotoViewfinder.fov_for(FOV_DEG, 0.0, Vector2(800, 600))).is_equal(FOV_DEG)


func test_the_photo_fills_the_height_on_a_wide_screen_and_the_width_on_a_narrow_one() -> void:
	var wide := PhotoViewfinder.photo_rect(ASPECT, Vector2(1920, 1080))
	assert_vector(wide.size).is_equal_approx(Vector2(1620, 1080), Vector2.ONE * 1e-3)
	assert_vector(wide.position).is_equal_approx(Vector2(150, 0), Vector2.ONE * 1e-3)
	var narrow := PhotoViewfinder.photo_rect(ASPECT, Vector2(900, 1000))
	assert_vector(narrow.size).is_equal_approx(Vector2(900, 600), Vector2.ONE * 1e-3)
	assert_vector(narrow.position).is_equal_approx(Vector2(0, 200), Vector2.ONE * 1e-3)


func test_the_frame_s_corners_project_onto_the_mask_s_corners_on_a_wide_screen() -> void:
	await _assert_corners_meet(Vector2i(1920, 1080))


func test_the_frame_s_corners_project_onto_the_mask_s_corners_on_a_narrow_screen() -> void:
	await _assert_corners_meet(Vector2i(900, 1000))


func test_the_frame_s_corners_project_onto_the_mask_s_corners_on_a_square_screen() -> void:
	await _assert_corners_meet(Vector2i(1000, 1000))


## A Camera3D in a SubViewport of `screen`, set up as PhotoViewfinder sets its lens for a frame
## that looks down and sideways, sees each of the frame's corners (PhotoFrame's edges, near and
## far) at the matching corner of photo_rect, within half a pixel.
func _assert_corners_meet(screen: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = screen
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var camera := Camera3D.new()
	# The viewfinder's own lens settings.
	var lens := (auto_free(PhotoViewfinder.new()) as PhotoViewfinder).camera
	camera.keep_aspect = lens.keep_aspect
	camera.near = lens.near
	camera.far = 50.0
	viewport.add_child(camera)
	add_child(viewport)
	var frame := PhotoFrame.between(Vector3(1, 1.6, 2), Vector3(-3, 1.2, -6), FOV_DEG, ASPECT, 10.0)
	camera.global_transform = Transform3D(frame.basis, frame.lens)
	camera.fov = PhotoViewfinder.fov_for(FOV_DEG, ASPECT, Vector2(screen))
	camera.make_current()
	await get_tree().process_frame
	var tan_v := tan(deg_to_rad(FOV_DEG) / 2.0)
	var tan_h := tan_v * ASPECT
	var rect := PhotoViewfinder.photo_rect(ASPECT, Vector2(screen))
	for depth: float in [1.0, 7.5]:
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var edge := Vector3(sx * depth * tan_h, sy * depth * tan_v, -depth)
				var corner := frame.lens + frame.basis * edge
				# Just inside the corner is in the frame (the corner is on its edges, up to rounding).
				var inside := edge * Vector3(0.999, 0.999, 1.0)
				assert_bool(frame.contains(frame.lens + frame.basis * inside)).is_true()
				var expected := Vector2(
					rect.position.x if sx < 0.0 else rect.end.x,
					rect.end.y if sy < 0.0 else rect.position.y
				)
				assert_vector(camera.unproject_position(corner)).is_equal_approx(
					expected, Vector2.ONE * 0.5
				)
	viewport.free()
