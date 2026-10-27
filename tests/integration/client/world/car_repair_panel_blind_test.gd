extends GdUnitTestSuite
## The lift panel is blind to the car (#811, ARCHITECTURE §4.7.57; the car repair ADR's RE16, RD14):
## the holder at the panel learns nothing of what happens under the car from the panel. With R5's
## real lift_panel.tscn under CarRepairViews, the lamp, StationUse.usable(panel) and the HUD aimed
## at the panel stay the same through FitChanged (a fitter starting and stopping) and a PartFitted
## that does not finish the task, the lift down and the lift up. The sounds' half (FitChanged
## silent, the task's success at the car) is car_repair_sounds_test's.

const SCENES := "res://levels/stations/%s.tscn"
const CAR := FixtureCarRepairClient.CAR
const PANEL := FixtureCarRepairClient.PANEL
const OTHER := FixtureCarRepairClient.OTHER
const PART_ITEM := 50

var _level: Node3D
var _views: CarRepairViews
var _model: ClientModel
var _mode: GameMode
var _now := 100
var _panel: Node3D


func before_test() -> void:
	_mode = FixtureCarRepairClient.for_scenes(FixtureCarRepairModes.basic())
	_level = auto_free(Node3D.new())
	add_child(_level)
	var car := _add("car", Vector3.ZERO)
	_panel = _add("lift_panel", Vector3(4, 0, 0))
	var bins: Array[Vector3] = [Vector3(-6, 0, 6), Vector3(-5, 0, 6), Vector3(-4, 0, 6)]
	_model = FixtureCarRepairClient.dealt(
		_mode, &"spark_plug", _spot(car), _spot(_panel), bins, Vector3(6, 0, 6)
	)
	FixtureCarRepairClient.at_tick(_model, _now)
	_views = auto_free(CarRepairViews.new())
	_views.mode = _mode
	_views.host_tick = func() -> int: return _now
	add_child(_views)
	_views.model = _model
	_views.level = _level
	await _frames()


func test_the_panel_shows_nothing_of_a_fit_while_the_lift_is_down() -> void:
	await _assert_blind()


func test_the_panel_shows_nothing_of_a_fit_while_the_lift_is_up() -> void:
	FixtureCarRepairClient.lift(_model, true, _now)
	_now += 400
	FixtureCarRepairClient.at_tick(_model, _now)
	await _frames()
	assert_bool(_lamp().visible).is_true()
	await _assert_blind()


## Folds a fit's events one by one and asserts after each that the panel looks as it did before.
func _assert_blind() -> void:
	var seen := _panel_view()
	FixtureCarRepairClient.hold(_model, PART_ITEM, &"spark_plug", OTHER)
	var steps: Array[MatchEvent] = [
		FitChangedEvent.new(CAR, OTHER, _now),
		FitChangedEvent.new(CAR, 0, _now + 5),
		FitChangedEvent.new(CAR, OTHER, _now + 10),
		PartFittedEvent.new(CAR, PART_ITEM),
	]
	for event in steps:
		FixtureCarRepairClient.fold(_model, event)
		_now += 20
		FixtureCarRepairClient.at_tick(_model, _now)
		await _frames()
		var message := "the panel changed after %s" % event.event_name()
		assert_array(_panel_view()).override_failure_message(message).is_equal(seen)
	assert_int(_model.stations[CAR].fitted).is_equal(1)


## What the holder at the panel can see of it: the lamp, whether E offers it, the HUD aimed at it.
func _panel_view() -> Array:
	var local := HudText.Local.new()
	local.aim_station = PANEL
	var shown := HudText.of(_model, _mode, float(_now), local)
	return [_lamp().visible, StationUse.usable(_model, _mode, PANEL), shown.aim, shown.raising]


func _lamp() -> Node3D:
	return _views.scene_of(PANEL).get_node("StationSight/Light") as Node3D


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
