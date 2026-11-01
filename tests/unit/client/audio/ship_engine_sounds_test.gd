extends GdUnitTestSuite
## ShipEngineSounds (#1501; GDD §8; ARCHITECTURE §4.7.64), on a ClientModel folded from the
## engine's public events and the base mode: each engine event maps to its sound at its place
## (the call at each pulse while the ship calls, a beep at each lamp of the order, a wail at each
## station of a new problem, the blast and the roar at the console, heard farther), edges only
## (nothing at the first frame, nothing twice) and nothing outside the play phase; a KnockedDown
## zaps only by a tripped breaker still off.

const BASE_MODE := "res://content/modes/base_mode.tres"
const CONSOLE := 1
const GILLS := 2
const BOARD := 3
## Breakers 5 to 8 hang by the board.
const FIRST_BREAKER := 5
const CONSOLE_AT := Vector3(0.0, 0.0, -0.4)
const GILLS_AT := Vector3(2.0, 0.0, -3.0)
const CENTRE := Vector3(0.0, 1.9, -0.4)

var _mode: GameMode
var _model: ClientModel
var _sounds: ShipEngineSounds
var _now := 0


func before_test() -> void:
	_mode = load(BASE_MODE) as GameMode
	_model = ClientModel.new(_mode)
	_phase(&"round")
	_station(CONSOLE, &"engine_console", CONSOLE_AT)
	_station(GILLS, &"gill_button", GILLS_AT)
	_station(BOARD, &"breaker_board", Vector3(6.5, 0.0, -0.2))
	for i in 4:
		_station(FIRST_BREAKER + i, &"breaker", Vector3(5.8 + 0.5 * i, 0.0, -0.2))
	_sounds = ShipEngineSounds.new()
	_now = 0


func test_the_first_frame_seeds_and_plays_nothing() -> void:
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS]))
	_model.fold(&"EngineBlast", {"stage": 1})
	_model.fold(&"EngineProblemOpened", _opened(2, [GILLS]))
	assert_array(_due(true)).is_empty()
	assert_array(_due(false)).is_empty()


func test_the_ship_calls_at_each_pulse_while_the_engine_is_off() -> void:
	assert_array(_due(true)).is_empty()
	var pulse := Ticks.from_seconds(ShipEngineHologram.PULSE_SECONDS)
	var calls := 0
	for frame in range(1, 4 * pulse + 1):
		_now = frame
		for cue: Dictionary in _due(true):
			assert_str(str(cue["id"])).is_equal(String(SfxSet.ENGINE_CALL))
			assert_object(cue["position"]).is_equal(CENTRE)
			calls += 1
	assert_int(calls).is_equal(4)
	# Pressed: the hologram no longer calls, so neither does its sound.
	for frame in range(4 * pulse + 1, 8 * pulse):
		_now = frame
		assert_array(_due(false)).is_empty()


func test_a_new_problem_wails_once_at_each_of_its_stations() -> void:
	_due(false)
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS, BOARD]))
	var cues := _due(false)
	assert_int(cues.size()).is_equal(2)
	for cue: Dictionary in cues:
		assert_str(str(cue["id"])).is_equal(String(SfxSet.ENGINE_WAIL))
	assert_object(cues[0]["position"]).is_equal(GILLS_AT)
	assert_object(cues[1]["position"]).is_equal(_model.stations[BOARD].position)
	assert_array(_due(false)).is_empty()
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	assert_array(_due(false)).is_empty()


func test_the_order_beeps_at_each_lit_lamp_and_never_in_its_pause() -> void:
	_due(false)
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD]))
	_model.fold(&"BreakerChain", _chain(1, [FIRST_BREAKER, FIRST_BREAKER + 2], 0))
	_due(false)
	var step := Ticks.from_seconds(ShipEngineViews.ORDER_STEP_SECONDS)
	var cycle := 2 + ShipEngineViews.ORDER_PAUSE_STEPS
	var beeps := 0
	for frame in range(1, 2 * cycle * step + 1):
		_now = frame
		for cue: Dictionary in _due(false):
			assert_str(str(cue["id"])).is_equal(String(SfxSet.ENGINE_BEEP))
			assert_object(cue["position"]).is_equal(CENTRE)
			@warning_ignore("integer_division")
			assert_int((frame / step) % cycle).is_less(2)
			beeps += 1
	# Steps 1 to 8 of a 4-step cycle (two lamps, two dark): lamps at steps 1, 4, 5 and 8; step 0, the
	# first lamp at tick 0, was seen at the open, not after it.
	assert_int(beeps).is_equal(4)
	# Fixed: no order, no beep.
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	for frame in range(2 * cycle * step + 1, 4 * cycle * step):
		_now = frame
		assert_array(_due(false)).is_empty()


func test_two_open_orders_beep_once_per_lamp_not_twice_on_top() -> void:
	_due(false)
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD]))
	_model.fold(&"BreakerChain", _chain(1, [FIRST_BREAKER, FIRST_BREAKER + 2], 0))
	_model.fold(&"EngineProblemOpened", _opened(2, [BOARD]))
	_model.fold(&"BreakerChain", _chain(2, [FIRST_BREAKER + 1, FIRST_BREAKER + 3], 0))
	_due(false)
	var step := Ticks.from_seconds(ShipEngineViews.ORDER_STEP_SECONDS)
	var cycle := 2 + ShipEngineViews.ORDER_PAUSE_STEPS
	var beeps := 0
	for frame in range(1, 2 * cycle * step + 1):
		_now = frame
		var cues := _due(false)
		assert_int(cues.size()).is_less_equal(1)
		beeps += cues.size()
	# The same four lamps as one order's (steps 1, 4, 5 and 8).
	assert_int(beeps).is_equal(4)


func test_a_blast_sounds_once_at_the_console_and_carries_far() -> void:
	_due(false)
	_model.fold(&"EngineBlast", {"stage": 1})
	var cues := _due(false)
	assert_int(cues.size()).is_equal(1)
	assert_str(str(cues[0]["id"])).is_equal(String(SfxSet.ENGINE_BLAST))
	assert_object(cues[0]["position"]).is_equal(CONSOLE_AT + Vector3.UP)
	assert_array(_due(false)).is_empty()
	assert_float(ShipEngineSounds.range_of(SfxSet.ENGINE_BLAST)).is_greater(
		SoundChooser.HEARING_RANGE_M
	)


func test_the_bar_full_roars_once_at_the_console_and_carries_far() -> void:
	_due(false)
	_zone(300, 600)
	assert_array(_due(false)).is_empty()
	_zone(600, 600)
	var cues := _due(false)
	assert_int(cues.size()).is_equal(1)
	assert_str(str(cues[0]["id"])).is_equal(String(SfxSet.ENGINE_ROAR))
	assert_object(cues[0]["position"]).is_equal(CONSOLE_AT + Vector3.UP)
	assert_array(_due(false)).is_empty()
	assert_float(ShipEngineSounds.range_of(SfxSet.ENGINE_ROAR)).is_greater(
		SoundChooser.HEARING_RANGE_M
	)
	for id: StringName in [
		SfxSet.ENGINE_CALL, SfxSet.ENGINE_BEEP, SfxSet.ENGINE_WAIL, SfxSet.ENGINE_ZAP
	]:
		assert_float(ShipEngineSounds.range_of(id)).is_equal(SoundChooser.HEARING_RANGE_M)


func test_an_engine_done_before_the_first_frame_never_roars() -> void:
	_zone(600, 600)
	assert_array(_due(false)).is_empty()
	assert_array(_due(false)).is_empty()


func test_nothing_sounds_outside_the_play_phase() -> void:
	_phase(&"pregame")
	_due(true)
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS]))
	_model.fold(&"EngineBlast", {"stage": 1})
	_zone(600, 600)
	for frame in range(1, 3 * Ticks.from_seconds(ShipEngineHologram.PULSE_SECONDS)):
		_now = frame
		assert_array(_due(true)).is_empty()


func test_the_engine_that_ends_the_round_still_roars_in_that_frame() -> void:
	_due(false)
	# The last stage ends the round in the same tick: both fold before one frame.
	_zone(600, 600)
	_phase(&"end")
	var cues := _due(false)
	assert_int(cues.size()).is_equal(1)
	assert_str(str(cues[0]["id"])).is_equal(String(SfxSet.ENGINE_ROAR))
	# The next frames are outside play: silent.
	_model.fold(&"EngineBlast", {"stage": 1})
	assert_array(_due(false)).is_empty()
	assert_array(_due(false)).is_empty()


func test_a_knockdown_by_a_tripped_breaker_still_off_zaps_there() -> void:
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD]))
	_model.fold(&"BreakerChain", _chain(1, [FIRST_BREAKER, FIRST_BREAKER + 3], 1))
	var by_last := _model.stations[FIRST_BREAKER + 3].position + Vector3(0.3, 0.0, 1.0)
	var zapped: Variant = ShipEngineSounds.zap_at(_knocked(by_last), _model, _mode)
	assert_object(zapped).is_equal(_model.stations[FIRST_BREAKER + 3].position)


func test_any_other_knockdown_zaps_nowhere() -> void:
	var by_breaker := _model.stations[FIRST_BREAKER].position + Vector3(0.0, 0.0, 1.0)
	# No problem open: a hit at the board.
	assert_object(ShipEngineSounds.zap_at(_knocked(by_breaker), _model, _mode)).is_null()
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD]))
	_model.fold(&"BreakerChain", _chain(1, [FIRST_BREAKER, FIRST_BREAKER + 3], 1))
	# The first is on already: a knockdown by it alone is no short circuit.
	var far := _model.stations[FIRST_BREAKER].position + Vector3(-2.0, 0.0, 0.0)
	assert_object(ShipEngineSounds.zap_at(_knocked(far), _model, _mode)).is_null()
	# Far from every board, and with no mode.
	assert_object(ShipEngineSounds.zap_at(_knocked(GILLS_AT), _model, _mode)).is_null()
	var near := _model.stations[FIRST_BREAKER + 3].position
	assert_object(ShipEngineSounds.zap_at(_knocked(near), _model, null)).is_null()
	# A blast takes every problem away before its knockdowns arrive.
	_model.fold(&"EngineBlast", {"stage": 1})
	assert_object(ShipEngineSounds.zap_at(_knocked(near), _model, _mode)).is_null()


func _due(calling: bool) -> Array[Dictionary]:
	return _sounds.due(_model, CONSOLE, CENTRE, _now, calling)


func _phase(id: StringName) -> void:
	_model.fold(&"PhaseChanged", PhaseChangedEvent.new(id, 1000).to_dict())


func _station(id: int, kind: StringName, at: Vector3) -> void:
	_model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)


func _zone(ticks: int, needed: int) -> void:
	_model.fold(
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": ticks, "needed": needed, "counting": false, "tick": _now}
	)


func _knocked(at: Vector3) -> Dictionary:
	return {"peer": 2, "position": at}


func _opened(problem: int, stations: Array[int]) -> Dictionary:
	return {"problem": problem, "stations": PackedInt32Array(stations), "deadline": 6000}


func _chain(problem: int, order: Array[int], next: int) -> Dictionary:
	var since := 0 if next > 0 else -1
	return {"problem": problem, "breakers": PackedInt32Array(order), "next": next, "since": since}
