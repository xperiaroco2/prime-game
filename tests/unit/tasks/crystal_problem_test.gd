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


## CrystalChanged's fields for `problem`'s crystal out as `item` (or in, -1) and in no charger.
func _out(problem: EngineProblem, item: int) -> Dictionary:
	return _in_charger(problem, -1, CrystalProblem.EMPTY, item, -1)


## CrystalChanged's fields for `problem`'s crystal `item` in `charger`, its `phase` and end tick.
func _in_charger(
	problem: EngineProblem, charger: int, phase: int, item: int, end_tick: int
) -> Dictionary:
	return {
		"station": problem.stations[0],
		"charger": charger,
		"phase": phase,
		"item": item,
		"tick": end_tick,
	}


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


## ALL starts the engine; the ticks run until two problems are open. Returns them.
func _two_open(game: Match) -> Array[EngineProblem]:
	FixtureEngineModes.start(game, ALL)
	var task_state := FixtureEngineModes.state_of(game)
	for i in 40:
		if task_state.problems.size() >= 2:
			break
		FixtureModes.run_ticks(game, 1)
	return task_state.problems.duplicate()


## The ItemPlaced events `peer` received with cause `slipped`.
func _slips(game: Match, peer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for placed: Dictionary in FixtureEngineModes.dicts(game, peer, &"ItemPlaced"):
		if placed["cause"] == CrystalProblem.SLIPPED:
			found.append(placed)
	return found


func test_a_charger_in_use_and_another_sockets_charged_crystal_are_refused() -> void:
	var game := _game()
	var problems := _two_open(game)
	assert_int(problems.size()).is_equal(2)
	var mine := problems[0]
	var other := problems[1]
	var charger := _chargers(game)[0]
	var crystal := _pull(game, mine)
	FixtureEngineKindModes.press(game, ALL, charger)
	var at := FixtureEngineKindModes.press(game, ALL, charger)
	FixtureEngineKindModes.press(game, SECOND, other.stations[0])
	var others := Items.held_by(game.state, SECOND)
	assert_int(_data(other).item).is_equal(others.id)
	# The second crystal waits for that charger (GDD §8).
	FixtureEngineKindModes.press(game, SECOND, charger)
	assert_str(String(FixtureEngineKindModes.last_reason(game, SECOND))).is_equal("unavailable")
	assert_object(Items.held_by(game.state, SECOND)).is_same(others)
	FixtureEngineKindModes.run_to(game, at + CHARGE)
	FixtureEngineKindModes.press(game, ALL, charger)
	assert_object(Items.held_by(game.state, ALL)).is_same(crystal)
	assert_str(String(crystal.kind.id)).is_equal("crystal_charged")
	# A charged crystal fits only its own socket.
	FixtureEngineKindModes.press(game, ALL, other.stations[0])
	assert_str(String(FixtureEngineKindModes.last_reason(game, ALL))).is_equal("wrong_item")
	var task_state := FixtureEngineModes.state_of(game)
	assert_bool(task_state.problems.has(mine)).is_true()
	assert_bool(task_state.problems.has(other)).is_true()
	assert_object(Items.held_by(game.state, ALL)).is_same(crystal)
	assert_object(Items.held_by(game.state, SECOND)).is_same(others)
	assert_bool(game.state.items.has(others.id)).is_true()
	FixtureEngineKindModes.press(game, ALL, mine.stations[0])
	assert_bool(task_state.problems.has(mine)).is_false()
	assert_bool(task_state.problems.has(other)).is_true()


func test_a_crystal_slips_once_from_a_charger_outside_the_ship() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var charger := _chargers(game)[0]
	# A level's charger out of the aboard box: the crystal's last aboard spot is outside.
	game.state.stations[charger].position = FixtureEngineKindModes.OUTSIDE
	var crystal := _charge(game, problem)
	assert_int(crystal.where).is_equal(ItemState.Where.LOCKED)
	assert_array(_slips(game, SECOND)).is_empty()
	# The take: the crystal comes into ALL's hands and slips in that tick's problem tick.
	FixtureEngineKindModes.press(game, ALL, charger)
	assert_array(FixtureEngineModes.dicts(game, SECOND, &"ItemPickedUp")).has_size(2)
	FixtureModes.run_ticks(game, 5)
	assert_bool(crystal.is_carried()).is_false()
	assert_int(crystal.where).is_equal(ItemState.Where.GROUND)
	# Once: lying on its slip spot, it stays (no ItemPlaced each tick).
	assert_array(_slips(game, SECOND)).has_size(1)


func test_a_crystal_thrown_from_outside_flies_until_it_lands() -> void:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.crystal()]
	var mode := FixtureThrowModes.with_throw(FixtureEngineKindModes.of(kinds))
	var game := FixtureEngineKindModes.in_round(mode, PEERS)
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _pull(game, problem)
	FixtureModes.run_ticks(game, 1)
	var last_in := game.state.player(ALL).position
	# A step over the edge and a throw in the same tick: no problem tick saw it carried outside.
	FixtureItemModes.stand(game, ALL, FixtureEngineKindModes.OUTSIDE)
	FixtureThrowModes.throw(game, ALL, Vector3.RIGHT)
	FixtureModes.run_ticks(game, 1)
	assert_int(crystal.where).is_equal(ItemState.Where.FLYING)
	assert_array(FixtureEngineModes.dicts(game, SECOND, &"ItemPlaced")).is_empty()
	for _i in 200:
		if crystal.where != ItemState.Where.FLYING:
			break
		FixtureModes.run_ticks(game, 1)
	var placed := FixtureEngineModes.dicts(game, SECOND, &"ItemPlaced")
	assert_int(placed.size()).is_equal(1)
	assert_str(str(placed[0]["cause"])).is_equal(str(Items.THROWN))
	FixtureModes.run_ticks(game, 1)
	assert_array(_slips(game, SECOND)).is_equal(
		[{"item": crystal.id, "position": last_in, "cause": CrystalProblem.SLIPPED}]
	)


func test_the_pull_puts_the_spent_crystal_in_both_hands() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var from_tick := game.ticked_through()
	var crystal := _pull(game, problem)
	assert_object(crystal).is_not_null()
	assert_str(String(crystal.kind.id)).is_equal("crystal_spent")
	assert_bool(crystal.kind.is_two_handed()).is_true()
	assert_int(_data(problem).item).is_equal(crystal.id)
	for peer: int in PEERS:
		var names := FixtureEngineModes.stream(
			game, peer, [&"ItemSpawned", &"CrystalChanged", &"ItemPickedUp"]
		)
		assert_array(names).is_equal([&"ItemSpawned", &"CrystalChanged", &"ItemPickedUp"])
	assert_array(FixtureEngineKindModes.since(game, SECOND, &"CrystalChanged", from_tick)).is_equal(
		[_out(problem, crystal.id)]
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
	# The pull, then the load, the press (its end tick), the charge's end and the take.
	var id := crystal.id
	(
		assert_array(FixtureEngineModes.dicts(game, SECOND, &"CrystalChanged"))
		. is_equal(
			[
				_out(problem, id),
				_in_charger(problem, charger, CrystalProblem.LOADED, id, -1),
				_in_charger(problem, charger, CrystalProblem.CHARGING, id, at + CHARGE),
				_in_charger(problem, charger, CrystalProblem.WAITING, id, -1),
				_out(problem, id),
			]
		)
	)
	assert_array(FixtureEngineModes.dicts(game, SECOND, &"ItemChanged")).is_equal(
		[{"item": crystal.id, "kind": &"crystal_charged"}]
	)
	var from_tick := game.ticked_through()
	FixtureEngineKindModes.press(game, ALL, problem.stations[0])
	assert_object(Items.held_by(game.state, ALL)).is_null()
	assert_bool(game.state.items.has(crystal.id)).is_false()
	assert_bool(FixtureEngineModes.state_of(game).problems.has(problem)).is_false()
	var names := FixtureEngineModes.stream(
		game, SECOND, [&"ItemVanished", &"CrystalChanged", &"EngineProblemFixed"]
	)
	assert_array(names.slice(-3)).is_equal(
		[&"ItemVanished", &"CrystalChanged", &"EngineProblemFixed"]
	)
	assert_array(FixtureEngineKindModes.since(game, SECOND, &"CrystalChanged", from_tick)).is_equal(
		[_out(problem, -1)]
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


func test_a_crystal_thrown_off_the_ship_is_judged_where_it_lands() -> void:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.crystal()]
	var mode := FixtureThrowModes.with_throw(FixtureEngineKindModes.of(kinds))
	var game := FixtureEngineKindModes.in_round(mode, PEERS)
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _pull(game, problem)
	var edge := Vector3(FixtureEngineModes.INSIDE_HIGH.x - 0.5, 0, 20)
	FixtureItemModes.stand(game, ALL, edge)
	FixtureModes.run_ticks(game, 1)
	FixtureThrowModes.throw(game, ALL, Vector3.RIGHT)
	FixtureModes.run_ticks(game, 1)
	assert_int(crystal.where).is_equal(ItemState.Where.FLYING)
	# In flight, out of the box: nothing slips until it lands.
	for _i in 200:
		if crystal.where != ItemState.Where.FLYING:
			break
		FixtureModes.run_ticks(game, 1)
	var placed := FixtureEngineModes.dicts(game, SECOND, &"ItemPlaced")
	assert_int(placed.size()).is_equal(1)
	assert_str(str(placed[0]["cause"])).is_equal(str(Items.THROWN))
	assert_bool(placed[0]["position"].x > FixtureEngineModes.INSIDE_HIGH.x).is_true()
	FixtureModes.run_ticks(game, 1)
	placed = FixtureEngineModes.dicts(game, SECOND, &"ItemPlaced")
	assert_int(placed.size()).is_equal(2)
	assert_dict(placed[1]).is_equal(
		{"item": crystal.id, "position": edge, "cause": CrystalProblem.SLIPPED}
	)


func test_the_blast_puts_a_carried_crystal_back_in_its_socket() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _pull(game, problem)
	var from_tick := game.ticked_through()
	FixtureEngineKindModes.run_to(game, problem.deadline)
	assert_array(FixtureEngineModes.dicts(game, SECOND, &"EngineBlast")).has_size(1)
	assert_bool(game.state.items.has(crystal.id)).is_false()
	assert_object(Items.held_by(game.state, ALL)).is_null()
	assert_array(FixtureEngineKindModes.since(game, SECOND, &"ItemVanished", from_tick)).has_size(1)
	assert_array(FixtureEngineKindModes.since(game, SECOND, &"CrystalChanged", from_tick)).is_equal(
		[_out(problem, -1)]
	)


func test_the_blast_empties_a_charger_holding_the_crystal() -> void:
	var game := _game()
	var problem := FixtureEngineKindModes.start_to_problem(game, ALL)
	var crystal := _charge(game, problem)
	var from_tick := game.ticked_through()
	FixtureEngineKindModes.run_to(game, problem.deadline)
	assert_bool(game.state.items.has(crystal.id)).is_false()
	# Out of the charger and back in its socket, in one change.
	assert_array(FixtureEngineKindModes.since(game, SECOND, &"CrystalChanged", from_tick)).is_equal(
		[_out(problem, -1)]
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
	kind.charged.vanish_seconds = 5
	assert_str(" ".join(kind.check(mode))).contains("vanishes")
	kind.charged.vanish_seconds = 0
	kind.site = FixtureEngineModes.kind(&"cartridge_socket")
	assert_str(" ".join(kind.check(mode))).contains("refuses the two-handed crystal")
	kind.site = FixtureEngineKindModes.two_handed_kind(&"cartridge_socket")
	kind.fixtures = []
	assert_str(" ".join(kind.check(mode))).contains("one fixture")
