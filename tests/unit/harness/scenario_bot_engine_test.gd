extends GdUnitTestSuite
## ScenarioBot learns the ship's engine from its public events alone (#1498; ARCHITECTURE §9.7,
## §9.5.27): it folds them into a ClientEngineBook as a player's client does, tells the console's
## start and the full bar, lets go of a crystal a charger locks, and forgets it all at a new match.

const PEER := 5
const CONSOLE := 1
const BUTTON := 2
const SOCKET := 3
const CHARGER := 4


func test_the_bot_folds_the_engine_events_into_its_book() -> void:
	var bot := _bot()
	_receive(
		bot,
		&"EngineProblemOpened",
		{"problem": 1, "stations": PackedInt32Array([BUTTON]), "deadline": 300}
	)
	_receive(
		bot,
		&"EngineProblemOpened",
		{"problem": 2, "stations": PackedInt32Array([SOCKET]), "deadline": 700}
	)
	_receive(bot, &"GillFlipped", {"station": BUTTON, "slit": 2, "open": true})
	assert_array(bot.engine.problems.keys()).contains_exactly_in_any_order([1, 2])
	assert_int(bot.engine.problems[1].deadline).is_equal(300)
	assert_int(bot.engine.slits[BUTTON]).is_equal(1 << 2)
	_receive(bot, &"EngineProblemFixed", {"problem": 1})
	assert_array(bot.engine.problems.keys()).contains_exactly([2])
	_receive(bot, &"EngineBlast", {"stage": 1})
	assert_bool(bot.engine.problems.is_empty()).is_true()
	assert_int(bot.engine.blasts).is_equal(1)


func test_the_console_s_press_and_its_full_bar_start_and_end_the_engine() -> void:
	var bot := _bot()
	# Another station's ButtonPressed and a part-full bar say nothing of the engine.
	_receive(bot, &"ButtonPressed", {"station": BUTTON})
	_receive(bot, &"ZoneProgress", _progress(CONSOLE, 0, 1800))
	assert_bool(bot.engine_started).is_false()
	_receive(bot, &"ButtonPressed", {"station": CONSOLE})
	assert_bool(bot.engine_started).is_true()
	_receive(bot, &"ZoneProgress", _progress(CONSOLE, 1799, 1800))
	assert_bool(bot.engine_done).is_false()
	_receive(bot, &"ZoneProgress", _progress(BUTTON, 1800, 1800))
	assert_bool(bot.engine_done).is_false()
	_receive(bot, &"ZoneProgress", _progress(CONSOLE, 1800, 1800))
	assert_bool(bot.engine_done).is_true()


func test_a_crystal_loaded_into_a_charger_leaves_the_hand() -> void:
	var bot := _bot()
	_receive(bot, &"ItemSpawned", {"item": 9, "kind": &"crystal_spent", "position": Vector3.ZERO})
	_receive(bot, &"ItemPickedUp", {"peer": PEER, "item": 9, "place": 0})
	_receive(bot, &"CrystalChanged", _crystal(-1, CrystalProblem.EMPTY, 9))
	assert_int(bot.held).is_equal(9)
	_receive(bot, &"CrystalChanged", _crystal(CHARGER, CrystalProblem.LOADED, 9))
	assert_int(bot.held).is_equal(-1)
	assert_int(bot.items[9]["where"]).is_equal(ScenarioBot.Where.LOCKED)
	assert_int(bot.engine.crystals[SOCKET].charger).is_equal(CHARGER)


func test_a_new_match_forgets_the_engine() -> void:
	var bot := _bot()
	_receive(bot, &"ButtonPressed", {"station": CONSOLE})
	_receive(
		bot,
		&"EngineProblemOpened",
		{"problem": 1, "stations": PackedInt32Array([BUTTON]), "deadline": 300}
	)
	_receive(bot, &"LoadMatch", {"match_id": 2})
	assert_bool(bot.engine_started).is_false()
	assert_bool(bot.engine.problems.is_empty()).is_true()


func _bot() -> ScenarioBot:
	var steps: Array[ScenarioStep] = []
	var bot := ScenarioBot.new(1, PEER, steps)
	_receive(bot, &"StationPlaced", _placed(CONSOLE, &"engine_console"))
	_receive(bot, &"StationPlaced", _placed(BUTTON, &"gill_button"))
	_receive(bot, &"StationPlaced", _placed(SOCKET, &"cartridge_socket"))
	_receive(bot, &"StationPlaced", _placed(CHARGER, &"cartridge_charger"))
	return bot


func _receive(bot: ScenarioBot, event_name: StringName, fields: Dictionary) -> void:
	assert_str(bot.receive(event_name, fields)).is_empty()


static func _placed(station: int, kind: StringName) -> Dictionary:
	return {"station": station, "kind": kind, "colour": Color.WHITE, "position": Vector3.ZERO}


static func _progress(station: int, ticks: int, needed: int) -> Dictionary:
	return {"station": station, "ticks": ticks, "needed": needed, "counting": false, "tick": 0}


static func _crystal(charger: int, phase: int, item: int) -> Dictionary:
	return {"station": SOCKET, "charger": charger, "phase": phase, "item": item, "tick": -1}
