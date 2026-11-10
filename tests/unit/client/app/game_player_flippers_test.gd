extends GdUnitTestSuite
## The flipper keys (GamePlayer.flippers_count, #1489): they count on the lobby screen and, for a
## player waiting in the dead's hall, on the Round screen, whose pinball stands there. A living
## player's Round has none.

const OWN := 2


func test_the_flippers_count_in_the_lobby_and_for_the_dead_of_the_round_hall() -> void:
	var model := ClientModel.new(FixtureHallModes.mode())
	model.own_peer = OWN
	model.phase = &"round"
	assert_bool(GamePlayer.flippers_count(GameFlow.Screen.LOBBY, model)).is_true()
	assert_bool(GamePlayer.flippers_count(GameFlow.Screen.ROUND, model)).is_false()
	model.lives[OWN] = ClientModel.Life.DEAD
	assert_bool(GamePlayer.flippers_count(GameFlow.Screen.ROUND, model)).is_true()
	assert_bool(GamePlayer.flippers_count(GameFlow.Screen.END, model)).is_false()
