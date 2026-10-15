extends GdUnitTestSuite
## The car repair's station scenes driven from the own ClientModel (#811, ARCHITECTURE §4.7.56; the
## car repair ADR's §8 R7, RE8, RE16, RD3): R5's real scenes (`levels/stations/`) under a fixture
## level, the stations of FixtureCarRepairModes placed at their use spots (for_scenes(): the
## shelf's bin tags, R5's clearance). The car's Lift rises to the clearance over rise_ticks and
## drops after a stop; the panel's lamp shows `up` only; the wall picture wears its bin plate's
## material and follows PartNeeded; a shelf hit names the nearest bin, turned or not; the Lift and
## the scenes' Collision name their stations; every driven part sits under a SightHider wrapper.

const SCENES := "res://levels/stations/%s.tscn"
const CAR := FixtureCarRepairClient.CAR
const PANEL := FixtureCarRepairClient.PANEL
const FIRST_BIN := FixtureCarRepairClient.FIRST_BIN
const PICTURE := FixtureCarRepairClient.PICTURE
const CAR_AT := Vector3(0, 0, 0)
const PANEL_AT := Vector3(4, 0, 0)
const SHELF_AT := Vector3(-6, 0, 6)
const PICTURE_AT := Vector3(6, 0, 6)

var _level: Node3D
var _views: CarRepairViews
var _model: ClientModel
var _mode: GameMode
var _type: CarRepair
var _now := 0
var _car: Node3D
var _panel: Node3D
var _shelf: Node3D
var _picture: Node3D


func before_test() -> void:
	_mode = FixtureCarRepairClient.for_scenes(FixtureCarRepairModes.basic())
	_type = FixtureCarRepairModes.type_of(_mode)
	_level = auto_free(Node3D.new())
	add_child(_level)
	_car = _add("car", CAR_AT)
	_panel = _add("lift_panel", PANEL_AT)
	_shelf = _add("parts_shelf", SHELF_AT)
	_picture = _add("part_picture", PICTURE_AT)
	_views = auto_free(CarRepairViews.new())
	_views.mode = _mode
	_views.host_tick = func() -> int: return _now
	add_child(_views)
	await _start(0.0)


func _start(shelf_turn: float) -> void:
	_shelf.rotation.y = shelf_turn
	var spots: Array[Vector3] = []
	for k in 3:
		spots.append((_shelf.get_node("Bin%d/UseSpot" % (k + 1)) as Node3D).global_position)
	_model = FixtureCarRepairClient.dealt(
		_mode, &"spark_plug", _spot(_car), _spot(_panel), spots, _spot(_picture)
	)
	_views.model = _model
	_views.level = _level
	await _frames()


func test_every_station_binds_to_its_scene() -> void:
	assert_object(_views.scene_of(CAR)).is_same(_car)
	assert_object(_views.scene_of(PANEL)).is_same(_panel)
	assert_object(_views.scene_of(PICTURE)).is_same(_picture)
	for k in 3:
		assert_object(_views.scene_of(FIRST_BIN + k)).is_same(_shelf.get_node("Bin%d" % (k + 1)))


func test_the_lift_rises_to_the_clearance_and_drops_after_a_stop() -> void:
	var lift := _car.get_node("Lift") as Node3D
	assert_float(lift.position.y).is_equal_approx(0.0, 0.001)
	FixtureCarRepairClient.lift(_model, true, 100)
	_now = 100
	await _frames()
	assert_float(lift.position.y).is_less(0.1)
	_now = 100 + _type.rise_ticks() / 2
	await _frames()
	var half := lift.position.y
	assert_float(half).is_between(0.3, 0.95)
	_now = 100 + _type.rise_ticks() + 5
	await _frames()
	var hull := lift.get_node("Hull") as CollisionShape3D
	var box := hull.shape as BoxShape3D
	var underside := lift.global_position.y + hull.position.y - box.size.y / 2.0
	assert_float(underside).is_equal_approx(_type.clearance_m, 0.001)
	FixtureCarRepairClient.lift(_model, false, _now)
	_now += Ticks.from_seconds(CarRepairUse.DROP_SECONDS) + 1
	await _frames()
	assert_float(lift.position.y).is_equal_approx(0.0, 0.001)


func test_an_unbound_car_stays_lowered() -> void:
	FixtureCarRepairClient.lift(_model, true, 0)
	_now = 1000
	_car.position = Vector3(30, 0, 0)
	_views.level = _level
	await _frames()
	assert_object(_views.scene_of(CAR)).is_null()
	assert_float((_car.get_node("Lift") as Node3D).position.y).is_equal_approx(0.0, 0.001)


func test_the_lamp_shows_up_only() -> void:
	var lamp := _views.scene_of(PANEL).get_node("StationSight/Light") as Node3D
	assert_bool(lamp.visible).is_false()
	FixtureCarRepairClient.lift(_model, true, 10)
	await _frames()
	assert_bool(lamp.visible).is_true()
	FixtureCarRepairClient.lift(_model, false, 20)
	await _frames()
	assert_bool(lamp.visible).is_false()


func test_the_picture_wears_the_plate_of_the_needed_parts_bin() -> void:
	var quad := _picture.get_node("StationSight/Picture") as MeshInstance3D
	for i in _type.parts.size():
		var part := _type.parts[i]
		FixtureCarRepairClient.fold(_model, PartNeededEvent.new(PICTURE, part.id))
		await _frames()
		var bin := _type.bin_of(part)
		var bin_scene := _shelf.get_node("Bin%d" % (_type.bins.find(bin) + 1))
		var plate := bin_scene.get_node("Picture") as MeshInstance3D
		assert_bool(quad.visible).is_true()
		assert_object(quad.material_override).is_same(plate.get_active_material(0))
	FixtureCarRepairClient.fold(_model, PartNeededEvent.new(PICTURE, &""))
	await _frames()
	assert_bool(quad.visible).is_false()


func test_an_unbound_bin_s_fallback_picture_is_made_once() -> void:
	_shelf.position = Vector3(40, 0, 0)
	_views.level = _level
	await _frames()
	assert_object(_views.scene_of(FIRST_BIN)).is_null()
	var quad := _picture.get_node("StationSight/Picture") as MeshInstance3D
	var look := quad.material_override
	assert_bool(quad.visible).is_true()
	assert_object(look).is_not_null()
	await _frames()
	assert_object(quad.material_override).is_same(look)


func test_the_plates_differ_so_the_pictures_do() -> void:
	var looks: Array[Material] = []
	for k in 3:
		var plate := _shelf.get_node("Bin%d/Picture" % (k + 1)) as MeshInstance3D
		var look := plate.get_active_material(0)
		assert_bool(looks.has(look)).is_false()
		looks.append(look)


func test_a_shelf_hit_names_the_nearest_bin() -> void:
	var body := _shelf.get_node("Collision")
	for k in 3:
		var bin := _shelf.get_node("Bin%d" % (k + 1)) as Node3D
		var point := bin.global_position + Vector3(0, 1.2, 0.2)
		assert_int(_views.station_of_point(body, point)).is_equal(FIRST_BIN + k)
	assert_int(_views.station_of_point(_panel.get_node("Collision"), Vector3.ZERO)).is_equal(-1)


func test_a_turned_shelf_hit_names_the_nearest_bin() -> void:
	await _start(PI / 2.0)
	var body := _shelf.get_node("Collision")
	for k in 3:
		var bin := _shelf.get_node("Bin%d" % (k + 1)) as Node3D
		var point := bin.global_position + bin.global_basis.z * 0.2 + Vector3.UP
		assert_int(_views.station_of_point(body, point)).is_equal(FIRST_BIN + k)


func test_the_lift_and_the_collisions_name_their_stations() -> void:
	assert_int(_views.station_of_hit(_car.get_node("Lift"), 0)).is_equal(CAR)
	assert_int(_views.station_of_hit(_car.get_node("Collision"), 0)).is_equal(CAR)
	assert_int(_views.station_of_hit(_panel.get_node("Collision"), 0)).is_equal(PANEL)
	assert_int(_views.station_of_hit(_shelf.get_node("Collision"), 0)).is_equal(-1)


func test_the_driven_parts_sit_under_sight_wrappers() -> void:
	for root: Node3D in [_panel, _picture]:
		var sight := root.get_node("StationSight")
		assert_bool(sight.is_in_group(SightHider.GROUP)).is_true()
	assert_object(_panel.get_node_or_null("Light")).is_null()
	assert_object(_picture.get_node_or_null("Picture")).is_null()


func _add(scene: String, at: Vector3) -> Node3D:
	var root := (load(SCENES % scene) as PackedScene).instantiate() as Node3D
	root.position = at
	_level.add_child(root)
	return root


func _spot(root: Node3D) -> Vector3:
	return (root.get_node("UseSpot") as Node3D).global_position


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
