extends GdUnitTestSuite
## EngineMender picks a MendEngine bot's next move on the ship's engine from what the bot was told
## (#1498; ARCHITECTURE §9.7, §9.5.27): synthetic events into a ScenarioBot, the problem kinds built
## here with the GDD's placeholder numbers (no content/ load), the press's host tick given.

const PEER := 5
const CONSOLE := 1
const BUTTON := 2
const BOARD := 3
const BREAKER_A := 4
const BREAKER_B := 5
const SOCKET := 6
const SOCKET_2 := 7
const CHARGER_A := 8
const CHARGER_B := 9
const DECK := 1.2
const AT: Dictionary[int, Vector3] = {
	CONSOLE: Vector3(0, DECK, 0),
	BUTTON: Vector3(5, DECK, 0),
	BOARD: Vector3(10, DECK, 0),
	BREAKER_A: Vector3(10, DECK, 5),
	BREAKER_B: Vector3(-10, DECK, 5),
	SOCKET: Vector3(0, DECK, 5),
	SOCKET_2: Vector3(0, DECK, -5),
	CHARGER_A: Vector3(20, DECK, 0),
	CHARGER_B: Vector3(-20, DECK, 0),
}
const KINDS: Dictionary[int, StringName] = {
	CONSOLE: &"engine_console",
	BUTTON: &"gill_button",
	BOARD: &"breaker_board",
	BREAKER_A: &"breaker",
	BREAKER_B: &"breaker",
	SOCKET: &"cartridge_socket",
	SOCKET_2: &"cartridge_socket",
	CHARGER_A: &"cartridge_charger",
	CHARGER_B: &"cartridge_charger",
}
## A gill problem's timer (10 s) and one bar step (0.6 s), in host ticks.
const GILL_TICKS := 200
const STEP := 12
## A breaker's ramp (1 s) and green (5 s), in host ticks.
const RAMP := 20
const GREEN := 100


func test_the_start_bot_walks_to_the_console_and_presses_it_once() -> void:
	var bot := _bot(false)
	var mender := _mender(true)
	bot.position = Vector3(0, DECK, 10)
	_is_walk(mender.decide(bot, 0), AT[CONSOLE])
	bot.position = AT[CONSOLE]
	_is_press(mender.decide(bot, 1), CONSOLE)
	# Its answer is not in yet: no second press.
	_is_wait(mender.decide(bot, 2))
	_receive(bot, &"ButtonPressed", {"station": CONSOLE})
	_is_wait(mender.decide(bot, 3))


func test_the_others_wait_at_the_console_until_it_is_pressed() -> void:
	var bot := _bot(false)
	var mender := _mender(false)
	bot.position = Vector3(0, DECK, 10)
	_is_walk(mender.decide(bot, 0), AT[CONSOLE])
	bot.position = AT[CONSOLE]
	_is_wait(mender.decide(bot, 1))


func test_a_bot_below_the_deck_walks_the_boarding_points_first() -> void:
	var bot := _bot(false)
	var mender := _mender(true)
	mender.step.boarding = PackedVector3Array([Vector3(0, 0, -10), Vector3(0, DECK, -5)])
	bot.position = Vector3(0, 0, -20)
	_is_walk(mender.decide(bot, 0), Vector3(0, 0, -10))
	bot.position = Vector3(0, 0, -10)
	_is_walk(mender.decide(bot, 1), Vector3(0, DECK, -5))
	bot.position = Vector3(0, DECK, -5)
	_is_walk(mender.decide(bot, 2), AT[CONSOLE])


func test_gills_press_mid_step_on_a_shut_slit_once_a_step() -> void:
	var bot := _bot(true)
	var mender := _mender(false)
	var deadline := 1000
	var opened := deadline - GILL_TICKS
	_open(bot, 3, [BUTTON], deadline)
	bot.position = Vector3(0, DECK, 0)
	_is_walk(mender.decide(bot, opened), AT[BUTTON])
	bot.position = AT[BUTTON]
	# A step's edge: wait; its middle on shut slit 0: press, once.
	_is_wait(mender.decide(bot, opened + 1))
	_is_press(mender.decide(bot, opened + STEP / 2), BUTTON)
	_is_wait(mender.decide(bot, opened + STEP / 2 + 1))
	# Slit 1 is open already: its step passes.
	_receive(bot, &"GillFlipped", {"station": BUTTON, "slit": 1, "open": true})
	_is_wait(mender.decide(bot, opened + STEP + STEP / 2))
	# Slit 2 is shut: pressed.
	_is_press(mender.decide(bot, opened + 2 * STEP + STEP / 2), BUTTON)


func test_a_bot_leaves_the_problems_of_another_share_alone() -> void:
	var bot := _bot(true)
	var mender := _mender(false)
	_open(bot, 4, [BUTTON], 1000)
	assert_int(mender.pick(bot)).is_equal(-1)
	bot.position = AT[BUTTON]
	_is_walk(mender.decide(bot, 900), AT[CONSOLE])


func test_the_soonest_deadline_of_its_share_comes_first() -> void:
	var bot := _bot(true)
	var mender := _mender(false)
	_open(bot, 3, [SOCKET], 900)
	_open(bot, 6, [BUTTON], 500)
	assert_int(mender.pick(bot)).is_equal(6)


func test_breakers_the_first_at_once_the_next_inside_its_green_window() -> void:
	var bot := _bot(true)
	var mender := _mender(false)
	_open(bot, 3, [BOARD], 2000)
	_chain(bot, 3, 0, -1)
	bot.position = AT[CONSOLE]
	_is_walk(mender.decide(bot, 100), AT[BREAKER_A])
	bot.position = AT[BREAKER_A]
	_is_press(mender.decide(bot, 101), BREAKER_A)
	_chain(bot, 3, 1, 101)
	_is_walk(mender.decide(bot, 102), AT[BREAKER_B])
	bot.position = AT[BREAKER_B]
	# Yellow, and too near the green's start: wait.
	_is_wait(mender.decide(bot, 101 + RAMP))
	_is_wait(mender.decide(bot, 101 + RAMP + EngineMender.GREEN_MARGIN_TICKS - 1))
	_is_press(mender.decide(bot, 101 + RAMP + EngineMender.GREEN_MARGIN_TICKS), BREAKER_B)


func test_a_breaker_is_not_pressed_at_the_end_of_its_green() -> void:
	var bot := _bot(true)
	var mender := _mender(false)
	_open(bot, 3, [BOARD], 2000)
	_chain(bot, 3, 1, 100)
	bot.position = AT[BREAKER_B]
	_is_wait(mender.decide(bot, 100 + RAMP + GREEN - EngineMender.GREEN_MARGIN_TICKS + 1))
	_is_press(mender.decide(bot, 100 + RAMP + GREEN - EngineMender.GREEN_MARGIN_TICKS), BREAKER_B)


func test_the_crystal_from_its_socket_through_a_charger_and_back() -> void:
	var bot := _bot(true)
	var mender := _mender(false)
	_open(bot, 3, [SOCKET], 2000)
	bot.position = AT[SOCKET]
	_is_press(mender.decide(bot, 100), SOCKET)
	# The pull: the spent crystal in its hands. Problem 3's own charger is B (3 % 2 of A, B).
	_receive(bot, &"ItemSpawned", {"item": 40, "kind": &"crystal_spent", "position": AT[SOCKET]})
	_receive(bot, &"ItemPickedUp", {"peer": PEER, "item": 40, "place": 0})
	_crystal(bot, SOCKET, -1, CrystalProblem.EMPTY, 40)
	_is_walk(mender.decide(bot, 101), AT[CHARGER_B])
	bot.position = AT[CHARGER_B]
	_is_press(mender.decide(bot, 102), CHARGER_B)
	_crystal(bot, SOCKET, CHARGER_B, CrystalProblem.LOADED, 40)
	assert_int(bot.held).is_equal(-1)
	_is_press(mender.decide(bot, 102 + EngineMender.SETTLE_TICKS), CHARGER_B)
	# Charging: nothing to do but wait by the console.
	_crystal(bot, SOCKET, CHARGER_B, CrystalProblem.CHARGING, 40)
	assert_int(mender.pick(bot)).is_equal(-1)
	_is_walk(mender.decide(bot, 120), AT[CONSOLE])
	_crystal(bot, SOCKET, CHARGER_B, CrystalProblem.WAITING, 40)
	_is_press(mender.decide(bot, 320), CHARGER_B)
	_receive(bot, &"ItemPickedUp", {"peer": PEER, "item": 40, "place": 0})
	_crystal(bot, SOCKET, -1, CrystalProblem.EMPTY, 40)
	_is_walk(mender.decide(bot, 321), AT[SOCKET])
	bot.position = AT[SOCKET]
	_is_press(mender.decide(bot, 322), SOCKET)


func test_a_busy_charger_sends_the_crystal_to_a_free_one_or_none() -> void:
	var bot := _bot(true)
	var mender := _mender(false)
	_open(bot, 3, [SOCKET], 2000)
	_crystal(bot, SOCKET_2, CHARGER_B, CrystalProblem.CHARGING, 41)
	_receive(bot, &"ItemSpawned", {"item": 40, "kind": &"crystal_spent", "position": AT[SOCKET]})
	_receive(bot, &"ItemPickedUp", {"peer": PEER, "item": 40, "place": 0})
	_crystal(bot, SOCKET, -1, CrystalProblem.EMPTY, 40)
	bot.position = AT[SOCKET]
	_is_walk(mender.decide(bot, 101), AT[CHARGER_A])
	_crystal(bot, 99, CHARGER_A, CrystalProblem.LOADED, 42)
	_is_wait(mender.decide(bot, 102))


func test_a_downed_bot_or_a_done_engine_waits() -> void:
	var bot := _bot(true)
	var mender := _mender(false)
	_open(bot, 3, [BUTTON], 1000)
	bot.downed = true
	_is_wait(mender.decide(bot, 900))
	bot.downed = false
	_receive(
		bot,
		&"ZoneProgress",
		{"station": CONSOLE, "ticks": 1800, "needed": 1800, "counting": false, "tick": 0}
	)
	_is_wait(mender.decide(bot, 901))


func _bot(started: bool) -> ScenarioBot:
	var steps: Array[ScenarioStep] = []
	var bot := ScenarioBot.new(1, PEER, steps)
	for station: int in AT:
		_receive(
			bot,
			&"StationPlaced",
			{
				"station": station,
				"kind": KINDS[station],
				"colour": Color.WHITE,
				"position": AT[station]
			}
		)
	if started:
		_receive(bot, &"ButtonPressed", {"station": CONSOLE})
	return bot


func _mender(start: bool) -> EngineMender:
	var mend := StepMendEngine.new()
	mend.of = 3
	mend.start = start
	var gills := GillsProblem.new()
	gills.id = &"gills"
	gills.seconds = 10.0
	gills.site = _station_kind(&"gill_button")
	gills.step_seconds = 0.6
	var breakers := BreakersProblem.new()
	breakers.id = &"breakers"
	breakers.seconds = 30.0
	breakers.site = _station_kind(&"breaker_board")
	breakers.fixtures = [_station_kind(&"breaker")]
	breakers.ramp_seconds = 1.0
	breakers.green_seconds = 5.0
	var crystal := CrystalProblem.new()
	crystal.id = &"crystal"
	crystal.seconds = 30.0
	crystal.site = _station_kind(&"cartridge_socket")
	crystal.fixtures = [_station_kind(&"cartridge_charger")]
	var kinds: Array[ProblemKind] = [gills, breakers, crystal]
	return EngineMender.new(mend, kinds)


static func _station_kind(id: StringName) -> StationKind:
	var kind := StationKind.new()
	kind.id = id
	return kind


func _open(bot: ScenarioBot, problem: int, at: Array[int], deadline: int) -> void:
	_receive(
		bot,
		&"EngineProblemOpened",
		{"problem": problem, "stations": PackedInt32Array(at), "deadline": deadline}
	)


func _chain(bot: ScenarioBot, problem: int, next: int, since: int) -> void:
	_receive(
		bot,
		&"BreakerChain",
		{
			"problem": problem,
			"breakers": PackedInt32Array([BREAKER_A, BREAKER_B]),
			"next": next,
			"since": since,
		}
	)


func _crystal(bot: ScenarioBot, socket: int, charger: int, phase: int, item: int) -> void:
	_receive(
		bot,
		&"CrystalChanged",
		{"station": socket, "charger": charger, "phase": phase, "item": item, "tick": -1}
	)


func _receive(bot: ScenarioBot, event_name: StringName, fields: Dictionary) -> void:
	assert_str(bot.receive(event_name, fields)).is_empty()


func _is_wait(move: EngineMender.Move) -> void:
	assert_int(move.act).is_equal(EngineMender.Act.WAIT)


func _is_walk(move: EngineMender.Move, to: Vector3) -> void:
	assert_int(move.act).is_equal(EngineMender.Act.WALK)
	assert_vector(move.to).is_equal(to)


func _is_press(move: EngineMender.Move, station: int) -> void:
	assert_int(move.act).is_equal(EngineMender.Act.PRESS)
	assert_int(move.station).is_equal(station)
