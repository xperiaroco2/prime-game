extends GdUnitTestSuite
## Cooking's station scenes driven from the own ClientModel (ARCHITECTURE §4.7.55, #776; the cooking
## ADR's §3, CD12 (a), CD14 (i), CE15): the level's real scenes (`levels/stations/`) under a fixture
## level, the stations of FixtureCookingModes placed at their use spots. Five beds under one
## `herb_beds.tscn` bind to five distinct `Plant`s; the order board shows a row per place with an
## order, numbered as its plate; the herb board shows the dealt code; each bed its herb; the plate's
## ingredients are stacked on the plate by slot with one filled-slot outline (#1101); the grill's
## ring fills from GrillLoaded's ticks. Every driven part sits under a wrapper in SightHider's group
## and nothing is drawn over the level.

const SCENES := "res://levels/stations/%s.tscn"
const OWN := FixtureCookingClient.OWN
const ORDER_BOARD := FixtureCookingClient.ORDER_BOARD
const HERB_BOARD := FixtureCookingClient.HERB_BOARD
const GRILL := FixtureCookingClient.GRILL
const FIRST_PLACE := FixtureCookingClient.FIRST_PLACE
const FIRST_BED := 40
const BEDS_AT := Vector3(20, 0, 40)

var _level: Node3D
var _views: CookingViews
var _model: ClientModel
var _mode: GameMode
var _now := 0
var _beds: Node3D


func before_test() -> void:
	_mode = FixtureCookingModes.basic(2)
	_model = ClientModel.new(_mode)
	_model.own_peer = OWN
	FixtureCookingClient.fold(_model, PhaseChangedEvent.new(&"round", 1000))
	_level = auto_free(Node3D.new())
	add_child(_level)
	_add(&"order_board", FixtureCookingModes.ORDER_BOARD_AT)
	_add(&"herb_board", FixtureCookingModes.HERB_BOARD_AT)
	_add(&"grill", FixtureCookingModes.GRILL_AT)
	for at: Vector3 in FixtureCookingModes.PLACE_SPOTS:
		_add(&"place", at)
	_beds = (load(SCENES % "herb_beds") as PackedScene).instantiate() as Node3D
	_beds.position = BEDS_AT
	_level.add_child(_beds)
	_place(ORDER_BOARD, &"order_board", FixtureCookingModes.ORDER_BOARD_AT)
	_place(HERB_BOARD, &"herb_board", FixtureCookingModes.HERB_BOARD_AT)
	_place(GRILL, &"grill", FixtureCookingModes.GRILL_AT)
	for k in 5:
		var spot := _beds.get_node("Bed%d/UseSpot" % (k + 1)) as Node3D
		_place(FIRST_BED + k, &"herb_bed", spot.global_position)
	for i in 2:
		_place(FIRST_PLACE + i, &"place", FixtureCookingModes.PLACE_SPOTS[i])
		FixtureCookingClient.fold(
			_model, OrderPostedEvent.new(FIRST_PLACE + i, &"bun_a", &"fried_a", i + 1)
		)
	var herbs := PackedStringArray(["herb_a", "herb_b", "herb_c"])
	var beds := PackedStringArray(["herb_c", "herb_a", "herb_b"])
	FixtureCookingClient.fold(_model, HerbsDealtEvent.new(herbs, beds))
	_views = auto_free(CookingViews.new())
	_views.model = _model
	_views.mode = _mode
	_views.host_tick = func() -> int: return _now
	add_child(_views)
	_views.level = _level
	await _frames()


func test_five_bed_stations_under_one_herb_beds_scene_bind_to_five_distinct_plants() -> void:
	var plants: Array[Node] = []
	for k in 5:
		var bed := _views.scene_of(FIRST_BED + k)
		assert_object(bed).is_same(_beds.get_node("Bed%d" % (k + 1)))
		var plant := bed.find_child("Plant", true, false)
		assert_object(plant).is_not_null()
		assert_bool(plants.has(plant)).is_false()
		plants.append(plant)


func test_the_order_board_shows_a_numbered_row_per_place_with_an_order() -> void:
	var board := _views.scene_of(ORDER_BOARD)
	for n in 3:
		var row := board.find_child("Row%d" % (n + 1), true, false) as Node3D
		assert_bool(row.visible).override_failure_message("Row%d" % (n + 1)).is_equal(n < 2)
	var row1 := board.find_child("Row1", true, false)
	assert_str((row1.get_node("Number") as Label3D).text).is_equal("1")
	var icon := row1.get_node("Herb/Picture") as Sprite3D
	assert_object(icon.texture).is_same(CookingLooks.icon(1))
	assert_bool(icon.no_depth_test).is_false()
	# A fixture kind has no look: its name as a label, drawn in the world.
	var bun := row1.get_node("Bun/Picture") as Label3D
	assert_str(bun.text).is_not_empty()
	assert_bool(bun.no_depth_test).is_false()
	assert_object(row1.get_node_or_null("Patty/Picture")).is_not_null()


func test_a_place_with_an_order_shows_its_plate_numbered_as_its_row() -> void:
	for i in 2:
		var place := _views.scene_of(FIRST_PLACE + i)
		assert_bool((place.find_child("Plate", true, false) as Node3D).visible).is_true()
		var number := place.find_child("Number", true, false) as Label3D
		assert_bool(number.visible).is_true()
		assert_str(number.text).is_equal(str(i + 1))
	var bare := _level.get_child(5) as Node3D
	assert_int(_views.scene_roots().count(bare)).is_equal(1)
	assert_bool((bare.find_child("Plate", true, false) as Node3D).visible).is_false()
	assert_bool((bare.find_child("Number", true, false) as Node3D).visible).is_false()


func test_the_herb_board_shows_the_code_and_each_bed_its_herb() -> void:
	var pairs := _views.scene_of(HERB_BOARD).find_child("Pairs", true, false)
	for n in 5:
		var pair := pairs.get_child(n) as Node3D
		assert_bool(pair.visible).is_equal(n < 3)
	var icon := pairs.get_child(2).get_node("Icon/Picture") as Sprite3D
	assert_object(icon.texture).is_same(CookingLooks.icon(2))
	var names: Array[String] = []
	for k in 3:
		var plant := _views.scene_of(FIRST_BED + k).find_child("Plant", true, false)
		names.append((plant.get_node("Picture") as Label3D).text)
	assert_str(names[0]).is_equal(_name(&"herb_c"))
	assert_str(names[1]).is_equal(_name(&"herb_a"))
	var fifth := _views.scene_of(FIRST_BED + 4).find_child("Plant", true, false)
	assert_object(fifth.get_node_or_null("Picture")).is_null()


func test_the_driven_parts_sit_under_a_wrapper_in_the_sight_group() -> void:
	for id: int in [ORDER_BOARD, HERB_BOARD, GRILL, FIRST_PLACE, FIRST_BED]:
		var root := _views.scene_of(id)
		var sight := root.get_node("StationSight") as Node3D
		assert_bool(sight.is_in_group(SightHider.GROUP)).is_true()
		assert_bool(sight.has_method(&"sight_point")).is_true()
		assert_int(sight.get_child_count()).is_greater(0)


func test_the_plates_ingredients_are_drawn_on_the_plate_with_their_outline() -> void:
	var items := auto_free(ItemViews.new()) as ItemViews
	items.model = _model
	items.mode = _mode
	items.station_point = _views.point_of
	add_child(items)
	FixtureCookingClient.hold(_model, 1, &"bun_a")
	FixtureCookingClient.put(_model, 1, 0)
	FixtureCookingClient.hold(_model, 2, &"herb_b")
	FixtureCookingClient.put(_model, 2, 0)
	await _frames()
	var plate := _views.scene_of(FIRST_PLACE).find_child("Plate", true, false) as Node3D
	var plate_xz := Vector2(plate.global_position.x, plate.global_position.z)
	# Every put stacks on its slot over the plate (#1101: nothing lies beside it as wrong).
	var bun: Vector3 = _views.point_of(1)
	var herb: Vector3 = _views.point_of(2)
	for at: Vector3 in [bun, herb]:
		assert_float(Vector2(at.x, at.z).distance_to(plate_xz)).is_less(0.01)
	assert_float(bun.y).is_greater_equal(plate.global_position.y)
	assert_float(herb.y).is_greater(bun.y)
	var bun_view := items.view_of(1)
	assert_bool(bun_view.global_position.is_equal_approx(bun)).is_true()
	assert_bool(bun_view.is_look_shown()).is_true()
	assert_bool(bun_view.is_in_group(SightHider.GROUP)).is_true()
	# One filled-slot outline for both, though herb_b is not the order's herb (#1101).
	var box := bun_view.look().find_children("*", "GeometryInstance3D", true, false)[0]
	assert_object((box as GeometryInstance3D).material_overlay).is_same(CookingLooks.outline())
	var leaf := items.view_of(2).look().find_children("*", "GeometryInstance3D", true, false)[0]
	assert_object((leaf as GeometryInstance3D).material_overlay).is_same(CookingLooks.outline())
	# Off the plate (the client folds any pickup), the herb loses its outline.
	FixtureCookingClient.fold(_model, ItemPickedUpEvent.new(OWN, 2))
	await _frames()
	assert_object(_views.point_of(2)).is_null()
	assert_object((leaf as GeometryInstance3D).material_overlay).is_null()


func test_the_grills_ring_fills_to_fried_and_then_to_burnt() -> void:
	var type := FixtureCookingModes.type_of(_mode)
	var ring := _views.scene_of(GRILL).find_child("Ring", true, false) as Node3D
	assert_bool(ring.visible).is_false()
	var fried := 100 + type.fried_ticks()
	FixtureCookingClient.hold(_model, 3, &"raw_a")
	FixtureCookingClient.grill(_model, 3, fried, 100 + type.burnt_ticks())
	_now = 100 + roundi(type.fried_ticks() / 2.0)
	await _frames()
	assert_bool(ring.visible).is_true()
	var lit := 0
	for segment: Node in ring.get_node("Segments").get_children():
		lit += 1 if (segment as Node3D).visible else 0
	var half := roundi(CookingViews.RING_SEGMENTS / 2.0)
	assert_int(lit).is_between(half - 1, half + 1)
	var grill := _model.stations[GRILL]
	assert_int(CookingViews.ring_phase(grill, _now)).is_equal(CookingViews.Ring.FRYING)
	assert_int(CookingViews.ring_phase(grill, fried)).is_equal(CookingViews.Ring.BURNING)
	assert_float(CookingViews.ring_fill(type, grill, fried)).is_equal(0.0)
	assert_int(CookingViews.ring_phase(grill, grill.burnt_tick)).is_equal(CookingViews.Ring.BURNT)
	assert_float(CookingViews.ring_fill(type, grill, grill.burnt_tick)).is_equal(1.0)
	var patty: Vector3 = _views.point_of(3)
	var grate := _views.scene_of(GRILL).get_node("Grate") as Node3D
	assert_float(patty.distance_to(grate.global_position)).is_less(0.05)
	# Taken off: the ring goes out.
	FixtureCookingClient.fold(_model, ItemPickedUpEvent.new(OWN, 3))
	await _frames()
	assert_bool(ring.visible).is_false()


func test_a_ray_names_a_bed_by_its_shape_and_the_grill_by_its_collision() -> void:
	var collider := _beds.get_node("Collision") as CollisionObject3D
	for k in 5:
		var shape := (collider.get_node("Shape%d" % (k + 1)) as CollisionShape3D).get_index()
		assert_int(_views.station_of_hit(collider, shape)).is_equal(FIRST_BED + k)
	var grill := _views.scene_of(GRILL).get_node("Collision")
	assert_int(_views.station_of_hit(grill, 0)).is_equal(GRILL)
	assert_int(_views.station_of_hit(_level, 0)).is_equal(-1)


func test_a_downed_eye_behind_a_kitchen_wall_sees_no_driven_part_nor_what_lies_on_them() -> void:
	var items := _loaded_items()
	await _frames()
	var views: Array[Node3D] = [items.view_of(1), items.view_of(2), items.view_of(3)]
	for root: Node3D in _views.scene_roots():
		views.append(root.get_node(StationViews.WRAPPER) as Node3D)
	for view: Node3D in views:
		assert_bool(view.is_in_group(SightHider.GROUP)).is_true()
	# A wall 3 m high in front of each row of stations: the boards and the grill, the places, the
	# beds. A downed eye's raised camera stands 1 m up behind it, then on the open side.
	var rows: Array[float] = [
		FixtureCookingModes.GRILL_AT.z, FixtureCookingModes.PLACE_SPOTS[0].z, _bed_spot_z()
	]
	for z: float in rows:
		_wall(Vector3(FixtureCookingModes.GRILL_AT.x, 1.5, z + 1.6), Vector3(60, 3, 0.1))
	var hider := auto_free(SightHider.new()) as SightHider
	add_child(hider)
	await get_tree().physics_frame
	for z: float in rows:
		var behind := _views_in_row(views, z)
		assert_int(behind.size()).is_greater(0)
		hider.watch_from(Vector3(_row_x(behind), 1.0, z + 3.0))
		hider.hide_unseen()
		for view: Node3D in behind:
			assert_bool(view.visible).override_failure_message(str(view.get_path())).is_false()
		hider.watch_from(Vector3(_row_x(behind), 1.0, z + 1.0))
		hider.hide_unseen()
		for view: Node3D in behind:
			assert_bool(view.visible).override_failure_message(str(view.get_path())).is_true()


func test_no_driven_part_nor_plate_item_draws_through_walls_or_over_the_level() -> void:
	var items := _loaded_items()
	_now = 100 + roundi(FixtureCookingModes.type_of(_mode).fried_ticks() / 2.0)
	await _frames()
	var roots: Array[Node] = []
	for root: Node3D in _views.scene_roots():
		roots.append(root)
	roots.append(items)
	var drawn := 0
	for root: Node in roots:
		for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
			drawn += 1
			var path := str(node.get_path())
			var sprite := node as SpriteBase3D
			if sprite != null:
				assert_bool(sprite.no_depth_test).override_failure_message(path).is_false()
				assert_int(sprite.render_priority).override_failure_message(path).is_equal(0)
			var label := node as Label3D
			if label != null:
				assert_bool(label.no_depth_test).override_failure_message(path).is_false()
				assert_int(label.render_priority).override_failure_message(path).is_equal(0)
			for material: Material in _materials_of(node as GeometryInstance3D):
				assert_int(material.render_priority).override_failure_message(path).is_equal(0)
				var base := material as BaseMaterial3D
				if base != null:
					assert_bool(base.no_depth_test).override_failure_message(path).is_false()
	# The ring's segments, a plant, a board picture and the outlined plate items are among them.
	assert_int(drawn).is_greater(CookingViews.RING_SEGMENTS)


## ItemViews over the model with a bun and a herb on the first place and a raw patty
## on the grill, drawn at CookingViews.point_of.
func _loaded_items() -> ItemViews:
	var items := auto_free(ItemViews.new()) as ItemViews
	items.model = _model
	items.mode = _mode
	items.station_point = _views.point_of
	add_child(items)
	var type := FixtureCookingModes.type_of(_mode)
	FixtureCookingClient.hold(_model, 1, &"bun_a")
	FixtureCookingClient.put(_model, 1, 0)
	FixtureCookingClient.hold(_model, 2, &"herb_b")
	FixtureCookingClient.put(_model, 2, 0)
	FixtureCookingClient.hold(_model, 3, &"raw_a")
	FixtureCookingClient.grill(_model, 3, 100 + type.fried_ticks(), 100 + type.burnt_ticks())
	return items


func _wall(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_level.add_child(body)


func _bed_spot_z() -> float:
	return (_beds.get_node("Bed1/UseSpot") as Node3D).global_position.z


## The views whose sight point lies in the row of use spots at `z` (within 2 m).
func _views_in_row(views: Array[Node3D], z: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for view: Node3D in views:
		var point: Vector3 = view.call(&"sight_point") as Vector3
		if absf(point.z - z) < 2.0:
			found.append(view)
	return found


## The middle of the views' sight points in x.
func _row_x(views: Array[Node3D]) -> float:
	var low := INF
	var high := -INF
	for view: Node3D in views:
		var x := (view.call(&"sight_point") as Vector3).x
		low = minf(low, x)
		high = maxf(high, x)
	return (low + high) / 2.0


func _materials_of(node: GeometryInstance3D) -> Array[Material]:
	var found: Array[Material] = []
	for material: Material in [node.material_override, node.material_overlay]:
		if material != null:
			found.append(material)
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for i in mesh.mesh.get_surface_count():
			var surface := mesh.get_surface_override_material(i)
			if surface == null:
				surface = mesh.mesh.surface_get_material(i)
			if surface != null:
				found.append(surface)
	return found


func _add(scene: StringName, spot_at: Vector3) -> void:
	var root := (load(SCENES % scene) as PackedScene).instantiate() as Node3D
	root.position = spot_at - (root.get_node("UseSpot") as Node3D).position
	_level.add_child(root)


func _place(id: int, kind: StringName, at: Vector3) -> void:
	FixtureCookingClient.place_station(_model, id, kind, at)


func _name(kind: StringName) -> String:
	return ContentNames.text(ContentNames.item(kind, _mode))


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
