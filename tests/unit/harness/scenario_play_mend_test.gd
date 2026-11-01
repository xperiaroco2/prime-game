extends GdUnitTestSuite
## ScenarioPlay.mend_answers reads the answers to a MendEngine bot's presses (#1498; ARCHITECTURE
## §9.7): a Rejected `unavailable`, or any while the bot is down or dead, only makes the mender look
## again; any other refusal fails the step; a press unanswered for PRESS_ANSWER_TICKS is taken.

const PEER := 5
const CONSOLE := 1
const SEQ := 7
const AT := Vector3(0, 1.2, 0)


func test_an_unavailable_refusal_lets_the_mender_press_again() -> void:
	var bot := _bot()
	var mender := _mender()
	_is_press(mender.decide(bot, 1))
	# Unanswered, the console is not pressed twice.
	assert_int(mender.decide(bot, 2).act).is_equal(EngineMender.Act.WAIT)
	var presses := _pressed(1)
	_refuse(bot, StationUsable.UNAVAILABLE)
	assert_str(ScenarioPlay.mend_answers(bot, mender, presses, 3)).is_empty()
	assert_dict(presses).is_empty()
	_is_press(mender.decide(bot, 3))


func test_any_refusal_while_the_bot_is_down_or_dead_is_let_through() -> void:
	for state: StringName in [&"downed", &"dead"]:
		var bot := _bot()
		var mender := _mender()
		_is_press(mender.decide(bot, 1))
		var presses := _pressed(1)
		_refuse(bot, InReach.OUT_OF_REACH)
		bot.set(state, true)
		var answer := ScenarioPlay.mend_answers(bot, mender, presses, 2)
		assert_str(answer).override_failure_message(state).is_empty()
		assert_dict(presses).is_empty()
		bot.set(state, false)
		_is_press(mender.decide(bot, 2))


func test_any_other_refusal_fails_the_step() -> void:
	for reason: StringName in [
		InReach.OUT_OF_REACH, StationUsable.WRONG_ITEM, StationUsable.EMPTY_HAND
	]:
		var bot := _bot()
		var mender := _mender()
		_is_press(mender.decide(bot, 1))
		var presses := _pressed(1)
		_refuse(bot, reason)
		assert_str(ScenarioPlay.mend_answers(bot, mender, presses, 2)).is_equal(
			"Rejected (%s) at station %d" % [reason, CONSOLE]
		)


func test_an_unanswered_press_is_taken_after_its_wait() -> void:
	var bot := _bot()
	var mender := _mender()
	_is_press(mender.decide(bot, 0))
	var presses := _pressed(0)
	var waited := ScenarioPlay.PRESS_ANSWER_TICKS
	assert_str(ScenarioPlay.mend_answers(bot, mender, presses, waited)).is_empty()
	assert_dict(presses).contains_keys([SEQ])
	assert_str(ScenarioPlay.mend_answers(bot, mender, presses, waited + 1)).is_empty()
	assert_dict(presses).is_empty()


func test_the_bots_console_kind_is_the_contents() -> void:
	# The engine tests' fixtures name the console kind as the content does.
	assert_str(str(ScenarioBot.engine_console())).is_equal("engine_console")


## A bot at the console, the engine not started.
func _bot() -> ScenarioBot:
	var steps: Array[ScenarioStep] = []
	var bot := ScenarioBot.new(1, PEER, steps)
	var fields := {
		"station": CONSOLE,
		"kind": ScenarioBot.engine_console(),
		"colour": Color.WHITE,
		"position": AT,
	}
	assert_str(bot.receive(&"StationPlaced", fields)).is_empty()
	bot.position = AT
	return bot


## The step's start bot's mender (no problem kinds: the console is all it presses here).
func _mender() -> EngineMender:
	var mend := StepMendEngine.new()
	mend.of = 1
	mend.start = true
	var kinds: Array[ProblemKind] = []
	return EngineMender.new(mend, kinds)


## The console's press SEQ, sent on `tick`.
func _pressed(tick: int) -> Dictionary:
	return {SEQ: [CONSOLE, tick]}


func _refuse(bot: ScenarioBot, reason: StringName) -> void:
	var fields := {"peer": PEER, "seq": SEQ, "reason": reason}
	assert_str(bot.receive(&"Rejected", fields)).is_empty()


func _is_press(move: EngineMender.Move) -> void:
	assert_int(move.act).is_equal(EngineMender.Act.PRESS)
	assert_int(move.station).is_equal(CONSOLE)
