extends GdUnitTestSuite
## The ship engine's events folded into the own ClientModel (#1462; ARCHITECTURE §9.5.27, "For part
## 3's client"): ClientEngineBook keeps the open problems until fixed or blasted, each problem's
## last BreakerChain, each gill set's slits since its problem opened and each socket's crystal;
## ClientModel.fold hands it every event and a new match starts it afresh.


func test_a_problem_is_open_from_its_opening_until_it_is_fixed() -> void:
	var model := ClientModel.new(FixtureBaseMode.mode())
	model.fold(&"EngineProblemOpened", _opened(1, [4], 300))
	model.fold(&"EngineProblemOpened", _opened(2, [6, 7], 400))
	assert_array(model.engine.problems.keys()).contains_exactly([1, 2])
	assert_int(model.engine.problem_at(7).deadline).is_equal(400)
	assert_object(model.engine.problem_at(5)).is_null()
	model.fold(&"EngineProblemFixed", {"problem": 1})
	assert_object(model.engine.problem_at(4)).is_null()
	assert_array(model.engine.problems.keys()).contains_exactly([2])


func test_a_blast_ends_every_open_problem_and_counts() -> void:
	var model := ClientModel.new(FixtureBaseMode.mode())
	model.fold(&"EngineProblemOpened", _opened(1, [4], 300))
	model.fold(&"EngineProblemOpened", _opened(2, [6], 300))
	model.fold(&"EngineBlast", {"stage": 1})
	assert_bool(model.engine.problems.is_empty()).is_true()
	assert_int(model.engine.blasts).is_equal(1)
	assert_int(model.engine.stage).is_equal(1)


func test_the_breakers_chain_is_the_problem_s_last() -> void:
	var model := ClientModel.new(FixtureBaseMode.mode())
	model.fold(&"EngineProblemOpened", _opened(3, [10, 11], 900))
	model.fold(&"BreakerChain", _chain(3, [14, 12, 17], 0, -1))
	model.fold(&"BreakerChain", _chain(3, [14, 12, 17], 2, 250))
	var problem := model.engine.problem_at(10)
	assert_array(Array(problem.breakers)).is_equal([14, 12, 17])
	assert_int(problem.next).is_equal(2)
	assert_int(problem.since).is_equal(250)
	# A chain of a problem the client never saw open is dropped.
	model.fold(&"BreakerChain", _chain(9, [1], 1, 5))
	assert_array(model.engine.problems.keys()).contains_exactly([3])


func test_the_gill_slits_flip_both_ways_and_shut_when_a_problem_opens() -> void:
	var model := ClientModel.new(FixtureBaseMode.mode())
	model.fold(&"EngineProblemOpened", _opened(1, [4], 300))
	model.fold(&"GillFlipped", {"station": 4, "slit": 0, "open": true})
	model.fold(&"GillFlipped", {"station": 4, "slit": 3, "open": true})
	assert_int(model.engine.slits[4]).is_equal(0b01001)
	model.fold(&"GillFlipped", {"station": 4, "slit": 0, "open": false})
	assert_int(model.engine.slits[4]).is_equal(0b01000)
	model.fold(&"EngineProblemFixed", {"problem": 1})
	model.fold(&"EngineProblemOpened", _opened(2, [4], 600))
	assert_int(model.engine.slits.get(4, 0)).is_equal(0)


func test_a_socket_s_crystal_is_its_last_change() -> void:
	var model := ClientModel.new(FixtureBaseMode.mode())
	model.fold(&"CrystalChanged", _crystal(20, 30, CrystalProblem.CHARGING, 7, 500))
	model.fold(&"CrystalChanged", _crystal(20, 30, CrystalProblem.WAITING, 7, -1))
	var crystal := model.engine.crystals[20]
	assert_int(crystal.charger).is_equal(30)
	assert_int(crystal.phase).is_equal(CrystalProblem.WAITING)
	assert_int(crystal.tick).is_equal(-1)


func test_a_new_match_forgets_the_engine() -> void:
	var model := ClientModel.new(FixtureBaseMode.mode())
	model.fold(&"EngineProblemOpened", _opened(1, [4], 300))
	model.fold(&"EngineBlast", {"stage": 1})
	model.clear_match()
	assert_bool(model.engine.problems.is_empty()).is_true()
	assert_int(model.engine.blasts).is_equal(0)


func test_the_opening_tick_is_the_deadline_less_the_kind_s_timer() -> void:
	var kind := GillsProblem.new()
	kind.seconds = 10.0
	var problem := ClientEngineBook.Problem.new()
	problem.deadline = 1000
	assert_int(ClientEngineBook.opened_tick(problem, kind)).is_equal(
		1000 - Ticks.from_seconds(10.0)
	)


func _opened(problem: int, stations: Array[int], deadline: int) -> Dictionary:
	return {"problem": problem, "stations": PackedInt32Array(stations), "deadline": deadline}


func _chain(problem: int, order: Array[int], next: int, since: int) -> Dictionary:
	return {"problem": problem, "breakers": PackedInt32Array(order), "next": next, "since": since}


func _crystal(station: int, charger: int, phase: int, item: int, tick: int) -> Dictionary:
	return {"station": station, "charger": charger, "phase": phase, "item": item, "tick": tick}
