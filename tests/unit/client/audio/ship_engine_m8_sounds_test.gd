extends GdUnitTestSuite
## ShipEngineSounds' M8 sounds (#1674), on a ClientModel folded from the engine's public events and
## the base mode: a problem fixed sounds the success at its stations (a blast fixes nothing); a gill
## opened or shut again at its button; a breakers chain tripped at its boards, a breaker on, one
## gone off again and the last one on's lamp turning green after the kind's ramp; a crystal laid in
## its charger, charged, fitted back into its socket. Edges only, nothing outside the play phase.

const BASE_MODE := "res://content/modes/base_mode.tres"
const CONSOLE := 1
const GILLS := 2
const BOARD := 3
const SOCKET := 4
const CHARGER := 9
## Breakers 5 to 8 hang by the board.
const FIRST_BREAKER := 5
const CENTRE := Vector3(0.0, 1.9, -0.4)

var _mode: GameMode
var _type: ShipEngine
var _model: ClientModel
var _sounds: ShipEngineSounds
var _now := 0


func before_test() -> void:
	_mode = load(BASE_MODE) as GameMode
	_type = ShipEngineClient.types_of(_mode)[0]
	_model = ClientModel.new(_mode)
	_phase(&"round")
	_station(CONSOLE, &"engine_console", Vector3(0.0, 0.0, -0.4))
	_station(GILLS, &"gill_button", Vector3(2.0, 0.0, -3.0))
	_station(BOARD, &"breaker_board", Vector3(6.5, 0.0, -0.2))
	_station(SOCKET, &"cartridge_socket", Vector3(-4.0, 0.0, 1.0))
	_station(CHARGER, &"cartridge_charger", Vector3(-8.0, 0.0, 3.0))
	for i in 4:
		_station(FIRST_BREAKER + i, &"breaker", Vector3(5.8 + 0.5 * i, 0.0, -0.2))
	_sounds = ShipEngineSounds.new()
	_now = 0
	_due()


func test_a_fixed_problem_sounds_the_success_at_its_stations() -> void:
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS]))
	_due()
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	var cues := _due()
	assert_array(_ids(cues)).contains_exactly([SfxSet.TASK_SUCCESS])
	assert_that(cues[0]["position"]).is_equal(_model.stations[GILLS].position)
	assert_array(_due()).is_empty()


func test_a_blast_fixes_nothing() -> void:
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS]))
	_due()
	_model.fold(&"EngineBlast", {"stage": 1})
	assert_array(_ids(_due())).contains_exactly([SfxSet.ENGINE_BLAST])


func test_a_gill_opens_and_shuts_again_at_its_button() -> void:
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS]))
	_due()
	_model.fold(&"GillFlipped", {"station": GILLS, "slit": 2, "open": true})
	var cues := _due()
	assert_array(_ids(cues)).contains_exactly([SfxSet.ENGINE_GILL_OPEN])
	assert_that(cues[0]["position"]).is_equal(_model.stations[GILLS].position)
	_model.fold(&"GillFlipped", {"station": GILLS, "slit": 2, "open": false})
	assert_array(_ids(_due())).contains_exactly([SfxSet.ENGINE_GILL_SHUT])
	_model.fold(&"GillFlipped", {"station": GILLS, "slit": 0, "open": true})
	_due()
	# A problem opening again at the set shuts its slits with no press: no sound.
	_model.fold(&"EngineProblemOpened", _opened(2, [GILLS]))
	assert_array(_ids(_due())).contains_exactly([SfxSet.ENGINE_WAIL])


func test_the_breakers_trip_switch_on_go_green_and_trip_again() -> void:
	var order: Array[int] = [FIRST_BREAKER + 2, FIRST_BREAKER, FIRST_BREAKER + 3]
	_model.fold(&"EngineProblemOpened", _opened(1, [BOARD]))
	_model.fold(&"BreakerChain", _chain(order, 0, -1))
	var cues := _due()
	assert_array(_ids(cues)).contains_exactly_in_any_order(
		[SfxSet.ENGINE_WAIL, SfxSet.ENGINE_BREAKER_TRIP]
	)
	# The first on, at tick 10.
	_now = 10
	_model.fold(&"BreakerChain", _chain(order, 1, 10))
	cues = _due()
	assert_array(_ids(cues)).contains_exactly([SfxSet.ENGINE_BREAKER_ON])
	assert_that(cues[0]["position"]).is_equal(_model.stations[order[0]].position)
	# Its lamp turns green once the ramp has passed, once.
	var ramp: int = (_type.kinds.filter(_is_breakers)[0] as BreakersProblem).ramp_ticks()
	_now = 10 + ramp - 1
	assert_array(_due()).is_empty()
	_now = 10 + ramp
	cues = _due()
	assert_array(_ids(cues)).contains_exactly([SfxSet.ENGINE_BREAKER_GREEN])
	assert_that(cues[0]["position"]).is_equal(_model.stations[order[0]].position)
	_now += 1
	assert_array(_due()).is_empty()
	# Too late: the chain unwinds, the one on goes off again.
	_model.fold(&"BreakerChain", _chain(order, 0, -1))
	cues = _due()
	assert_array(_ids(cues)).contains_exactly([SfxSet.ENGINE_BREAKER_TRIP])
	assert_that(cues[0]["position"]).is_equal(_model.stations[order[0]].position)


func test_a_crystal_loaded_charged_and_fitted_back() -> void:
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET]))
	_due()
	# The pull and the take are the pick-up's click: no engine sound.
	_model.fold(&"ItemSpawned", {"item": 40, "kind": &"crystal", "position": Vector3.ZERO})
	_model.fold(&"CrystalChanged", _crystal(-1, CrystalProblem.EMPTY, 40))
	assert_array(_due()).is_empty()
	_model.fold(&"CrystalChanged", _crystal(CHARGER, CrystalProblem.LOADED, 40))
	var cues := _due()
	assert_array(_ids(cues)).contains_exactly([SfxSet.ENGINE_CRYSTAL_CHARGER])
	assert_that(cues[0]["position"]).is_equal(_model.stations[CHARGER].position)
	_model.fold(&"CrystalChanged", _crystal(CHARGER, CrystalProblem.CHARGING, 40, 500))
	assert_array(_due()).is_empty()
	_model.fold(&"CrystalChanged", _crystal(CHARGER, CrystalProblem.WAITING, 40))
	assert_array(_ids(_due())).contains_exactly([SfxSet.ENGINE_CHARGED])
	_model.fold(&"CrystalChanged", _crystal(-1, CrystalProblem.EMPTY, 40))
	assert_array(_due()).is_empty()
	_model.fold(&"CrystalChanged", _crystal(-1, CrystalProblem.EMPTY, -1))
	cues = _due()
	assert_array(_ids(cues)).contains_exactly([SfxSet.ENGINE_CRYSTAL_SOCKET])
	assert_that(cues[0]["position"]).is_equal(_model.stations[SOCKET].position)


func test_a_blast_returning_the_crystal_is_no_fit() -> void:
	_model.fold(&"EngineProblemOpened", _opened(1, [SOCKET]))
	_model.fold(&"ItemSpawned", {"item": 40, "kind": &"crystal", "position": Vector3.ZERO})
	_model.fold(&"CrystalChanged", _crystal(-1, CrystalProblem.EMPTY, 40))
	_due()
	_model.fold(&"EngineBlast", {"stage": 1})
	_model.fold(&"CrystalChanged", _crystal(-1, CrystalProblem.EMPTY, -1))
	assert_array(_ids(_due())).contains_exactly([SfxSet.ENGINE_BLAST])


func test_nothing_sounds_outside_the_play_phase() -> void:
	_model.fold(&"EngineProblemOpened", _opened(1, [GILLS]))
	_due()
	_phase(&"end")
	_model.fold(&"GillFlipped", {"station": GILLS, "slit": 1, "open": true})
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	assert_array(_due()).is_empty()


## The cues due now but the order's beeps, which keep the hologram's clock
## (ship_engine_sounds_test.gd).
func _due() -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	for cue: Dictionary in _sounds.due(_model, CONSOLE, CENTRE, _now, false, _type):
		if cue["id"] != SfxSet.ENGINE_BEEP:
			cues.append(cue)
	return cues


static func _ids(cues: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for cue: Dictionary in cues:
		ids.append(cue["id"] as StringName)
	return ids


static func _is_breakers(kind: ProblemKind) -> bool:
	return kind is BreakersProblem


func _phase(id: StringName) -> void:
	_model.fold(&"PhaseChanged", PhaseChangedEvent.new(id, 1000).to_dict())


func _station(id: int, kind: StringName, at: Vector3) -> void:
	_model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)


func _opened(problem: int, stations: Array[int]) -> Dictionary:
	return {"problem": problem, "stations": PackedInt32Array(stations), "deadline": 6000}


func _chain(order: Array[int], next: int, since: int) -> Dictionary:
	return {"problem": 1, "breakers": PackedInt32Array(order), "next": next, "since": since}


func _crystal(charger: int, phase: int, item: int, tick := -1) -> Dictionary:
	return {"station": SOCKET, "charger": charger, "phase": phase, "item": item, "tick": tick}
