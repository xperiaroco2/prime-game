extends GdUnitTestSuite
## ScenarioBot's "an honest bot is never corrected" around the limp (#1393; ARCHITECTURE §7.1.21,
## KE4): the go-limp's Correction has no event of its own, so the next snapshot must show the bot
## limp; a sober bot, which cannot go limp, fails at once, as does a second unexplained one before
## the snapshot, and a limp bot gets at most the go-limp's and the get-up's.

const PEER := 5


func test_a_sober_bots_unexplained_correction_fails_at_once() -> void:
	var bot := _bot(0)
	assert_str(_correct(bot, 2)).contains("Correction outside a placement")


func test_one_unexplained_correction_passes_when_the_next_snapshot_shows_limp() -> void:
	var bot := _bot()
	assert_str(_correct(bot, 2)).is_empty()
	assert_str(bot.see({PEER: {"limp": true}})).is_empty()
	assert_bool(bot.limp).is_true()
	# The get-up's, then the bot stands again.
	assert_str(_correct(bot, 3)).is_empty()
	assert_str(bot.see({})).is_empty()
	assert_bool(bot.limp).is_false()


func test_one_unexplained_correction_fails_when_the_next_snapshot_shows_no_limp() -> void:
	var bot := _bot()
	assert_str(_correct(bot, 2)).is_empty()
	assert_str(bot.see({})).contains("never corrected")


func test_a_second_unexplained_correction_before_a_snapshot_fails_at_once() -> void:
	var bot := _bot()
	assert_str(_correct(bot, 2)).is_empty()
	assert_str(_correct(bot, 3)).contains("a second Correction")


func test_a_limp_bot_corrected_for_its_claims_fails() -> void:
	var bot := _bot()
	assert_str(_correct(bot, 2)).is_empty()
	assert_str(bot.see({PEER: {"limp": true}})).is_empty()
	assert_str(_correct(bot, 3)).is_empty()
	assert_str(_correct(bot, 4)).contains("a third Correction while limp")


## Over the network the snapshot showing the bot limp may come before the go-limp's Correction.
func test_the_snapshot_first_still_allows_the_go_limps_and_the_get_ups() -> void:
	var bot := _bot()
	assert_str(bot.see({PEER: {"limp": true}})).is_empty()
	assert_str(_correct(bot, 2)).is_empty()
	assert_str(_correct(bot, 3)).is_empty()
	assert_str(bot.see({})).is_empty()
	# A new limp starts its own count.
	assert_str(_correct(bot, 4)).is_empty()
	assert_str(bot.see({PEER: {"limp": true}})).is_empty()
	assert_str(_correct(bot, 5)).is_empty()


func _bot(drunk := 80) -> ScenarioBot:
	var steps: Array[ScenarioStep] = []
	var bot := ScenarioBot.new(1, PEER, steps)
	var welcome := {
		"peer": PEER, "epoch": 1, "spot": Vector3.ZERO, "phase": &"lobby", "positions": {}
	}
	assert_str(bot.receive(&"Welcome", welcome)).is_empty()
	bot.drunk = drunk
	return bot


func _correct(bot: ScenarioBot, epoch: int) -> String:
	return bot.receive(&"Correction", {"epoch": epoch, "position": Vector3(0, 0, epoch)})
