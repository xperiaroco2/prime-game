extends GdUnitTestSuite
## The ship engine's stand-in views (#1462; ARCHITECTURE §9.5.27 "For part 3's client", §4.7.59),
## driven from a ClientModel folded from the engine's events, the base mode's engine and a host
## tick the test sets: the console's stage strips, a red lamp over each station of an open problem,
## the breakers' lamps and the mimic board, where alone the order plays, the gill sets' slits and
## white bar, a charger's lamp and the blast; the hologram made readable (#1500, GDD §8): the call,
## the turbines' spin, a point and a line per site station, the blink, the flash, the countdown and
## the ring; the gills' steam and mist. And ShipEngineClient offers no breaker board.

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
	# Then a dark pause, so the loop's start can be told (7, 11, 5, 7 reads as no order), and again.
	for i in range(order.size(), order.size() + ShipEngineViews.ORDER_PAUSE_STEPS):
		for at: int in [i * step, (i + 1) * step - 1]:
			_now = at
			_view._process(0.0)
			for breaker: int in order:
				(
					assert_object(ShipEngineViews.colour_of(_view.mimic_of(breaker)))
					. override_failure_message("tick %d, %d" % [at, breaker])
					. is_equal(ShipEngineViews.RED)
				)
	_now = (order.size() + ShipEngineViews.ORDER_PAUSE_STEPS) * step
	_view._process(0.0)
	assert_object(ShipEngineViews.colour_of(_view.mimic_of(order[0]))).is_equal(
		ShipEngineViews.WHITE
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


func test_a_mimic_lamp_is_red_tripped_and_green_once_on_never_yellow() -> void:
	_place()
	var order: Array[int] = [5, 6, 7]
	# A tick in the order's dark pause, with breaker 6 the last one on and still in its ramp.
	var step := maxi(1, Ticks.from_seconds(ShipEngineViews.ORDER_STEP_SECONDS))
	var pause := order.size() * step
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD_EAST], 900))
	_model.fold(&"BreakerChain", _chain(1, order, 2, pause - 1))
	_now = pause
	_view._process(0.0)
	assert_object(ShipEngineViews.colour_of(_view.lamp_of(6))).is_equal(ShipEngineViews.YELLOW)
	assert_object(ShipEngineViews.colour_of(_view.mimic_of(5))).is_equal(ShipEngineViews.GREEN)
	assert_object(ShipEngineViews.colour_of(_view.mimic_of(6))).is_equal(ShipEngineViews.GREEN)
	assert_object(ShipEngineViews.colour_of(_view.mimic_of(7))).is_equal(ShipEngineViews.RED)


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


func test_the_strips_are_the_engine_s_task_state_total_of_stages() -> void:
	_place()
	_view._process(0.0)
	var engine: ShipEngine = ShipEngineClient.types_of(_mode)[0]
	_model.fold(&"TaskState", {"task": 9, "type": engine.id, "done": 0, "total": 4})
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 300, "needed": 600, "counting": false, "tick": 0}
	)
	_view._process(0.0)
	# Half the bar is two of four stages: the first two full, the others empty.
	assert_object(_view.strip_fill(3)).is_not_null()
	assert_object(_view.strip_fill(4)).is_null()
	assert_float(_view.strip_fill(1).scale.x).is_equal_approx(1.0, 1e-4)
	assert_bool(_view.strip_fill(2).visible).is_false()


func test_the_hologram_stands_at_the_level_s_point_else_over_the_console_s_use_spot() -> void:
	_place()
	_view._process(0.0)
	# The middle strip stands centred a quarter metre over the hologram's centre.
	var lift := Vector3.UP * 0.25
	var over_spot := Vector3(0.0, 1.2, -0.4) + Vector3.UP * ShipEngineViews.HOLOGRAM_LIFT_M
	assert_vector(_view._strip_at[1]).is_equal_approx(over_spot + lift, Vector3.ONE * 1e-4)
	var level := _level()
	var point := Node3D.new()
	point.add_to_group(&"engine_hologram", true)
	point.position = Vector3(0.0, 2.9, 0.6)
	level.add_child(point)
	_view.level = level
	_view._process(0.0)
	assert_vector(_view._strip_at[1]).is_equal_approx(point.position + lift, Vector3.ONE * 1e-4)


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
	# Tick by tick the bar is the host's own (GillsProblem.bar_slit), so a press by it is taken.
	var host := EngineProblem.new(1, kind, PackedInt32Array([GILLS]), opened, deadline, 1)
	for tick in range(opened - 2, opened + kind.step_ticks() * (GillsProblem.BAR.size() + 1)):
		_now = tick
		_view._process(0.0)
		var lit := kind.bar_slit(host, tick) + 1
		for slit in range(1, 6):
			(
				assert_bool((gills.get_node("Light%d" % slit) as Node3D).visible)
				. override_failure_message("tick %d, slit %d" % [tick, slit])
				. is_equal(slit == lit)
			)


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


func test_a_view_built_again_after_a_blast_plays_no_old_blast() -> void:
	_place()
	_view._process(0.0)
	_model.fold(&"EngineBlast", {"stage": 1})
	_view._process(0.1)
	_view._process(ShipEngineViews.BLAST_SECONDS)
	# A new level clears the view, and it is built again from the same book.
	_view.level = _level()
	_view._process(0.1)
	assert_object(_blast()).is_null()


func test_a_view_first_built_after_a_blast_plays_none() -> void:
	_model.fold(&"EngineBlast", {"stage": 1})
	_place()
	_view._process(0.1)
	assert_object(_blast()).is_null()


func test_the_client_offers_no_breaker_board_but_its_breakers() -> void:
	_place()
	var client := ShipEngineClient.new()
	var engine: ShipEngine = ShipEngineClient.types_of(_mode)[0]
	assert_bool(client.usable(_model, engine, BOARD_EAST)).is_false()
	assert_bool(client.usable(_model, engine, FIRST_BREAKER)).is_true()
	assert_bool(client.usable(_model, engine, CONSOLE)).is_true()
	assert_bool(client.usable(_model, engine, GILLS)).is_true()


func test_the_ship_calls_while_the_engine_is_off() -> void:
	_place()
	_view._process(0.0)
	var hologram := _view.hologram()
	assert_bool(hologram.called()).is_true()
	assert_object(_colour(hologram.turbine(0))).is_equal(ShipEngineHologram.ORANGE_DIM)
	assert_bool(hologram.button().visible).is_true()
	assert_object(_colour(hologram.button())).is_equal(ShipEngineHologram.ORANGE)
	# The turbines pulse with the host tick, orange at the pulse's peak, and stand still.
	_now = Ticks.from_seconds(ShipEngineHologram.PULSE_SECONDS / 2.0)
	var still := hologram.turbine(0).rotation.y
	_view._process(0.5)
	for i in 2:
		(
			assert_bool(_colour(hologram.turbine(i)).is_equal_approx(ShipEngineHologram.ORANGE))
			. is_true()
		)
	assert_float(hologram.turbine_speed()).is_equal(0.0)
	assert_float(hologram.turbine(0).rotation.y).is_equal(still)
	# Pressed: no call, the button out, the turbines the hologram's cyan.
	_model.fold(&"ButtonPressed", {"station": CONSOLE})
	_view._process(0.0)
	assert_bool(hologram.called()).is_false()
	assert_bool(hologram.button().visible).is_false()
	assert_object(_colour(hologram.turbine(0))).is_equal(ShipEngineViews.CYAN)


func test_a_started_engine_does_not_call_to_one_who_never_saw_the_press() -> void:
	_place()
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 0, "needed": 600, "counting": true, "tick": 0}
	)
	_view._process(0.0)
	assert_bool(_view.hologram().called()).is_false()
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 120, "needed": 600, "counting": false, "tick": 0}
	)
	_view._process(0.0)
	assert_bool(_view.hologram().called()).is_false()
	assert_bool(_view.hologram().button().visible).is_false()


func test_an_open_problem_stops_the_call_for_an_idle_unpressed_console() -> void:
	_place()
	# A client that joined a started engine, right after a stage-1 blast: the bar is empty and
	# still, no press seen, and a problem is already open.
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 0, "needed": 600, "counting": false, "tick": 0}
	)
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 600))
	_view._process(0.0)
	var hologram := _view.hologram()
	assert_bool(hologram.called()).is_false()
	assert_bool(hologram.button().visible).is_false()
	assert_float(hologram.turbine_speed()).is_equal(
		ShipEngineHologram.SPIN_RAD_PER_SECOND * ShipEngineHologram.SLOW_FACTOR
	)


func test_the_start_button_sits_under_the_centre_toward_the_use_spot() -> void:
	_place()
	var level := _level()
	var marker := Node3D.new()
	marker.add_to_group(&"engine_hologram", true)
	level.add_child(marker)
	marker.global_position = Vector3(3.0, 3.0, -0.4)
	_view.level = level
	_view._process(0.0)
	# The console's use spot is 3 m west of the centre, at the same depth.
	var expected := (
		marker.global_position
		+ Vector3.DOWN * ShipEngineHologram.BUTTON_DROP_M
		+ Vector3.LEFT * ShipEngineHologram.BUTTON_TOWARD_M
	)
	assert_vector(_view.hologram().button().global_position).is_equal_approx(
		expected, Vector3.ONE * 1e-4
	)


func test_the_turbines_spin_once_started_and_slower_while_a_problem_is_open() -> void:
	_place()
	_model.fold(&"ButtonPressed", {"station": CONSOLE})
	_view._process(0.0)
	var hologram := _view.hologram()
	var full := ShipEngineHologram.SPIN_RAD_PER_SECOND
	assert_float(hologram.turbine_speed()).is_equal(full)
	var from := hologram.turbine(1).rotation.y
	_view._process(0.1)
	assert_float(hologram.turbine(1).rotation.y).is_equal_approx(from + full * 0.1, 1e-4)
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 600))
	_view._process(0.0)
	assert_float(hologram.turbine_speed()).is_less(full)
	assert_float(hologram.turbine_speed()).is_equal(full * ShipEngineHologram.SLOW_FACTOR)
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_view._process(0.0)
	assert_float(hologram.turbine_speed()).is_equal(full)


func test_every_site_station_is_a_point_with_a_line_and_all_points_look_alike() -> void:
	_place()
	_view._process(0.0)
	var hologram := _view.hologram()
	for site: int in [GILLS, BOARD_EAST, BOARD_WEST, SOCKET]:
		var point := hologram.point_of(site)
		assert_object(point).override_failure_message("site %d" % site).is_not_null()
		assert_object(_colour(point)).is_equal(ShipEngineViews.WHITE)
		assert_object((point.mesh as BoxMesh).size).is_equal(
			(hologram.point_of(SOCKET).mesh as BoxMesh).size
		)
		assert_object(_colour(hologram.line_of(site))).is_equal(ShipEngineHologram.LINE)
	for other: int in [CONSOLE, FIRST_BREAKER, CHARGER]:
		assert_object(hologram.point_of(other)).is_null()
	# A point stands where the mimic board would put it, a little over it.
	var centre := Vector3(0.0, 1.2, -0.4) + Vector3.UP * ShipEngineViews.HOLOGRAM_LIFT_M
	var at := Vector3(1.5, 0.0, 2.8) * ShipEngineViews.MIMIC_SCALE
	var lift := Vector3.UP * ShipEngineHologram.POINT_LIFT_M
	assert_vector(hologram.point_of(SOCKET).position).is_equal_approx(
		centre + at + lift, Vector3.ONE * 1e-4
	)
	# Its line runs from the point to the turbine on its side.
	var line := hologram.line_of(SOCKET)
	var to := hologram.turbine(1).position
	assert_vector(line.position).is_equal_approx(
		(hologram.point_of(SOCKET).position + to) / 2.0, Vector3.ONE * 1e-4
	)
	assert_float(line.basis.z.length()).is_equal_approx(
		hologram.point_of(SOCKET).position.distance_to(to), 1e-4
	)


func test_a_held_station_blinks_red_and_its_line_goes_dark() -> void:
	_place()
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 600))
	_view._process(0.0)
	var hologram := _view.hologram()
	var step := Ticks.from_seconds(ShipEngineHologram.BLINK_FAST_SECONDS)
	for at: int in [0, step - 1, step, 2 * step - 1, 2 * step]:
		_now = at
		_view._process(0.0)
		@warning_ignore("integer_division")
		var expected := ShipEngineViews.RED if (at / step) % 2 == 0 else ShipEngineViews.DARK
		(
			assert_object(_colour(hologram.point_of(SOCKET)))
			. override_failure_message("tick %d" % at)
			. is_equal(expected)
		)
		assert_object(_colour(hologram.line_of(SOCKET))).is_equal(ShipEngineViews.DARK)
		assert_object(_colour(hologram.line_of(GILLS))).is_equal(ShipEngineHologram.LINE)
		assert_object(_colour(hologram.point_of(GILLS))).is_equal(ShipEngineViews.WHITE)


func test_a_fixed_station_s_line_flashes_back_and_a_blast_flashes_none() -> void:
	_place()
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 600))
	_view._process(0.0)
	var hologram := _view.hologram()
	var thin := hologram.line_of(SOCKET).basis.x.length()
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_view._process(0.1)
	assert_object(_colour(hologram.line_of(SOCKET))).is_equal(ShipEngineViews.WHITE)
	assert_float(hologram.line_of(SOCKET).basis.x.length()).is_equal_approx(
		thin * ShipEngineHologram.FLASH_THICKER, 1e-4
	)
	assert_object(_colour(hologram.point_of(SOCKET))).is_equal(ShipEngineViews.WHITE)
	_view._process(ShipEngineHologram.FLASH_SECONDS)
	assert_object(_colour(hologram.line_of(SOCKET))).is_equal(ShipEngineHologram.LINE)
	assert_float(hologram.line_of(SOCKET).basis.x.length()).is_equal_approx(thin, 1e-4)
	# A blast takes the problem away unfixed: its line comes back with no flash.
	_model.fold(&"EngineProblemOpened", _opened(2, [SOCKET], 900))
	_view._process(0.0)
	_model.fold(&"EngineBlast", {"stage": 1})
	_view._process(0.0)
	assert_object(_colour(hologram.line_of(SOCKET))).is_equal(ShipEngineHologram.LINE)


func test_the_problem_that_blows_first_blinks_fastest() -> void:
	_place()
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 900))
	_model.fold(&"EngineProblemOpened", _opened(2, [GILLS], 600))
	var fast := Ticks.from_seconds(ShipEngineHologram.BLINK_FAST_SECONDS)
	var slow := Ticks.from_seconds(ShipEngineHologram.BLINK_SLOW_SECONDS)
	assert_int(fast).is_less(slow)
	_now = fast
	_view._process(0.0)
	var hologram := _view.hologram()
	assert_object(_colour(hologram.point_of(GILLS))).is_equal(ShipEngineViews.DARK)
	assert_object(_colour(hologram.point_of(SOCKET))).is_equal(ShipEngineViews.RED)
	_now = slow
	_view._process(0.0)
	assert_object(_colour(hologram.point_of(SOCKET))).is_equal(ShipEngineViews.DARK)
	# Fixed the first, the other is the nearest and blinks fast.
	_model.fold(&"EngineProblemFixed", {"problem": 2})
	_now = fast
	_view._process(0.0)
	assert_object(_colour(hologram.point_of(SOCKET))).is_equal(ShipEngineViews.DARK)


func test_the_countdown_shows_the_seconds_to_the_nearest_deadline() -> void:
	_place()
	_view._process(0.0)
	var countdown := _view.hologram().countdown()
	assert_bool(countdown.visible).is_false()
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET], 900))
	_model.fold(&"EngineProblemOpened", _opened(2, [GILLS], 600))
	_now = 100
	_view._process(0.0)
	assert_bool(countdown.visible).is_true()
	assert_str(countdown.text).is_equal("25")
	_now = 101
	_view._process(0.0)
	assert_str(countdown.text).is_equal("25")
	_model.fold(&"EngineProblemFixed", {"problem": 2})
	_view._process(0.0)
	assert_str(countdown.text).is_equal("40")
	_now = 1000
	_view._process(0.0)
	assert_str(countdown.text).is_equal("0")
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_view._process(0.0)
	assert_bool(countdown.visible).is_false()


func test_the_ring_round_the_disc_runs_with_the_strips_bar() -> void:
	_place()
	_view._process(0.0)
	var hologram := _view.hologram()
	assert_int(hologram.ring_lit()).is_equal(0)
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 300, "needed": 600, "counting": false, "tick": 0}
	)
	_view._process(0.0)
	assert_int(hologram.ring_lit()).is_equal(ShipEngineHologram.RING_SEGMENTS / 2)
	assert_bool(_view.strip_fill(2).visible).is_false()
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 600, "needed": 600, "counting": false, "tick": 0}
	)
	_view._process(0.0)
	assert_int(hologram.ring_lit()).is_equal(ShipEngineHologram.RING_SEGMENTS)
	assert_int(ShipEngineHologram.ring_lit_for(0.999)).is_equal(
		ShipEngineHologram.RING_SEGMENTS - 1
	)


func test_a_slit_opened_puffs_steam_and_all_five_open_leave_a_mist() -> void:
	_place()
	var level := _level()
	var gills := level.get_child(0) as Node3D
	(gills.get_node("Slit2") as Node3D).position = Vector3(1.0, 2.0, -4.0)
	_view.level = level
	_view._process(0.0)
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS], 600))
	_view._process(0.0)
	assert_int(_view.steam().size()).is_equal(0)
	_model.fold(&"GillFlipped", {"station": GILLS, "slit": 1, "open": true})
	_view._process(0.0)
	assert_int(_view.steam().size()).is_equal(1)
	assert_vector(_view.steam()[0].global_position).is_equal_approx(
		Vector3(1.0, 2.0, -4.0), Vector3.ONE * 1e-4
	)
	# Half-way through its life the puff has risen half its rise and swelled.
	_view._process(ShipEngineViews.STEAM_SECONDS / 2.0)
	assert_float(_view.steam()[0].global_position.y).is_equal_approx(
		2.0 + ShipEngineViews.STEAM_RISE_M / 2.0, 1e-4
	)
	assert_float(_view.steam()[0].scale.x).is_greater(0.1)
	_view._process(ShipEngineViews.STEAM_SECONDS)
	assert_int(_view.steam().size()).is_equal(0)
	# Shut again: no puff.
	_model.fold(&"GillFlipped", {"station": GILLS, "slit": 1, "open": false})
	_view._process(0.0)
	assert_int(_view.steam().size()).is_equal(0)
	for slit in 4:
		_model.fold(&"GillFlipped", {"station": GILLS, "slit": slit, "open": true})
		_view._process(0.0)
	assert_int(_view.steam().size()).is_equal(4)
	assert_int(_view.mist().size()).is_equal(0)
	# The fifth opens the last slit and fixes it in one frame: its puff and the mist.
	_model.fold(&"GillFlipped", {"station": GILLS, "slit": 4, "open": true})
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_view._process(0.0)
	assert_int(_view.steam().size()).is_equal(5)
	assert_int(_view.mist().size()).is_equal(1)
	# The cloud stands at the middle of the five slits, not at the gill set's own place.
	var middle := Vector3.ZERO
	for slit in range(1, 6):
		middle += (gills.get_node("Slit%d" % slit) as Node3D).global_position / 5.0
	assert_vector(_view.mist()[0].global_position).is_equal_approx(middle, Vector3.ONE * 1e-4)
	assert_float(middle.distance_to(gills.global_position)).is_greater(0.1)
	_view._process(ShipEngineViews.MIST_SECONDS)
	assert_int(_view.steam().size()).is_equal(0)
	assert_int(_view.mist().size()).is_equal(0)
	# The vapour is none of the blast's sphere.
	assert_object(_blast()).is_null()


func test_a_view_built_again_or_a_blast_plays_no_steam_or_mist() -> void:
	_place()
	var level := _level()
	_view.level = level
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS], 600))
	_view._process(0.0)
	for slit in 2:
		_model.fold(&"GillFlipped", {"station": GILLS, "slit": slit, "open": true})
	# Built again (a new level) with two slits open and the problem holding: no puff replays.
	_view.level = level
	_view._process(0.0)
	assert_int(_view.steam().size()).is_equal(0)
	for slit in range(2, 5):
		_model.fold(&"GillFlipped", {"station": GILLS, "slit": slit, "open": true})
	# Built again after the last slits opened and the fix: no puff and no mist.
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_view.level = level
	_view._process(0.0)
	assert_int(_view.steam().size()).is_equal(0)
	assert_int(_view.mist().size()).is_equal(0)
	# A blast takes an all-open problem away unfixed: no mist.
	_model.fold(&"EngineProblemOpened", _opened(2, [GILLS], 900))
	_view._process(0.0)
	for slit in 5:
		_model.fold(&"GillFlipped", {"station": GILLS, "slit": slit, "open": true})
	_model.fold(&"EngineBlast", {"stage": 1})
	_view._process(0.0)
	assert_int(_view.steam().size()).is_equal(0)
	assert_int(_view.mist().size()).is_equal(0)


func _colour(part: MeshInstance3D) -> Color:
	return ShipEngineViews.colour_of(part)


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
		if child.is_queued_for_deletion():
			continue
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
