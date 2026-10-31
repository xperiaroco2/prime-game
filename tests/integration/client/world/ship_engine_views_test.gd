extends GdUnitTestSuite
## The ship engine's stand-in views (#1462; ARCHITECTURE §9.5.27 "For part 3's client", §4.7.59),
## driven from a ClientModel folded from the engine's events, the base mode's engine and a host
## tick the test sets: the console's stage strips, a red lamp over each station of an open problem,
## the breakers' lamps and the mimic board, where alone the order plays, the gill sets' slits and
## white bar, a charger's lamp and the blast. And ShipEngineClient offers no breaker board.

const BASE_MODE := "res://content/modes/base_mode.tres"
const CONSOLE := 1
const GILLS := 2
const BOARD_EAST := 3
const BOARD_WEST := 4
## Breakers 5 to 8 hang by the east board, 9 to 12 by the west one.
const FIRST_BREAKER := 5
const SOCKET := 13
const CHARGER := 14
const GILLS_AT := Vector3(2.0, 1.2, -3.0)

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


func test_nothing_is_drawn_before_the_console_is_placed() -> void:
	_view._process(0.0)
	assert_int(_view.get_child_count()).is_equal(0)
	_place()
	_view._process(0.0)
	assert_int(_view.get_child_count()).is_greater(0)


func test_a_station_of_an_open_problem_shows_a_red_lamp_until_it_is_fixed() -> void:
	_place()
	_view._process(0.0)
	assert_bool(_view.lamp_of(SOCKET).visible).is_false()
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 600))
	_view._process(0.0)
	assert_bool(_view.lamp_of(SOCKET).visible).is_true()
	assert_object(ShipEngineViews.colour_of(_view.lamp_of(SOCKET))).is_equal(ShipEngineViews.RED)
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_view._process(0.0)
	assert_bool(_view.lamp_of(SOCKET).visible).is_false()


func test_the_order_plays_on_the_mimic_board_and_never_at_the_boards() -> void:
	_place()
	var order: Array[int] = [7, 11, 5]
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD_EAST, BOARD_WEST], 900))
	_model.fold(&"BreakerChain", _chain(1, order, 0, -1))
	var step := maxi(1, Ticks.from_seconds(ShipEngineViews.ORDER_STEP_SECONDS))
	for i in order.size():
		_now = i * step
		_view._process(0.0)
		for j in order.size():
			var colour := ShipEngineViews.colour_of(_view.mimic_of(order[j]))
			var expected := ShipEngineViews.WHITE if i == j else ShipEngineViews.RED
			assert_object(colour).override_failure_message("step %d, %d" % [i, j]).is_equal(
				expected
			)
	for tick in range(0, step * 6):
		_now = tick
		_view._process(0.0)
		for breaker in range(FIRST_BREAKER, FIRST_BREAKER + 8):
			assert_object(ShipEngineViews.colour_of(_view.lamp_of(breaker))).is_not_equal(
				ShipEngineViews.WHITE
			)
	# A breaker no problem tripped stays dark on the mimic board and at its board.
	assert_object(ShipEngineViews.colour_of(_view.mimic_of(6))).is_equal(ShipEngineViews.DARK)
	assert_bool(_view.lamp_of(6).visible).is_false()


func test_a_breaker_lamp_is_red_tripped_yellow_then_green_once_on() -> void:
	_place()
	var ramp := _breakers().ramp_ticks()
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD_EAST], 900))
	_model.fold(&"BreakerChain", _chain(1, [5, 6, 7], 2, 100))
	_now = 100 + ramp - 1
	_view._process(0.0)
	assert_object(ShipEngineViews.colour_of(_view.lamp_of(5))).is_equal(ShipEngineViews.GREEN)
	assert_object(ShipEngineViews.colour_of(_view.lamp_of(6))).is_equal(ShipEngineViews.YELLOW)
	assert_object(ShipEngineViews.colour_of(_view.lamp_of(7))).is_equal(ShipEngineViews.RED)
	_now = 100 + ramp
	_view._process(0.0)
	assert_object(ShipEngineViews.colour_of(_view.lamp_of(6))).is_equal(ShipEngineViews.GREEN)


func test_the_stage_strips_fill_with_their_third_of_the_bar() -> void:
	_place()
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 300, "needed": 600, "counting": false, "tick": 0}
	)
	_view._process(0.0)
	assert_float(_view.strip_fill(0).scale.x).is_equal_approx(1.0, 1e-4)
	assert_float(_view.strip_fill(1).scale.x).is_equal_approx(0.5, 1e-4)
	assert_bool(_view.strip_fill(2).visible).is_false()


func test_the_gills_show_their_slits_and_the_white_bar_from_the_opening_tick() -> void:
	_place()
	var level := _level()
	_view.level = level
	_view._process(0.0)
	var gills := level.get_child(0)
	for slit in range(1, 6):
		assert_bool((gills.get_node("Slit%d/Open" % slit) as Node3D).visible).is_true()
		assert_bool((gills.get_node("Light%d" % slit) as Node3D).visible).is_false()
	var kind := _gills()
	var deadline := 1000
	var opened := deadline - Ticks.from_seconds(kind.seconds)
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS], deadline))
	_model.fold(&"GillFlipped", {"station": GILLS, "slit": 1, "open": true})
	_now = opened + kind.step_ticks()
	_view._process(0.0)
	assert_bool((gills.get_node("Slit1/Shut") as Node3D).visible).is_true()
	assert_bool((gills.get_node("Slit1/Open") as Node3D).visible).is_false()
	assert_bool((gills.get_node("Slit2/Open") as Node3D).visible).is_true()
	# One step after the opening the bar stands on the second slit (GillsProblem.BAR).
	for slit in range(1, 6):
		assert_bool((gills.get_node("Light%d" % slit) as Node3D).visible).is_equal(slit == 2)


func test_a_charger_lamp_is_yellow_while_charging_and_green_with_a_crystal_waiting() -> void:
	_place()
	_model.fold(&"CrystalChanged", _crystal(CHARGER, CrystalProblem.CHARGING))
	_view._process(0.0)
	assert_object(ShipEngineViews.colour_of(_view.lamp_of(CHARGER))).is_equal(
		ShipEngineViews.YELLOW
	)
	_model.fold(&"CrystalChanged", _crystal(CHARGER, CrystalProblem.WAITING))
	_view._process(0.0)
	assert_object(ShipEngineViews.colour_of(_view.lamp_of(CHARGER))).is_equal(ShipEngineViews.GREEN)


func test_a_blast_swells_once_and_fades() -> void:
	_place()
	_view._process(0.0)
	_model.fold(&"EngineBlast", {"stage": 1})
	_view._process(0.1)
	var blast := _blast()
	assert_object(blast).is_not_null()
	assert_bool(blast.visible).is_true()
	_view._process(ShipEngineViews.BLAST_SECONDS)
	assert_bool(blast.visible).is_false()
	_view._process(0.1)
	assert_bool(blast.visible).is_false()


func test_the_client_offers_no_breaker_board_but_its_breakers() -> void:
	_place()
	var client := ShipEngineClient.new()
	var engine: ShipEngine = ShipEngineClient.types_of(_mode)[0]
	assert_bool(client.usable(_model, engine, BOARD_EAST)).is_false()
	assert_bool(client.usable(_model, engine, FIRST_BREAKER)).is_true()
	assert_bool(client.usable(_model, engine, CONSOLE)).is_true()
	assert_bool(client.usable(_model, engine, GILLS)).is_true()


func _place() -> void:
	_station(CONSOLE, &"engine_console", Vector3(0.0, 1.2, -0.4))
	_station(GILLS, &"gill_button", GILLS_AT)
	_station(BOARD_EAST, &"breaker_board", Vector3(6.5, 1.2, -0.2))
	_station(BOARD_WEST, &"breaker_board", Vector3(-6.5, 1.2, -0.2))
	for i in 8:
		var side := 1.0 if i < 4 else -1.0
		_station(FIRST_BREAKER + i, &"breaker", Vector3(side * (5.8 + 0.5 * (i % 4)), 1.2, -0.2))
	_station(SOCKET, &"cartridge_socket", Vector3(1.5, 1.2, 2.4))
	_station(CHARGER, &"cartridge_charger", Vector3(10.4, 1.2, 1.8))


func _station(id: int, kind: StringName, at: Vector3) -> void:
	_model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)


## A level with one gill set, its Button by the gill button's spot.
func _level() -> Node3D:
	var level: Node3D = auto_free(Node3D.new())
	var gills := Node3D.new()
	gills.add_to_group(&"engine_gills", true)
	level.add_child(gills)
	for slit in range(1, 6):
		var cut := Node3D.new()
		cut.name = "Slit%d" % slit
		gills.add_child(cut)
		for part: String in ["Open", "Shut"]:
			var look := Node3D.new()
			look.name = part
			look.visible = part == "Open"
			cut.add_child(look)
		var light := Node3D.new()
		light.name = "Light%d" % slit
		light.visible = false
		gills.add_child(light)
	var button := Node3D.new()
	button.name = "Button"
	button.position = GILLS_AT + Vector3(0.6, 1.15, 0.0)
	gills.add_child(button)
	add_child(level)
	return level


func _blast() -> MeshInstance3D:
	for child: Node in _view.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is SphereMesh:
			return child as MeshInstance3D
	return null


func _gills() -> GillsProblem:
	for kind: ProblemKind in ShipEngineClient.types_of(_mode)[0].kinds:
		if kind is GillsProblem:
			return kind as GillsProblem
	return null


func _breakers() -> BreakersProblem:
	for kind: ProblemKind in ShipEngineClient.types_of(_mode)[0].kinds:
		if kind is BreakersProblem:
			return kind as BreakersProblem
	return null


func _opened(problem: int, stations: Array[int], deadline: int) -> Dictionary:
	return {"problem": problem, "stations": PackedInt32Array(stations), "deadline": deadline}


func _chain(problem: int, order: Array[int], next: int, since: int) -> Dictionary:
	return {"problem": problem, "breakers": PackedInt32Array(order), "next": next, "since": since}


func _crystal(charger: int, phase: int) -> Dictionary:
	return {"station": SOCKET, "charger": charger, "phase": phase, "item": 7, "tick": -1}
