extends GdUnitTestSuite
## The bots of a `tools\run.cmd playcheck` run (tests/harness/playcheck/playcheck_bots.gd, #318):
## the runner starts their process beside the windows, so the bots play only once every player is
## in each bot's lobby, and a bot whose join went unanswered (window 1 not listening yet) joins
## again, as BotsEnet after #284. Built in code, no ENet socket: `tools\run.cmd playcheck spectate`
## runs the real thing.

const PlaycheckBots := preload("res://tests/harness/playcheck/playcheck_bots.gd")
const BASE_MODE := "res://content/modes/base_mode.tres"
const NO_PORT := 9
const PEERS := "user://playcheck_bots_test"
const START_USEC := 1_000_000
const FRAME_USEC := 16_667


## Players 1 and 2 are windows, 3 and 4 bots whose joins go to a LoopbackTransport of an empty hub
## (no host: connect_failed at the first poll).
class UnhostedBots:
	extends "res://tests/harness/playcheck/playcheck_bots.gd"

	func _init(bot_scenario: BotScenario) -> void:
		super(bot_scenario, 3, NO_PORT, PEERS)

	func _joining() -> NetTransport:
		var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
		transport.join("loopback", NO_PORT)
		return transport


func test_the_bots_play_once_every_player_is_in_each_bots_lobby() -> void:
	var play := PlaycheckBots.new(_scenario(), 3, NO_PORT, PEERS)
	var three := ScenarioBot.new(3, 0, [], play.peers)
	var four := ScenarioBot.new(4, 0, [], play.peers)
	play.bots.append(three)
	play.bots.append(four)
	for number in range(1, 5):
		play.peers.set_peer(number, 10 * number)
	# Every peer id is known, but no bot decoded the others joining yet.
	assert_bool(play._may_play()).override_failure_message("peer ids alone").is_false()
	for peer: int in [10, 20, 40]:
		three.seen[peer] = Vector3.ZERO
	assert_bool(play._may_play()).override_failure_message("bot 4 saw nobody").is_false()
	for peer: int in [10, 30]:
		four.seen[peer] = Vector3.ZERO
	assert_bool(play._may_play()).override_failure_message("window 2 not in bot 4's").is_false()
	four.seen[20] = Vector3.ZERO
	assert_bool(play._may_play()).is_true()


func test_a_bot_whose_join_went_unanswered_joins_again_and_plays_on() -> void:
	var play := UnhostedBots.new(_scenario())
	assert_bool(play.start(START_USEC)).is_true()
	var first: BotClient = play.clients[3]
	play.step(START_USEC + EnetTransport.JOIN_TIMEOUT_MS * 1000)
	assert_str(play.ended()).override_failure_message("joined again").is_empty()
	assert_object(play.clients[3]).is_not_same(first)
	assert_object(play.clients[4]).is_not_null()
	assert_array(play.failures).is_empty()
	play.finish()


func test_a_join_refused_at_once_still_ends_the_run() -> void:
	var play := UnhostedBots.new(_scenario())
	assert_bool(play.start(START_USEC)).is_true()
	var first: BotClient = play.clients[3]
	play.step(START_USEC + FRAME_USEC)
	assert_object(play.clients[3]).is_same(first)
	assert_str(play.ended()).contains("bot 3: its session ended (connect_failed)")
	play.step(START_USEC + 2 * EnetTransport.JOIN_TIMEOUT_MS * 1000)
	assert_object(play.clients[3]).override_failure_message("judged when first seen").is_same(first)
	play.finish()


## Players 1 and 2 are windows (empty scripts); 3 and 4 are bots with empty scripts.
func _scenario() -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = 4
	scenario.session_seed = 490_000_000_318
	scenario.expected_ends = [BotScenario.NONE]
	var made: Array[BotScript] = []
	for _number in 4:
		made.append(BotScript.new())
	scenario.scripts = made
	return scenario
