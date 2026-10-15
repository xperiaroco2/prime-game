extends GdUnitTestSuite
## PhotoViews (#787, photo P8; ARCHITECTURE §4.7): the real camera, printer and board scenes of
## `levels/stations/` under a level, bound to a dealt photo task's stations (FixturePhotoClient),
## with ItemViews drawing the items at PhotoViews.drawn_point. The camera's FramesLeft label, the
## loaded film in its FilmSlot (still no item target, #1104 option (a)), the hung photos on the
## board's slots in hang order (the lowest free slot refilled), the tray's photos spread apart,
## all depth-tested and hidden behind a wall by SightHider.

const SCENES := "res://levels/stations/%s.tscn"
const C := preload("res://tests/fixtures/client/fixture_photo_client.gd")
const FILM := 20
const FIRST_PHOTO := 50

var _level: Node3D
var _views: PhotoViews
var _items: ItemViews
var _model: ClientModel
var _mode: GameMode
var _camera: Node3D
var _board: Node3D
var _printer: Node3D


func before_test() -> void:
	_model = C.dealt()
	_mode = FixturePhotoModes.basic()
	var type := FixturePhotoModes.type_of(_mode)
	_level = auto_free(Node3D.new())
	add_child(_level)
	_camera = _add(&"camera", FixturePhotoModes.CAMERA_AT)
	_printer = _add(&"printer", FixturePhotoModes.PRINTER_AT)
	_board = _add(&"photo_board", FixturePhotoModes.BOARD_AT)
	# The fixture's board kind is tagged `board`: the views find a scene by its kind's tag, never by
	# the base mode's literal one.
	_board.get_node("UseSpot").add_to_group(StringName("spawn_" + type.board.spawn_tag))
	_views = auto_free(PhotoViews.new())
	_views.model = _model
	_views.mode = _mode
	add_child(_views)
	_views.level = _level
	_items = auto_free(ItemViews.new())
	_items.model = _model
	_items.mode = _mode
	_items.station_point = _views.drawn_point
	add_child(_items)
	await _frames()


func test_the_counter_shows_the_frames_left_only_while_a_film_is_loaded() -> void:
	var label := _views.frames_label(C.CAMERA)
	assert_object(label).is_not_null()
	assert_bool(label.visible).is_false()
	C.load_film(_model, FILM)
	await _frames()
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal(str(FixturePhotoModes.FRAMES))
	assert_int(label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_bool(label.no_depth_test).is_false()
	C.shoot(_model, FILM, 0)
	await _frames()
	assert_str(label.text).is_equal(str(FixturePhotoModes.FRAMES - 1))
	C.fold(_model, ItemPickedUpEvent.new(C.OWN, FILM))
	await _frames()
	assert_bool(label.visible).is_false()


func test_the_loaded_film_is_drawn_in_the_film_slot_and_is_no_item_target() -> void:
	C.load_film(_model, FILM)
	await _frames()
	var slot := _camera.get_node("FilmSlot") as Node3D
	var view := _items.view_of(FILM)
	assert_bool(view.look().visible).is_true()
	assert_vector(view.global_position).is_equal_approx(slot.global_position, Vector3.ONE * 0.001)
	assert_that(TargetChoice.aim_at(_model, FILM, _views.aim_point)).is_null()
	var eye := slot.global_position + Vector3.BACK
	var picked := TargetChoice.along_ray(
		_model, eye, Vector3.FORWARD, TargetChoice.RAY_M, _views.aim_point
	)
	assert_int(picked).is_equal(-1)


func test_hung_photos_take_the_slots_in_hang_order_and_refill_the_lowest_free_slot() -> void:
	_hang(FIRST_PHOTO, true)
	_hang(FIRST_PHOTO + 1, false)
	_hang(FIRST_PHOTO + 2, false)
	await _frames()
	for i in 3:
		_assert_on_slot(FIRST_PHOTO + i, i + 1)
	# The uncounted second one is taken down: its slot frees and the next hang takes it.
	C.fold(_model, ItemPickedUpEvent.new(C.OWN, FIRST_PHOTO + 1))
	await _frames()
	_hang(FIRST_PHOTO + 3, false)
	await _frames()
	_assert_on_slot(FIRST_PHOTO + 3, 2)
	_assert_on_slot(FIRST_PHOTO + 2, 3)


func test_a_photo_past_the_last_slot_stacks_in_front_of_it() -> void:
	var count := _board.get_node("Slots").get_child_count()
	for i in count + 1:
		_hang(FIRST_PHOTO + i, true)
	await _frames()
	var last := _board.get_node("Slots").get_child(count - 1) as Node3D
	var out := _board.global_basis.z * PhotoViews.STACK_OUT_M
	var view := _items.view_of(FIRST_PHOTO + count)
	assert_vector(view.global_position).is_equal_approx(
		last.global_position + out, Vector3.ONE * 0.001
	)


func test_a_taken_down_photo_is_aimed_at_on_its_slot_and_a_counted_one_is_not() -> void:
	_hang(FIRST_PHOTO, true)
	_hang(FIRST_PHOTO + 1, false)
	await _frames()
	for i in 2:
		var slot := _board.get_node("Slots/Slot%d" % (i + 1)) as Node3D
		var eye := slot.global_position + _board.global_basis.z * 1.0
		var look := -_board.global_basis.z
		var picked := TargetChoice.along_ray(
			_model, eye, look, TargetChoice.RAY_M, _views.aim_point
		)
		assert_int(picked).is_equal(-1 if i == 0 else FIRST_PHOTO + 1)


func test_photos_on_the_tray_are_spread_apart_and_aimed_at_where_they_are_drawn() -> void:
	var tray := _printer.get_node("Tray") as Node3D
	for i in 6:
		C.printed(_model, FILM, FIRST_PHOTO + i, i, false, tray.global_position)
	await _frames()
	var seen: Array[Vector3] = []
	for i in 6:
		var view := _items.view_of(FIRST_PHOTO + i)
		var at := view.global_position
		for other: Vector3 in seen:
			var off := at - other
			assert_float(Vector2(off.x, off.z).length()).is_greater(0.09)
		seen.append(at)
		assert_float(at.distance_to(tray.global_position)).is_less(0.25)
		var aim: Variant = TargetChoice.aim_at(_model, FIRST_PHOTO + i, _views.aim_point)
		assert_vector(aim as Vector3).is_equal_approx(
			ItemView.centre_of(&"photo", at), Vector3.ONE * 0.001
		)


func test_a_downed_eye_behind_a_wall_sees_neither_the_counter_nor_the_film_nor_a_photo() -> void:
	C.load_film(_model, FILM)
	_hang(FIRST_PHOTO, true)
	await _frames()
	var label := _views.frames_label(C.CAMERA)
	var wrapper := label.get_parent() as Node3D
	assert_str(String(wrapper.name)).is_equal(StationViews.WRAPPER)
	var views: Array[Node3D] = [wrapper, _items.view_of(FILM), _items.view_of(FIRST_PHOTO)]
	for view: Node3D in views:
		assert_bool(view.is_in_group(SightHider.GROUP)).is_true()
	var hider := auto_free(SightHider.new()) as SightHider
	add_child(hider)
	var targets: Array[Node3D] = [_camera, _board]
	for target: Node3D in targets:
		_wall(target.global_position + target.global_basis.z * 1.8 + Vector3.UP * 1.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in targets.size():
		var target := targets[i]
		var drawn: Array[Node3D] = [wrapper, _items.view_of(FILM)]
		if i == 1:
			drawn = [_items.view_of(FIRST_PHOTO)]
		hider.watch_from(target.global_position + target.global_basis.z * 3.0 + Vector3.UP)
		hider.hide_unseen()
		for view: Node3D in drawn:
			assert_bool(view.visible).override_failure_message(str(view.get_path())).is_false()
		hider.watch_from(target.global_position + target.global_basis.z * 1.2 + Vector3.UP)
		hider.hide_unseen()
		for view: Node3D in drawn:
			assert_bool(view.visible).override_failure_message(str(view.get_path())).is_true()


func test_nothing_the_views_draw_skips_the_depth_test() -> void:
	C.load_film(_model, FILM)
	_hang(FIRST_PHOTO, false)
	await _frames()
	var roots: Array[Node] = [_camera, _board, _items]
	var drawn := 0
	for root: Node in roots:
		for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
			drawn += 1
			var path := str(node.get_path())
			var label := node as Label3D
			if label != null:
				assert_bool(label.no_depth_test).override_failure_message(path).is_false()
			var geometry := node as GeometryInstance3D
			var materials: Array[Material] = [geometry.material_override]
			var mesh := node as MeshInstance3D
			if mesh != null and mesh.mesh != null:
				for s in mesh.mesh.get_surface_count():
					materials.append(mesh.get_active_material(s))
			for material: Material in materials:
				var base := material as BaseMaterial3D
				if base != null:
					assert_bool(base.no_depth_test).override_failure_message(path).is_false()
					assert_int(base.render_priority).override_failure_message(path).is_equal(0)
	assert_int(drawn).is_greater(2)


func _assert_on_slot(photo: int, slot_number: int) -> void:
	var slot := _board.get_node("Slots/Slot%d" % slot_number) as Node3D
	var view := _items.view_of(photo)
	var where := "photo %d on Slot%d" % [photo, slot_number]
	assert_vector(view.global_position).override_failure_message(where).is_equal_approx(
		slot.global_position, Vector3.ONE * 0.001
	)
	# Upright, the picture (the card's top face) facing out of the board.
	assert_vector(view.global_basis.y).is_equal_approx(_board.global_basis.z, Vector3.ONE * 0.001)


func _hang(photo: int, counted: bool) -> void:
	C.hold(_model, photo, &"photo")
	C.hang(_model, photo, counted)


func _add(scene: StringName, spot_at: Vector3) -> Node3D:
	var root := (load(SCENES % scene) as PackedScene).instantiate() as Node3D
	root.position = spot_at - (root.get_node("UseSpot") as Node3D).position
	_level.add_child(root)
	return root


func _wall(center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 3, 0.1)
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_level.add_child(body)


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
