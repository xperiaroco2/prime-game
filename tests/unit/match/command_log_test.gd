extends GdUnitTestSuite
## CommandLog read back (ARCHITECTURE §4.5, E13): from_dict(to_dict()) is the same log, and
## Match.replay runs it to the same events.


func test_a_log_read_back_is_the_same_log_and_replays() -> void:
	var game := FixtureBaseMode.in_round([1, 2], 11)
	(
		FixtureModes
		. send(
			game,
			Intents.MOVE_CLAIM,
			2,
			{
				"epoch": 2,
				"client_tick": 3,
				"position": Vector3(10.5, 0, 5),
				"velocity": Vector3.ZERO,
				"facing": Vector3.FORWARD,
				"sprint": false,
				"moving": true,
				"on_floor": true,
				"jumps": 0,
			}
		)
	)
	FixtureModes.run_ticks(game, 3)
	var data := game.command_log.to_dict()
	var read := CommandLog.from_dict(data)
	assert_dict(read.to_dict()).is_equal(data)
	assert_int(read.commands.size()).is_equal(game.command_log.commands.size())
	assert_array(read.layouts.keys()).contains_exactly_in_any_order(game.command_log.layouts.keys())
	var replayed := Match.replay(read, FixtureBaseMode.mode())
	assert_array(Array(replayed.refusals)).is_empty()
	assert_dict(replayed.command_log.to_dict()).is_equal(data)
	assert_array(FixtureModes.names(replayed)).is_equal(FixtureModes.names(game))


func test_a_missing_entry_reads_as_its_default() -> void:
	var read := CommandLog.from_dict({})
	assert_int(read.start_tick).is_equal(-1)
	assert_int(read.ticked_through).is_equal(-1)
	assert_array(read.commands).is_empty()
	assert_dict(read.layouts).is_empty()
