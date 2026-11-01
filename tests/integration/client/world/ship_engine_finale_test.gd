extends GdUnitTestSuite
## The ship engine's finish (client/world/ship_engine_finale.gd, #1502; GDD §8): ShipEngineViews
## starts it at the roar, from the filtered ZoneProgress of the engine's last stage: a flame from
## each nozzle pod of the level along its exhaust axis, and the light show over the hologram, for
## the Round's linger; then it is gone. Driven like ship_engine_views_test.gd: a ClientModel, the
## base mode and frames the test runs.

const BASE_MODE := "res://content/modes/base_mode.tres"
const CONSOLE := 1
const CONSOLE_AT := Vector3(0.0, 1.2, -0.4)
## Three pods, turned so their exhaust axis differs from the level's: name -> (origin, yaw).
const PODS := {
	"nozzle_pod_mid_500": [Vector3(0.0, 2.5, 9.6), 0.0],
	"nozzle_pod_outer_496": [Vector3(-3.0, 2.0, 9.6), 0.5],
	"nozzle_pod_outer_498": [Vector3(3.0, 2.0, 9.6), -0.5],
}
const BELL_M := 1.2

var _mode: GameMode
var _model: ClientModel
var _view: ShipEngineViews
var _now := 0


func before_test() -> void:
	_mode = load(BASE_MODE) as GameMode
	_model = ClientModel.new(_mode)
	_now = 0
	_view = auto_free(ShipEngineViews.new())
	_view.model = _model
	_view.mode = _mode
	_view.host_tick = func() -> int: return _now
	add_child(_view)


func test_the_roar_starts_a_flame_at_each_nozzle_and_the_light_show() -> void:
	_view.level = _level(true)
	_placed()
	assert_bool(_finale().playing()).is_false()
	_done()
	_view._process(0.0)
	var finale := _finale()
	assert_bool(finale.playing()).is_true()
	assert_int(finale.lights().size()).is_equal(ShipEngineFinale.SHOW_LIGHTS)
	var mouths := ShipEngineFinale.nozzles_of(_view.level)
	assert_int(mouths.size()).is_equal(3)
	assert_int(finale.flames().size()).is_equal(3)
	var names: Array = PODS.keys()
	names.sort()
	for i in 3:
		var spec: Array = PODS[names[i]]
		var axis := Basis(Vector3.UP, spec[1] as float) * ShipEngineFinale.EXHAUST_AXIS
		var mouth := (spec[0] as Vector3) + axis * BELL_M
		assert_bool(mouths[i].origin.is_equal_approx(mouth)).is_true()
		assert_bool(mouths[i].basis.z.is_equal_approx(axis)).is_true()
	_run(0.5)
	# Grown: each flame reaches out of its mouth along the axis, away from the ship.
	for i in 3:
		var flame := finale.flames()[i]
		var reach := (flame.global_position - mouths[i].origin).dot(mouths[i].basis.z)
		assert_float(reach).is_greater(1.0)
	# The show circles over the hologram's centre (here over the console: the level gives no point).
	for light: OmniLight3D in finale.lights():
		var flat := Vector2(light.position.x - CONSOLE_AT.x, light.position.z - CONSOLE_AT.z)
		assert_float(flat.length()).is_equal_approx(ShipEngineFinale.SHOW_RADIUS_M, 0.01)


func test_the_finish_lasts_the_round_s_linger_then_is_gone() -> void:
	_view.level = _level(true)
	_placed()
	_done()
	_view._process(0.0)
	var seconds := ShipEngineFinale.seconds_of(_mode)
	assert_float(seconds).is_equal(4.0)
	_run(seconds - 0.2)
	assert_bool(_finale().playing()).is_true()
	_run(0.3)
	assert_bool(_finale().playing()).is_false()
	assert_array(_finale().flames()).is_empty()
	assert_array(_finale().lights()).is_empty()


func test_a_level_with_no_nozzles_shows_the_light_show_alone() -> void:
	_view.level = _level(false)
	_placed()
	_done()
	_view._process(0.0)
	assert_bool(_finale().playing()).is_true()
	assert_array(_finale().flames()).is_empty()
	assert_int(_finale().lights().size()).is_equal(ShipEngineFinale.SHOW_LIGHTS)


func test_no_finish_without_the_last_stage_or_for_a_view_built_again() -> void:
	_view.level = _level(true)
	_placed()
	_run(1.0)
	assert_bool(_finale().playing()).is_false()
	_done()
	_view._process(0.0)
	assert_bool(_finale().playing()).is_true()
	# A new level builds the engine again: the old finish is not played again.
	_view.level = _level(true)
	_view._process(0.0)
	_view._process(0.1)
	assert_bool(_finale().playing()).is_false()


func test_the_finish_plays_also_in_the_frame_the_round_ends() -> void:
	_view.level = _level(true)
	_placed()
	_done()
	_model.fold(&"PhaseChanged", PhaseChangedEvent.new(&"end", 1000).to_dict())
	_view._process(0.0)
	assert_bool(_finale().playing()).is_true()
	_view.clear()
	assert_object(_view_finale()).is_null()


func test_the_finish_s_seconds_follow_the_round_s_linger() -> void:
	var mode := _mode.duplicate(true) as GameMode
	mode.find_phase(&"round").settings[RoundPhase.LINGER_SECONDS] = 2.5
	assert_float(ShipEngineFinale.seconds_of(mode)).is_equal(2.5)
	mode.find_phase(&"round").settings.erase(RoundPhase.LINGER_SECONDS)
	assert_float(ShipEngineFinale.seconds_of(mode)).is_equal(ShipEngineFinale.DEFAULT_SECONDS)
	assert_float(ShipEngineFinale.seconds_of(null)).is_equal(ShipEngineFinale.DEFAULT_SECONDS)


func _placed() -> void:
	_model.fold(&"PhaseChanged", PhaseChangedEvent.new(&"round", 1000).to_dict())
	_model.fold(
		&"StationPlaced",
		{
			"station": CONSOLE,
			"kind": &"engine_console",
			"colour": Color.WHITE,
			"position": CONSOLE_AT
		}
	)
	_view._process(0.0)


## The engine's last stage passed: its bar's done ZoneProgress.
func _done() -> void:
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 600, "needed": 600, "counting": false, "tick": 0}
	)


func _run(seconds: float) -> void:
	var frames := roundi(seconds / 0.1)
	for i in frames:
		_view._process(0.1)


func _finale() -> ShipEngineFinale:
	var found := _view_finale()
	assert_object(found).is_not_null()
	return found


func _view_finale() -> ShipEngineFinale:
	for child: Node in _view.get_children():
		if child is ShipEngineFinale and not child.is_queued_for_deletion():
			return child as ShipEngineFinale
	return null


## A level with the three pods (each a `pod_bell` box BELL_M deep behind its origin along the
## exhaust axis), or none.
func _level(pods: bool) -> Node3D:
	var level: Node3D = auto_free(Node3D.new())
	var art := Node3D.new()
	art.name = "Art"
	level.add_child(art)
	if pods:
		for pod_name: String in PODS:
			var spec: Array = PODS[pod_name]
			var pod := Node3D.new()
			pod.name = pod_name
			pod.position = spec[0]
			pod.rotation.y = spec[1]
			art.add_child(pod)
			var bell := MeshInstance3D.new()
			bell.name = "pod_bell"
			var box := BoxMesh.new()
			box.size = Vector3(0.8, 0.8, BELL_M)
			bell.mesh = box
			bell.position = ShipEngineFinale.EXHAUST_AXIS * BELL_M * 0.5
			pod.add_child(bell)
	add_child(level)
	return level
