extends GdUnitTestSuite
## The ship's station devices' looks driven by the engine (#1550, ARCHITECTURE §9.5.27): a level
## with the art console, a crystal socket, two breaker boards and a crystal charger; ShipEngineViews
## binds them to the engine's stations (ShipStationLooks) and sets their looks from a ClientModel
## folded from the engine's events and a host tick the test sets, in place of the stand-ins.

const BASE_MODE := "res://content/modes/base_mode.tres"
const CONSOLE_GLB := preload("res://assets/environment/start_console/start_console.glb")
const SOCKET_KIT := preload("res://levels/kit/crystal_socket/crystal_socket.tscn")
const BOARD_KIT := preload("res://levels/kit/breaker_board/breaker_board.tscn")
const CHARGER_KIT := preload("res://levels/kit/crystal_charger/crystal_charger.tscn")
const CONSOLE := 1
const GILLS := 2
const BOARD_EAST := 3
const BOARD_WEST := 4
## Breakers 5 to 8 hang by the east board, 9 to 12 by the west one.
const FIRST_BREAKER := 5
const SOCKET := 13
const CHARGER := 14
const CHARGER_WEST := 15

var _mode: GameMode
var _model: ClientModel
var _view: ShipEngineViews
var _level: Node3D
var _now := 0


func before_test() -> void:
	_mode = load(BASE_MODE) as GameMode
	_model = ClientModel.new(_mode)
	_now = 0
	_level = _devices()
	_view = auto_free(ShipEngineViews.new())
	_view.model = _model
	_view.mode = _mode
	_view.host_tick = func() -> int: return _now
	_view.level = _level
	add_child(_view)
	_place()
	_view._process(0.0)


func test_each_station_binds_to_its_device() -> void:
	var looks := _view.station_looks()
	assert_object(looks.console()).is_not_null()
	assert_object(looks.socket_of(SOCKET)).is_not_null()
	assert_object(looks.board_of(BOARD_EAST)).is_not_null()
	assert_object(looks.board_of(BOARD_WEST)).is_not_null()
	assert_object(looks.charger_of(CHARGER)).is_not_null()
	assert_object(looks.charger_of(CHARGER_WEST)).is_not_null()
	assert_object(looks.charger_of(CHARGER)).is_not_same(looks.charger_of(CHARGER_WEST))
	assert_object(looks.board_of(BOARD_EAST)).is_not_same(looks.board_of(BOARD_WEST))
	for i in 4:
		assert_int(looks.board_station_of(FIRST_BREAKER + i)).is_equal(BOARD_EAST)
		assert_int(looks.board_station_of(FIRST_BREAKER + 4 + i)).is_equal(BOARD_WEST)


func test_breakers_bind_to_shells_by_their_rank_along_the_board() -> void:
	var looks := _view.station_looks()
	# The east breakers run +X from 5 to 8; the west ones run -X from 9 to 12.
	assert_array([5, 6, 7, 8].map(looks.shell_of)).is_equal([0, 1, 2, 3])
	assert_array([12, 11, 10, 9].map(looks.shell_of)).is_equal([0, 1, 2, 3])


func test_a_breaker_s_console_lamp_has_its_shell_s_colour_on_its_board_s_wing() -> void:
	var looks := _view.station_looks()
	for i in 8:
		var breaker := FIRST_BREAKER + i
		var wing := 4 if i < 4 else 0
		assert_int(looks.lamp_of(breaker)).is_equal(wing + looks.shell_of(breaker))


func test_each_site_takes_its_wiring_point_by_its_side_in_the_console_s_frame() -> void:
	var looks := _view.station_looks()
	assert_str(looks.slot_of(SOCKET)).is_equal("socket_e")
	assert_str(looks.slot_of(GILLS)).is_equal("vent_e")
	assert_str(looks.slot_of(BOARD_EAST)).is_equal("breaker_e")
	assert_str(looks.slot_of(BOARD_WEST)).is_equal("breaker_w")
	assert_str(ShipStationLooks.site_slot("socket", Vector3(1.0, 0.0, 2.0))).is_equal("socket_fw")
	assert_str(ShipStationLooks.site_slot("socket", Vector3(-1.0, 0.0, -2.0))).is_equal("socket_e")


func test_the_devices_replace_their_stand_ins_and_the_art_hologram_the_game_s() -> void:
	for id: int in [SOCKET, CHARGER, CHARGER_WEST, BOARD_EAST, BOARD_WEST]:
		assert_object(_view.lamp_of(id)).is_null()
	for i in 8:
		assert_object(_view.lamp_of(FIRST_BREAKER + i)).is_null()
		assert_object(_view.mimic_of(FIRST_BREAKER + i)).is_null()
	assert_object(_view.lamp_of(GILLS)).is_not_null()
	assert_bool(_view.hologram().visible).is_false()
	assert_object(_view.strip_fill(0)).is_null()


func test_every_device_mesh_and_light_stays_on_the_live_cameras_layers() -> void:
	for node: Node in _level.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		(
			assert_int(visual.layers & PhotoLayers.LIVE_VIEW)
			. override_failure_message(str(visual.get_path()))
			. is_not_zero()
		)


func test_the_console_keeps_the_host_s_clock_and_calls_on_the_beep_s_tick() -> void:
	var console := _view.station_looks().console()
	_model.fold(&"PhaseChanged", PhaseChangedEvent.new(&"round", 1000).to_dict())
	var beeps: Array[int] = []
	_view.sound_due.connect(
		func(_event: StringName, cue: Dictionary) -> void:
			if cue["id"] == SfxSet.ENGINE_CALL:
				beeps.append(_now)
	)
	var phases: Dictionary[int, float] = {}
	for tick in range(1, 80):
		_now = tick
		_view._process(1.0 / Ticks.RATE)
		phases[tick] = console.call_phase()
	assert_bool(console.calling()).is_true()
	assert_float(console.clock()).is_equal_approx(79.0 / Ticks.RATE, 1e-5)
	assert_int(beeps.size()).is_greater_equal(2)
	for tick: int in beeps:
		assert_float(phases[tick]).override_failure_message("tick %d" % tick).is_less(
			1.0 / Ticks.RATE / ShipEngineHologram.PULSE_SECONDS + 1e-4
		)


func test_the_call_stops_at_the_press_and_a_held_site_blinks_then_shows_fixed() -> void:
	var console := _view.station_looks().console()
	assert_str(console.station_state("socket_e")).is_equal("off")
	assert_str(console.station_state("socket_fw")).is_equal("off")
	_model.fold(&"ButtonPressed", {"station": CONSOLE})
	_view._process(0.05)
	assert_bool(console.calling()).is_false()
	assert_str(console.station_state("socket_e")).is_equal("ok")
	assert_str(console.station_state("socket_fw")).is_equal("ok")
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 600))
	_now = 10
	_view._process(0.05)
	assert_bool(console.calling()).is_false()
	assert_str(console.station_state("socket_e")).is_equal("broken")
	var fast := 1.0 / (2.0 * ShipEngineHologram.BLINK_FAST_SECONDS)
	assert_float(console.station_blink("socket_e")).is_equal_approx(fast, 1e-5)
	assert_float(console.countdown()).is_equal_approx(590.0 / Ticks.RATE, 1e-5)
	assert_str(console.station_state("vent_e")).is_equal("ok")
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_now = 11
	_view._process(0.05)
	assert_str(console.station_state("socket_e")).is_equal("ok")
	assert_float(console.fixed_at("socket_e")).is_equal_approx(11.0 / Ticks.RATE, 1e-5)
	assert_float(console.countdown()).is_equal(-1.0)


func test_a_blast_shows_no_site_fixed() -> void:
	_model.fold(&"ButtonPressed", {"station": CONSOLE})
	var console := _view.station_looks().console()
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 600))
	_now = 10
	_view._process(0.05)
	_model.fold(&"EngineBlast", {"stage": 1})
	_now = 11
	_view._process(0.05)
	assert_float(console.fixed_at("socket_e")).is_equal(ShipConsoleLook.FAR_PAST)


func test_the_order_lights_the_console_lamp_of_its_breaker_a_step_at_a_time() -> void:
	var console := _view.station_looks().console()
	var looks := _view.station_looks()
	var order: Array[int] = [7, 5, 8]
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD_EAST], 900))
	_model.fold(&"BreakerChain", _chain(1, order, 0, -1))
	var step := Ticks.from_seconds(ShipEngineViews.ORDER_STEP_SECONDS)
	for i in order.size():
		_now = i * step
		_view._process(0.05)
		assert_int(console.lit()).is_equal(looks.lamp_of(order[i]))
	_now = order.size() * step
	_view._process(0.05)
	assert_int(console.lit()).is_equal(-1)


func test_the_nearest_deadline_blinks_fast_and_a_later_one_slow() -> void:
	var console := _view.station_looks().console()
	_model.fold(&"ButtonPressed", {"station": CONSOLE})
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD_EAST], 900))
	_model.fold(&"EngineProblemOpened", _opened(2, [SOCKET], 600))
	_now = 10
	_view._process(0.05)
	var fast := 1.0 / (2.0 * ShipEngineHologram.BLINK_FAST_SECONDS)
	var slow := 1.0 / (2.0 * ShipEngineHologram.BLINK_SLOW_SECONDS)
	assert_str(console.station_state("breaker_e")).is_equal("broken")
	assert_float(console.station_blink("socket_e")).is_equal_approx(fast, 1e-5)
	assert_float(console.station_blink("breaker_e")).is_equal_approx(slow, 1e-5)
	_model.fold(&"EngineProblemFixed", {"problem": 2})
	_now = 11
	_view._process(0.05)
	assert_float(console.station_blink("breaker_e")).is_equal_approx(fast, 1e-5)


func test_the_shells_trip_and_the_last_on_ramps_yellow_under_the_beacon() -> void:
	var looks := _view.station_looks()
	var east := looks.board_of(BOARD_EAST)
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD_EAST], 900))
	_model.fold(&"BreakerChain", _chain(1, [5, 6, 7, 8], 2, 99))
	_now = 100
	_view._process(0.1)
	assert_float(east.open_of(looks.shell_of(7))).is_equal_approx(0.4, 1e-4)
	_view._process(0.2)
	assert_float(east.open_of(looks.shell_of(7))).is_equal(1.0)
	assert_float(east.open_of(looks.shell_of(5))).is_equal(0.0)
	assert_int(east.lamp_of(looks.shell_of(5))).is_equal(ShipBoardLook.GREEN)
	assert_int(east.lamp_of(looks.shell_of(6))).is_equal(ShipBoardLook.YELLOW)
	assert_int(east.lamp_of(looks.shell_of(8))).is_equal(ShipBoardLook.DARK)
	assert_bool(east.problem()).is_true()
	assert_bool(looks.board_of(BOARD_WEST).problem()).is_false()
	_model.fold(&"BreakerChain", _chain(1, [5, 6, 7, 8], 4, 100))
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_now = 200
	_view._process(0.4)
	assert_float(east.open_of(looks.shell_of(7))).is_equal(0.0)
	assert_bool(east.problem()).is_false()


func test_the_socket_shows_its_crystal_and_opens_its_claws_while_it_is_out() -> void:
	var socket := _view.station_looks().socket_of(SOCKET)
	assert_str(socket.state()).is_equal("charged")
	assert_float(socket.claws()).is_equal(0.0)
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 600))
	_view._process(0.1)
	assert_str(socket.state()).is_equal("spent")
	_model.fold(&"CrystalChanged", _crystal(-1, CrystalProblem.EMPTY, 7))
	_view._process(0.1)
	assert_str(socket.state()).is_equal("empty")
	assert_float(socket.claws()).is_equal_approx(0.4, 1e-4)
	_view._process(0.2)
	assert_float(socket.claws()).is_equal(1.0)
	_model.fold(&"CrystalChanged", _crystal(-1, CrystalProblem.EMPTY, -1))
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_view._process(0.15)
	assert_str(socket.state()).is_equal("charged")
	assert_float(socket.claws()).is_equal(0.0)


func test_the_charger_shows_the_charge_of_the_crystal_it_holds() -> void:
	var charger := _view.station_looks().charger_of(CHARGER)
	assert_str(charger.state()).is_equal("idle")
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 6000))
	_model.fold(&"CrystalChanged", _crystal(CHARGER, CrystalProblem.LOADED, 7))
	_view._process(0.05)
	assert_str(charger.state()).is_equal("idle")
	var ends := 400
	var charge := _crystals().charge_ticks()
	var fields := _crystal(CHARGER, CrystalProblem.CHARGING, 7)
	fields["tick"] = ends
	_model.fold(&"CrystalChanged", fields)
	_now = ends - charge + Ticks.RATE
	_view._process(0.05)
	assert_str(charger.state()).is_equal("charging")
	assert_float(charger.carrier_rise()).is_equal(1.0)
	assert_float(charger.carrier_turn()).is_equal_approx(
		TAU * ShipStationLooks.CARRIER_TURNS_PER_SECOND, 1e-4
	)
	assert_bool(charger.pressed()).is_true()
	_model.fold(&"CrystalChanged", _crystal(CHARGER, CrystalProblem.WAITING, 7))
	_view._process(0.05)
	assert_str(charger.state()).is_equal("charged")


func test_each_charger_shows_only_the_crystal_it_holds() -> void:
	var looks := _view.station_looks()
	var east := looks.charger_of(CHARGER)
	var west := looks.charger_of(CHARGER_WEST)
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 6000))
	var fields := _crystal(CHARGER, CrystalProblem.CHARGING, 7)
	fields["tick"] = 400
	_model.fold(&"CrystalChanged", fields)
	_now = 400 - _crystals().charge_ticks() + Ticks.RATE
	_view._process(0.05)
	assert_str(east.state()).is_equal("charging")
	assert_str(west.state()).is_equal("idle")
	assert_float(west.carrier_rise()).is_equal(0.0)
	assert_bool(west.pressed()).is_false()
	fields["charger"] = CHARGER_WEST
	_model.fold(&"CrystalChanged", fields)
	_view._process(0.05)
	assert_str(east.state()).is_equal("idle")
	assert_float(east.carrier_rise()).is_equal(0.0)
	assert_bool(east.pressed()).is_false()
	assert_str(west.state()).is_equal("charging")
	assert_bool(west.pressed()).is_true()


func test_a_level_without_devices_keeps_the_stand_ins() -> void:
	var bare: Node3D = auto_free(Node3D.new())
	add_child(bare)
	_view.level = bare
	_view._process(0.0)
	assert_object(_view.station_looks().console()).is_null()
	assert_object(_view.lamp_of(SOCKET)).is_not_null()
	assert_object(_view.mimic_of(FIRST_BREAKER)).is_not_null()
	assert_bool(_view.hologram().visible).is_true()


## The devices as the ship places them by its stations (the console turned to face the mouth).
func _devices() -> Node3D:
	var level: Node3D = auto_free(Node3D.new())
	add_child(level)
	var console: Node3D = CONSOLE_GLB.instantiate()
	console.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.2, 0.6))
	level.add_child(console)
	_add(level, SOCKET_KIT, Vector3(1.5, 0.0, 3.1))
	_add(level, BOARD_KIT, Vector3(6.65, 1.0, -1.0))
	_add(level, BOARD_KIT, Vector3(-6.65, 1.0, -1.0))
	_add(level, CHARGER_KIT, Vector3(10.3, 3.2, 3.0))
	_add(level, CHARGER_KIT, Vector3(-10.3, 3.2, 3.0))
	return level


func _add(level: Node3D, scene: PackedScene, at: Vector3) -> void:
	var device: Node3D = scene.instantiate()
	device.position = at
	level.add_child(device)


func _place() -> void:
	_station(CONSOLE, &"engine_console", Vector3(0.0, 1.2, -0.4))
	_station(GILLS, &"gill_button", Vector3(2.0, 1.2, -3.0))
	_station(BOARD_EAST, &"breaker_board", Vector3(6.5, 1.2, -0.2))
	_station(BOARD_WEST, &"breaker_board", Vector3(-6.5, 1.2, -0.2))
	for i in 8:
		var side := 1.0 if i < 4 else -1.0
		_station(FIRST_BREAKER + i, &"breaker", Vector3(side * (5.8 + 0.5 * (i % 4)), 1.2, -0.2))
	_station(SOCKET, &"cartridge_socket", Vector3(1.5, 1.2, 2.4))
	_station(CHARGER, &"cartridge_charger", Vector3(10.4, 1.2, 1.8))
	_station(CHARGER_WEST, &"cartridge_charger", Vector3(-10.4, 1.2, 1.8))


func _station(id: int, kind: StringName, at: Vector3) -> void:
	_model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)


func _crystals() -> CrystalProblem:
	for kind: ProblemKind in ShipEngineClient.types_of(_mode)[0].kinds:
		if kind is CrystalProblem:
			return kind as CrystalProblem
	return null


func _opened(problem: int, stations: Array[int], deadline: int) -> Dictionary:
	return {"problem": problem, "stations": PackedInt32Array(stations), "deadline": deadline}


func _chain(problem: int, order: Array[int], next: int, since: int) -> Dictionary:
	return {"problem": problem, "breakers": PackedInt32Array(order), "next": next, "since": since}


func _crystal(charger: int, phase: int, item: int) -> Dictionary:
	return {"station": SOCKET, "charger": charger, "phase": phase, "item": item, "tick": -1}
