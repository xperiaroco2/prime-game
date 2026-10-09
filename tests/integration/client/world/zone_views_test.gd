extends GdUnitTestSuite
## ZoneViews in a world (ARCHITECTURE §4.7; the zone task ADR's ZD11 (b) and ZE8, #650): a zone
## is a disc, a fill and a ring of its station kind's radius in StationPlaced's colour, and no
## delivery circle's cylinder; its fill follows the host's ZoneProgress and the estimated host
## tick; a done zone is full and dimmed; nothing of it draws through walls (the M4 ADR's §3 item 5).

const NEEDED := 20
const YELLOW := Color(0.95, 0.85, 0.2)
const ZONE := 4
const CIRCLE := 5

var _mode: GameMode
var _model: ClientModel
var _world: Node3D
var _zones: ZoneViews
var _circles: CircleViews
var _host_tick := -1


func before_test() -> void:
	_mode = GameMode.new()
	var package := ItemKind.new()
	package.id = &"package"
	_mode.task_types.append(FixtureDeliveryModes.delivery(package))
	_mode.task_types.append(FixtureZoneModes.zone_task())
	_model = ClientModel.new(_mode)
	_model.own_peer = 1
	_world = Node3D.new()
	add_child(_world)
	_zones = ZoneViews.new()
	_zones.model = _model
	_zones.mode = _mode
	_zones.host_tick = func() -> int: return _host_tick
	_world.add_child(_zones)
	_circles = CircleViews.new()
	_circles.model = _model
	_circles.mode = _mode
	_world.add_child(_circles)
	_model.fold(
		&"StationPlaced",
		{"station": ZONE, "kind": &"zone", "colour": YELLOW, "position": Vector3(2, 0, -3)}
	)
	_model.fold(
		&"StationPlaced",
		{"station": CIRCLE, "kind": &"circle", "colour": Color.RED, "position": Vector3(6, 0, 0)}
	)


func after_test() -> void:
	_world.free()


func test_a_zone_has_its_own_look_of_its_kinds_radius_in_its_colour_and_no_circle() -> void:
	await _drawn()
	assert_int(_zones.count()).is_equal(1)
	assert_object(_zones.view_of(CIRCLE)).is_null()
	assert_object(_circles.view_of(ZONE)).is_null()
	assert_object(_circles.view_of(CIRCLE)).is_not_null()
	var view := _zones.view_of(ZONE)
	assert_that(view.global_position).is_equal(Vector3(2, 0, -3))
	var radius := FixtureZoneModes.RADIUS_M
	assert_float((_part(&"Disc").mesh as CylinderMesh).top_radius).is_equal(radius)
	assert_float((_part(&"Fill").mesh as CylinderMesh).top_radius).is_equal(radius)
	assert_float((_part(&"Ring").mesh as TorusMesh).outer_radius).is_equal(radius)
	for part: StringName in [&"Disc", &"Fill", &"Ring"]:
		var colour := _colour(part)
		assert_float(colour.r).is_equal_approx(YELLOW.r, 1e-5)
		assert_float(colour.b).is_equal_approx(YELLOW.b, 1e-5)
	# No progress yet: no fill.
	assert_bool(_part(&"Fill").visible).is_false()


func test_the_fill_follows_zone_progress_and_the_host_tick() -> void:
	_host_tick = 100
	await _drawn()
	assert_bool(_part(&"Fill").visible).is_false()
	# The host tick alone starts nothing: the fill waits for the host's ZoneProgress.
	_host_tick = 140
	await _drawn()
	assert_bool(_part(&"Fill").visible).is_false()
	_progress(4, true, 140)
	_host_tick = 146
	await _drawn()
	assert_bool(_part(&"Fill").visible).is_true()
	assert_float(_part(&"Fill").scale.x).is_equal_approx(0.5, 1e-5)
	assert_float(_part(&"Fill").scale.z).is_equal_approx(0.5, 1e-5)
	_host_tick = 400
	await _drawn()
	assert_float(_part(&"Fill").scale.x).is_equal_approx(1.0, 1e-5)
	# Stopped at 12 of 20: it stands still whatever the tick.
	_progress(12, false, 152)
	_host_tick = 500
	await _drawn()
	assert_float(_part(&"Fill").scale.x).is_equal_approx(0.6, 1e-5)


func test_a_done_zone_is_full_and_dimmed() -> void:
	_progress(10, false, 100)
	await _drawn()
	var open := {}
	for part: StringName in [&"Disc", &"Fill", &"Ring"]:
		open[part] = _colour(part)
	_progress(NEEDED, false, 130)
	await _drawn()
	assert_bool(_model.stations[ZONE].done).is_true()
	assert_float(_part(&"Fill").scale.x).is_equal_approx(1.0, 1e-5)
	for part: StringName in [&"Fill", &"Ring"]:
		assert_float(_colour(part).a).is_less((open[part] as Color).a)
	for part: StringName in [&"Disc", &"Fill", &"Ring"]:
		assert_float(_colour(part).r).is_less((open[part] as Color).r)


func test_nothing_of_a_zone_draws_through_walls() -> void:
	_progress(4, true, 100)
	_host_tick = 105
	await _drawn()
	var meshes := _zones.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_equal(3)
	for node: Node in meshes:
		var material := (node as MeshInstance3D).material_override as BaseMaterial3D
		assert_object(material).is_not_null()
		assert_bool(material.no_depth_test).override_failure_message(str(node.name)).is_false()
		assert_int(material.depth_test).is_equal(BaseMaterial3D.DEPTH_TEST_DEFAULT)
	assert_int(_zones.find_children("*", "Label3D", true, false).size()).is_equal(0)


func test_views_go_with_the_models_stations() -> void:
	await _drawn()
	assert_int(_zones.count()).is_equal(1)
	_model.clear_match()
	await _drawn()
	assert_int(_zones.count()).is_equal(0)
	assert_object(_zones.view_of(ZONE)).is_null()


func _progress(ticks: int, counting: bool, at_tick: int) -> void:
	_model.fold(
		&"ZoneProgress",
		{"station": ZONE, "ticks": ticks, "needed": NEEDED, "counting": counting, "tick": at_tick}
	)


func _part(part: StringName) -> MeshInstance3D:
	return _zones.view_of(ZONE).get_node(NodePath(part)) as MeshInstance3D


func _colour(part: StringName) -> Color:
	return (_part(part).material_override as StandardMaterial3D).albedo_color


## Waits until ZoneViews and CircleViews have drawn (in their _process) since the state the test
## folded: process_frame is emitted before that frame's _process, so the second one comes after a
## _process that saw the state (#222).
func _drawn() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
