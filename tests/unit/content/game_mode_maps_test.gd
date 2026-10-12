extends GdUnitTestSuite
## GameMode's maps and test benches (#767): `bench_maps` are maps players never get, so the lobby
## offers only player_maps() and a match starts on default_map(), the first map players play; a
## bench map stays one of the mode's maps, which the lobby accepts when a bot asks for it (the bot
## scenarios and the information-leak test, ARCHITECTURE §9.7). A mode built in code (§9.6).

const P1 := 1


func test_the_player_maps_are_every_map_but_the_benches_in_their_order() -> void:
	var mode := _benched()
	assert_array(Array(mode.player_maps())).contains_exactly([FixtureBaseMode.SMALL_MAP])
	assert_str(mode.default_map()).is_equal(FixtureBaseMode.SMALL_MAP)
	mode.bench_maps = PackedStringArray()
	assert_array(Array(mode.player_maps())).contains_exactly(
		[FixtureBaseMode.MAP, FixtureBaseMode.SMALL_MAP]
	)
	assert_str(mode.default_map()).is_equal(FixtureBaseMode.MAP)
	mode.maps = PackedStringArray()
	assert_str(mode.default_map()).is_empty()


func test_a_bench_must_be_one_of_the_maps_and_players_keep_one() -> void:
	var mode := _benched()
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	mode.bench_maps = PackedStringArray(["fixture://elsewhere"])
	assert_array(Array(ModeCheck.run(mode).errors)).contains(
		["mode: bench map fixture://elsewhere is not one of the mode's maps"]
	)
	mode.bench_maps = mode.maps.duplicate()
	assert_array(Array(ModeCheck.run(mode).errors)).contains(
		["mode: every map is a test bench: players have none"]
	)


func test_a_match_starts_on_the_default_map_never_on_a_bench() -> void:
	var game := Match.new(_benched(), 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.start(0)
	assert_str(game.state.map).is_equal(FixtureBaseMode.SMALL_MAP)


func test_the_lobby_still_takes_a_bench_map_a_bot_asks_for() -> void:
	var game := Match.new(_benched(), 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	FixtureBaseMode.join(game, P1)
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"map": FixtureBaseMode.MAP})
	assert_str(game.state.map).is_equal(FixtureBaseMode.MAP)


## The fixture base mode with its first map, FixtureBaseMode.MAP, a test bench.
func _benched() -> GameMode:
	var mode := FixtureBaseMode.mode()
	mode.bench_maps = PackedStringArray([FixtureBaseMode.MAP])
	return mode
