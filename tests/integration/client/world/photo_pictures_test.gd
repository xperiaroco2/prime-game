extends GdUnitTestSuite
## PhotoPictures (#787, photo P8; the photo ADR §3.3, PE15): a shot the own ClientModel folded
## renders once from its record, one render a frame, in a SubViewport whose camera stands at the
## camera's frame and sees only PhotoLayers.PHOTO_VIEW, with a puppet per record row (on PHOTO, no
## collision, no shadow). The picture is read after the draw (a test signal and reader stand in for
## RenderingServer.frame_post_draw and the GPU read-back), kept as JPEG bytes, then the flash is
## released. A shot the model no longer holds drops its picture and any render of it.

signal drawn_now

const C := preload("res://tests/fixtures/client/fixture_photo_client.gd")
const RigFixture := preload("res://tests/integration/client/player/character_fixture.gd")
const FILM := 20
const OTHER_FILM := 21

var _model: ClientModel
var _mode: GameMode
var _flashes: LoggingFlashes
var _pictures: PhotoPictures
var _calls: Array[String] = []
var _colour := Color.RED
var _empty := false


## The flashes, noting each release beside the reads.
class LoggingFlashes:
	extends PhotoFlashes
	var calls: Array[String]

	func release(shot: int) -> void:
		calls.append("release %d" % shot)
		super.release(shot)


func before_test() -> void:
	_calls.clear()
	_colour = Color.RED
	_empty = false
	_model = C.dealt()
	_mode = FixturePhotoModes.basic()
	_flashes = auto_free(LoggingFlashes.new())
	_flashes.calls = _calls
	_flashes.model = _model
	_flashes.lens_m = _mode.player_rules.eye_height_m
	add_child(_flashes)
	_pictures = auto_free(PhotoPictures.new())
	_pictures.model = _model
	_pictures.mode = _mode
	_pictures.flashes = _flashes
	_pictures.enabled = true
	_pictures.drawn = drawn_now
	_pictures.reader = _read
	add_child(_pictures)
	C.load_film(_model, FILM)


func test_a_shot_renders_once_at_the_camera_frame_seeing_no_live_avatar() -> void:
	_shoot(0, [C.row(C.OTHER, FixturePhotoModes.SPOT_AT)])
	assert_object(_pictures.rendering()).is_null()
	await _frames(1)
	var viewport := _pictures.rendering()
	assert_object(viewport).is_not_null()
	assert_int(viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_ONCE)
	var type := FixturePhotoModes.type_of(_mode)
	assert_that(viewport.size).is_equal(
		Vector2i(roundi(PhotoPictures.HEIGHT_PX * type.aspect), PhotoPictures.HEIGHT_PX)
	)
	assert_bool(viewport.own_world_3d).is_false()
	var camera := viewport.get_camera_3d()
	assert_object(camera).is_not_null()
	var frame := PhotoUse.frame_of(_model, _mode, C.CAMERA)
	assert_bool(camera.global_position.is_equal_approx(frame.lens)).is_true()
	assert_bool(camera.global_basis.is_equal_approx(frame.basis)).is_true()
	assert_float(camera.fov).is_equal(type.fov_deg)
	assert_int(camera.keep_aspect).is_equal(Camera3D.KEEP_HEIGHT)
	assert_int(camera.cull_mask).is_equal(PhotoLayers.PHOTO_VIEW)
	assert_int(camera.cull_mask & PhotoLayers.LIVE_AVATAR).is_equal(0)
	assert_int(camera.cull_mask & PhotoLayers.PHOTO).is_not_equal(0)


func test_each_record_row_stands_a_shadowless_puppet_out_of_the_live_physics() -> void:
	var spot := FixturePhotoModes.SPOT_AT
	_shoot(0, [C.row(C.OWN, spot + Vector3(1, 0, 0)), C.row(C.OTHER, spot + Vector3(-1, 0, 0))])
	await _frames(1)
	var puppets := _pictures.puppets()
	assert_int(puppets.size()).is_equal(2)
	assert_bool(puppets[0].global_position.is_equal_approx(spot + Vector3(1, 0, 0))).is_true()
	assert_bool(puppets[1].global_position.is_equal_approx(spot + Vector3(-1, 0, 0))).is_true()
	for puppet: RemotePlayerBody in puppets:
		assert_int(puppet.collision_layer).is_equal(0)
		assert_int(puppet.collision_mask).is_equal(0)
		assert_int(PhotoLayers.layers_of(puppet)).is_equal(PhotoLayers.PHOTO)
		for node: Node in puppet.find_children("*", "GeometryInstance3D", true, false):
			assert_int((node as GeometryInstance3D).cast_shadow).is_equal(
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)


func test_the_held_item_goes_into_the_picture_with_its_puppet() -> void:
	C.hold(_model, 40, &"film", C.OTHER)
	_shoot(0, [C.row(C.OTHER, FixturePhotoModes.SPOT_AT, Vector3.FORWARD, false, 40)])
	await _frames(1)
	var puppet := _pictures.puppets()[0]
	var views := puppet.find_children("*", "ItemView", true, false)
	assert_int(views.size()).is_equal(1)
	assert_int(PhotoLayers.layers_of(views[0])).is_equal(PhotoLayers.PHOTO)


## A belt item in the higher place alone (the row's belt places are not compacted) is drawn at the
## first belt socket, as the live view draws it (#1218).
func test_the_belt_is_drawn_as_the_live_view_draws_it() -> void:
	C.hold(_model, 41, &"film", C.OTHER)
	C.hold(_model, 42, &"film", C.OTHER)
	var lone := C.row(C.OTHER, FixturePhotoModes.SPOT_AT, Vector3.FORWARD)
	lone["belt_item2"] = 41
	_shoot(0, [lone])
	await _frames(1)
	var views := _pictures.puppets()[0].find_children("*", "ItemView", true, false)
	assert_int(views.size()).is_equal(1)
	assert_vector((views[0] as Node3D).position).is_equal(Vector3.ZERO)


func test_two_belt_items_take_both_belt_sockets() -> void:
	C.hold(_model, 41, &"film", C.OTHER)
	C.hold(_model, 42, &"film", C.OTHER)
	var both := C.row(C.OTHER, FixturePhotoModes.SPOT_AT, Vector3.FORWARD)
	both["belt_item"] = 41
	both["belt_item2"] = 42
	_shoot(0, [both])
	await _frames(1)
	var views := _pictures.puppets()[0].find_children("*", "ItemView", true, false)
	assert_int(views.size()).is_equal(2)
	var offsets: Array[Vector3] = []
	for view: Node3D in views:
		offsets.append(view.position)
	assert_array(offsets).contains_exactly_in_any_order(
		[Vector3.ZERO, ItemViews.SECOND_BELT_OFFSET]
	)


## With the avatars' character (the game's case) the puppet is drawn in its clip at once, its hand
## item at the posed hand: the render is set up and drawn in one frame, before any physics step
## would run the rig's tree, so `_process` is called by hand here with no physics step after it.
func test_a_puppet_with_the_character_is_posed_before_its_draw() -> void:
	var scene := RigFixture.scene(AvatarClips.all_clips(), RigFixture.BONES, true)
	var avatars: AvatarViews = auto_free(AvatarViews.new())
	avatars.character = CharacterSet.from_scene(scene, RigFixture.ragdoll())
	_pictures.avatars = avatars
	C.hold(_model, 40, &"film", C.OTHER)
	_shoot(0, [C.row(C.OTHER, FixturePhotoModes.SPOT_AT, Vector3.FORWARD, false, 40)])
	_pictures._process(0.0)
	var rig := _pictures.puppets()[0].character()
	assert_object(rig).is_not_null()
	var wrist := rig.skeleton.find_bone(&"Wrist.R")
	var rest := rig.skeleton.get_bone_global_rest(wrist).origin
	assert_float(rest.distance_to(rig.skeleton.get_bone_global_pose(wrist).origin)).is_greater(0.3)
	var view := rig.socket(&"Hand").find_children("*", "ItemView", true, false)[0] as Node3D
	var hand := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(wrist)
	assert_float(view.global_position.distance_to(hand.origin)).is_less(0.2)


## §3.3: the render never touches a live view's `visible` (SightHider alone sets it; a view shown
## for the render frame would draw through a wall), neither a hidden one nor a shown one.
func test_the_render_never_sets_a_live_views_visible() -> void:
	var changes: Array[String] = []
	var views: Array[MeshInstance3D] = []
	for shown: bool in [false, true]:
		var view: MeshInstance3D = auto_free(MeshInstance3D.new())
		view.mesh = BoxMesh.new()
		view.visible = shown
		view.add_to_group(SightHider.GROUP)
		add_child(view)
		view.visibility_changed.connect(func() -> void: changes.append(view.name))
		views.append(view)
	_shoot(0, [C.row(C.OTHER, FixturePhotoModes.SPOT_AT)])
	await _frames(1)
	assert_object(_pictures.rendering()).is_not_null()
	drawn_now.emit()
	await _frames(1)
	assert_bool(_pictures.has_picture(0)).is_true()
	assert_array(changes).is_empty()
	assert_bool(views[0].visible).is_false()
	assert_bool(views[1].visible).is_true()


func test_the_picture_is_read_with_the_flash_on_then_the_flash_is_released() -> void:
	_shoot(0, [C.row(C.OTHER, FixturePhotoModes.SPOT_AT)])
	await _frames(1)
	var puppet := _pictures.puppets()[0]
	assert_array(_calls).is_empty()
	drawn_now.emit()
	assert_array(_calls).is_equal(["read lit", "release 0"])
	assert_object(_pictures.rendering()).is_null()
	assert_bool(_pictures.has_picture(0)).is_true()
	assert_int(_pictures.bytes_kept()).is_greater(0)
	assert_int(_pictures.pending()).is_equal(0)
	await _frames(1)
	assert_bool(is_instance_valid(puppet)).is_false()
	assert_int(_pictures.get_child_count()).is_equal(0)


func test_three_shots_render_one_a_frame_in_order() -> void:
	C.fold(_model, FilmLoadedEvent.new(C.CAMERA, FILM))
	_shoot(0)
	_shoot(1)
	_shoot(2)
	assert_int(_pictures.pending()).is_equal(3)
	for shot in 3:
		await _frames(1)
		assert_str(_pictures.rendering().name).is_equal("Picture%d" % shot)
		drawn_now.emit()
	assert_array(_calls).is_equal(
		["read lit", "release 0", "read lit", "release 1", "read lit", "release 2"]
	)
	assert_int(_pictures.count()).is_equal(3)


func test_the_texture_decodes_when_asked_and_is_freed_when_nobody_asks() -> void:
	await _rendered(0)
	assert_bool(_pictures.has_texture(0)).is_false()
	var texture := _pictures.texture_of(0)
	assert_object(texture).is_not_null()
	assert_that(texture.get_size()).is_equal(Vector2(576, 384))
	assert_bool(_pictures.has_texture(0)).is_true()
	var bytes := _pictures.bytes_kept()
	await _frames(PhotoPictures.TEXTURE_FRAMES + 2)
	assert_bool(_pictures.has_texture(0)).is_false()
	assert_int(_pictures.bytes_kept()).is_equal(bytes)
	assert_object(_pictures.texture_of(0)).is_not_null()


func test_a_film_gone_unprinted_drops_its_picture() -> void:
	await _rendered(0)
	C.fold(_model, ItemVanishedEvent.new(FILM))
	await _frames(1)
	assert_bool(_pictures.has_picture(0)).is_false()
	assert_object(_pictures.texture_of(0)).is_null()


func test_a_printed_photo_keeps_the_picture_its_film_gave() -> void:
	await _rendered(0)
	C.printed(_model, FILM, 50, 0)
	await _frames(1)
	assert_bool(_pictures.has_picture(0)).is_true()
	assert_object(_pictures.texture_of(0)).is_not_null()


func test_a_render_whose_shot_went_is_discarded_and_its_flash_released() -> void:
	_shoot(0, [C.row(C.OTHER, FixturePhotoModes.SPOT_AT)])
	await _frames(1)
	assert_object(_pictures.rendering()).is_not_null()
	C.fold(_model, ItemVanishedEvent.new(FILM))
	await _frames(1)
	assert_object(_pictures.rendering()).is_null()
	assert_array(_calls).is_equal(["release 0"])
	drawn_now.emit()
	assert_array(_calls).is_equal(["release 0"])
	assert_bool(_pictures.has_picture(0)).is_false()


func test_a_queued_render_whose_shot_went_is_dropped_and_its_flash_released() -> void:
	_shoot(0)
	_shoot(1)
	await _frames(1)
	C.fold(_model, ItemVanishedEvent.new(FILM))
	await _frames(1)
	assert_int(_pictures.pending()).is_equal(0)
	assert_array(_calls).contains_exactly_in_any_order(["release 0", "release 1"])


func test_a_recycled_shot_id_is_a_new_picture() -> void:
	await _rendered(0)
	C.fold(_model, ItemVanishedEvent.new(FILM))
	C.load_film(_model, OTHER_FILM)
	_colour = Color.BLUE
	_shoot(0, [], OTHER_FILM)
	await _frames(1)
	assert_bool(_pictures.has_picture(0)).is_false()
	drawn_now.emit()
	var pixel := _pictures.texture_of(0).get_image().get_pixel(10, 10)
	assert_float(pixel.b).is_greater(0.8)
	assert_float(pixel.r).is_less(0.2)


func test_nothing_renders_when_disabled() -> void:
	_pictures.enabled = false
	_shoot(0)
	await _frames(2)
	assert_object(_pictures.rendering()).is_null()
	assert_int(_pictures.pending()).is_equal(0)
	assert_int(_pictures.get_child_count()).is_equal(0)


func test_a_headless_client_renders_nothing_by_default() -> void:
	assert_str(DisplayServer.get_name()).is_equal("headless")
	var pictures: PhotoPictures = auto_free(PhotoPictures.new())
	assert_bool(pictures.enabled).is_false()
	var world: ItemWorld = auto_free(ItemWorld.new())
	assert_bool(world.pictures.enabled).is_false()


func test_an_empty_read_keeps_nothing_and_still_releases_the_flash() -> void:
	_empty = true
	_shoot(0)
	await _frames(1)
	drawn_now.emit()
	assert_bool(_pictures.has_picture(0)).is_false()
	assert_array(_calls).is_equal(["read lit", "release 0"])
	assert_object(_pictures.rendering()).is_null()


func test_clear_frees_the_render_and_releases_every_flash() -> void:
	_shoot(0)
	_shoot(1)
	await _frames(1)
	_pictures.clear()
	assert_object(_pictures.rendering()).is_null()
	assert_int(_pictures.pending()).is_equal(0)
	assert_array(_calls).contains_exactly_in_any_order(["release 0", "release 1"])
	drawn_now.emit()
	assert_int(_pictures.count()).is_equal(0)


func test_a_zero_or_vertical_facing_still_stands_a_finite_puppet() -> void:
	var spot := FixturePhotoModes.SPOT_AT
	_shoot(0, [C.row(C.OWN, spot, Vector3.ZERO), C.row(C.OTHER, spot, Vector3.UP * 1.01)])
	await _frames(1)
	for puppet: RemotePlayerBody in _pictures.puppets():
		assert_bool(puppet.global_transform.basis.is_finite()).is_true()
		assert_bool(puppet.head().global_transform.basis.is_finite()).is_true()
		assert_float(absf(puppet.head().rotation.x)).is_less_equal(SnapshotBuffer.MAX_PITCH + 1e-5)


func test_a_downed_row_lies_flat() -> void:
	var spot := FixturePhotoModes.SPOT_AT
	_shoot(0, [C.row(C.OTHER, spot, Vector3.FORWARD, true)])
	await _frames(1)
	var puppet := _pictures.puppets()[0]
	# Its up axis lies along the floor; its middle a capsule radius above it.
	assert_float(absf(puppet.global_basis.y.normalized().dot(Vector3.UP))).is_less(0.01)
	assert_float(puppet.global_position.y).is_equal_approx(
		_mode.player_rules.capsule_radius_m, 0.001
	)


func _read(viewport: SubViewport) -> Image:
	_calls.append("read lit" if _flashes.light_of(_shot_of(viewport)) != null else "read dark")
	if _empty:
		return Image.new()
	var image := Image.create_empty(viewport.size.x, viewport.size.y, false, Image.FORMAT_RGB8)
	image.fill(_colour)
	return image


func _shot_of(viewport: SubViewport) -> int:
	return String(viewport.name).trim_prefix("Picture").to_int()


## Shot `shot` on `film` with `record`, folded and forwarded as ItemWorld does.
func _shoot(shot: int, record: Array[Dictionary] = [], film := FILM) -> void:
	var event := ShotTakenEvent.new(C.CAMERA, film, shot, record)
	C.fold(_model, event)
	_flashes.on_event(event.event_name(), event.to_dict())
	_pictures.on_event(event.event_name(), event.to_dict())


func _rendered(shot: int) -> void:
	_shoot(shot)
	await _frames(1)
	drawn_now.emit()
	assert_bool(_pictures.has_picture(shot)).is_true()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
