extends GdUnitTestSuite
## The ship engine's burnt crystal (CrystalProblem, #1461; GDD §8 "A spent cartridge"): the pull
## into both hands, the charger's load, press, charge and take, the fit fixing it, the refusals,
## the crystal slipping back aboard (carried out, put down outside), the blast putting it back, and
## the check; on FixtureEngineKindModes with the real kind.

const PEERS: Array[int] = [1, 2]
const ALL := 1
const SECOND := 2
const CHARGE := FixtureEngineKindModes.CHARGE_TICKS


func _game(seed_value: int = 7) -> Match:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.crystal()]
	return FixtureEngineKindModes.in_round(FixtureEngineKindModes.of(kinds), PEERS, seed_value)


func _data(problem: EngineProblem) -> CrystalProblem.Data:
	return problem.data as CrystalProblem.Data


func _chargers(game: Match) -> Array[int]:
	var task_state := FixtureEngineModes.state_of(game)
	var found: Array[int] = []
	for station_id: int in task_state.stations:
		if task_state.kind_of.get(station_id, -1) == 0 and not task_state.sites[0].has(station_id):
			found.append(station_id)
	return found


## ALL pulls the crystal of `problem`; returns the item.
func _pull(game: Match, problem: EngineProblem) -> ItemState:
	FixtureEngineKindModes.press(game, ALL, problem.stations[0])
	return Items.held_by(game.state, ALL)


## ALL pulls the crystal, loads it into the first charger, SECOND presses it and the charge runs
## out; returns the item.
func _charge(game: Match, problem: EngineProblem) -> ItemState:
	var crystal := _pull(game, problem)
	var charger := _chargers(game)[0]
	FixtureEngineKindModes.press(game, ALL, charger)
	var at := FixtureEngineKindModes.press(game, SECOND, charger)
	FixtureEngineKindModes.run_to(game, at + CHARGE)
	return crystal


func test_the_pull_puts_the_spent_crystal_in_both_hands() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var before := game.ticked_through()
	var crystal := _pull(game, problem)
	assert_object(crystal).is_not_null()
	assert_str(String(crystal.kind.id)).is_equal("crystal_spent")
	assert_bool(crystal.kind.is_two_handed()).is_true()
	assert_int(_data(problem).item).is_equal(crystal.id)
	for peer: int in PEERS:
		var names := FixtureEngineModes.stream(
			game, peer, [&"ItemSpawned", &"CrystalSocketChanged", &"ItemPickedUp"]
		)
		assert_array(names).is_equal([&"ItemSpawned", &"CrystalSocketChanged", &"ItemPickedUp"])
	(
		assert_array(FixtureEngineKindModes.since(game, SECOND, &"CrystalSocketChanged", before))
		. is_equal([{"station": problem.stations[0], "item": crystal.id}])
	)


func test_the_charger_loads_charges_and_hands_out_the_charged_crystal_which_fixes_it() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _pull(game, problem)
	var charger := _chargers(game)[0]
	FixtureEngineKindModes.press(game, ALL, charger)
	assert_object(Items.held_by(game.state, ALL)).is_null()
	assert_int(crystal.where).is_equal(ItemState.Where.LOCKED)
	# Anyone presses a loaded charger.
	var at := FixtureEngineKindModes.press(game, SECOND, charger)
	FixtureEngineKindModes.run_to(game, at + CHARGE - 1)
	assert_str(String(crystal.kind.id)).is_equal("crystal_spent")
	FixtureEngineKindModes.run_to(game, at + CHARGE)
	assert_str(String(crystal.kind.id)).is_equal("crystal_charged")
	FixtureEngineKindModes.press(game, ALL, charger)
	assert_object(Items.held_by(game.state, ALL)).is_same(crystal)
	var phases: Array[int] = []
	for changed: Dictionary in FixtureEngineModes.dicts(game, SECOND, &"ChargerChanged"):
		assert_int(changed["station"]).is_equal(charger)
		phases.append(changed["phase"])
	(
		assert_array(phases)
		. is_equal(
			[
				CrystalProblem.LOADED,
				CrystalProblem.CHARGING,
				CrystalProblem.WAITING,
				CrystalProblem.EMPTY,
			]
		)
	)
	assert_int(FixtureEngineModes.dicts(game, SECOND, &"ChargerChanged")[1]["tick"]).is_equal(
		at + CHARGE
	)
	assert_array(FixtureEngineModes.dicts(game, SECOND, &"ItemChanged")).is_equal(
		[{"item": crystal.id, "kind": &"crystal_charged"}]
	)
	var before := game.ticked_through()
	FixtureEngineKindModes.press(game, ALL, problem.stations[0])
	assert_object(Items.held_by(game.state, ALL)).is_null()
	assert_bool(game.state.items.has(crystal.id)).is_false()
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_false()
	var names := FixtureEngineModes.stream(
		game, SECOND, [&"ItemVanished", &"CrystalSocketChanged", &"EngineProblemFixed"]
	)
	assert_array(names.slice(-3)).is_equal(
		[&"ItemVanished", &"CrystalSocketChanged", &"EngineProblemFixed"]
	)
	(
		assert_array(FixtureEngineKindModes.since(game, SECOND, &"CrystalSocketChanged", before))
		. is_equal([{"station": problem.stations[0], "item": -1}])
	)


func test_the_refusals() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var task_state := FixtureEngineModes.state_of(game)
	var idle := -1
	for socket: int in task_state.sites[0]:
		if ShipEngine.problem_at(task_state, socket) == null:
			idle = socket
	FixtureEngineKindModes.press(game, ALL, idle)
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("unavailable")
	var charger := _chargers(game)[0]
	FixtureEngineKindModes.press(game, ALL, charger)
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("empty_hand")
	_pull(game, problem)
	# The spent crystal does not fit back.
	FixtureEngineKindModes.press(game, ALL, problem.stations[0])
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("wrong_item")
	FixtureEngineKindModes.press(game, ALL, charger)
	FixtureEngineKindModes.press(game, SECOND, charger)
	# Charging: no use.
	FixtureEngineKindModes.press(game, ALL, charger)
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("unavailable")
	# The socket of a crystal out takes nothing from an empty hand.
	FixtureEngineKindModes.press(game, SECOND, problem.stations[0])
	assert_str(String(FixtureEngineKindModes.last_reason(game, SECOND))).is_equal("empty_hand")


func test_a_crystal_carried_off_the_ship_slips_back_aboard() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _pull(game, problem)
	FixtureModes.run_ticks(game, 1)
	var last_in := game.state.player(ALL).position
	FixtureItemModes.stand(game, ALL, FixtureEngineKindModes.OUTSIDE)
	FixtureModes.run_ticks(game, 1)
	assert_object(Items.held_by(game.state, ALL)).is_null()
	assert_bool(crystal.is_carried()).is_false()
	assert_vector(crystal.position).is_equal(last_in)
	var placed := FixtureEngineModes.dicts(game, SECOND, &"ItemPlaced")
	assert_dict(placed[-1]).is_equal(
		{"item": crystal.id, "position": last_in, "cause": CrystalProblem.SLIPPED}
	)


func test_a_crystal_put_down_outside_slips_back_aboard() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _pull(game, problem)
	var edge := Vector3(FixtureEngineModes.INSIDE_HIGH.x - 0.5, 0, 20)
	FixtureItemModes.stand(game, ALL, edge)
	FixtureModes.run_ticks(game, 1)
	FixtureItemModes.put_down(game, ALL, Vector3.RIGHT)
	FixtureModes.run_ticks(game, 1)
	assert_bool(crystal.is_carried()).is_false()
	var placed := FixtureEngineModes.dicts(game, SECOND, &"ItemPlaced")
	assert_int(placed.size()).is_equal(2)
	assert_bool(placed[0]["position"].x > FixtureEngineModes.INSIDE_HIGH.x).is_true()
	assert_dict(placed[1]).is_equal(
		{"item": crystal.id, "position": edge, "cause": CrystalProblem.SLIPPED}
	)
	assert_vector(crystal.position).is_equal(edge)


func test_the_blast_puts_a_carried_crystal_back_in_its_socket() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _pull(game, problem)
	var before := game.ticked_through()
	FixtureEngineKindModes.run_to(game, problem.deadline)
	assert_array(FixtureEngineModes.dicts(game, SECOND, &"EngineBlast")).has_size(1)
	assert_bool(game.state.items.has(crystal.id)).is_false()
	assert_object(Items.held_by(game.state, ALL)).is_null()
	assert_array(FixtureEngineKindModes.since(game, SECOND, &"ItemVanished", before)).has_size(1)
	(
		assert_array(FixtureEngineKindModes.since(game, SECOND, &"CrystalSocketChanged", before))
		. is_equal([{"station": problem.stations[0], "item": -1}])
	)


func test_the_blast_empties_a_charger_holding_the_crystal() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _charge(game, problem)
	var before := game.ticked_through()
	FixtureEngineKindModes.run_to(game, problem.deadline)
	assert_bool(game.state.items.has(crystal.id)).is_false()
	assert_array(FixtureEngineKindModes.since(game, SECOND, &"ChargerChanged", before)).is_equal(
		[{"station": _chargers(game)[0], "phase": CrystalProblem.EMPTY, "item": -1, "tick": 0}]
	)
	# The socket holds its crystal again: a new problem there pulls a fresh one.
	assert_int(_data(problem).item).is_equal(-1)


func test_the_check() -> void:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.crystal()]
	var mode := FixtureEngineKindModes.of(kinds)
	var kind := kinds[0] as CrystalProblem
	assert_array(Array(kind.check(mode))).is_empty()
	kind.charge_seconds = 0.0
	assert_str(" ".join(kind.check(mode))).contains("charge_seconds")
	kind.charge_seconds = FixtureEngineKindModes.CHARGE_SECONDS
	kind.charged = kind.spent
	assert_str(" ".join(kind.check(mode))).contains("two distinct")
	kind.charged = FixtureItemModes.item_kind(&"crystal_charged", [], 2)
	assert_str(" ".join(kind.check(mode))).contains("not the mode's")
	kind.charged = mode.find_item_kind(&"crystal_charged")
	kind.charged.vanish_seconds = 5.0
	assert_str(" ".join(kind.check(mode))).contains("vanishes")
	kind.charged.vanish_seconds = 0.0
	kind.site = FixtureEngineModes.kind(&"cartridge_socket")
	assert_str(" ".join(kind.check(mode))).contains("refuses the two-handed crystal")
	kind.site = FixtureEngineKindModes.two_handed_kind(&"cartridge_socket")
	kind.fixtures = []
	assert_str(" ".join(kind.check(mode))).contains("one fixture")
