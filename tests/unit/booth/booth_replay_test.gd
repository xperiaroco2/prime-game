extends GdUnitTestSuite
## A print's frames kept for a joiner (#1474; ARCHITECTURE §4.2, §9.5.29): BoothSessions keeps each
## print's FLASH records while any strip it made still exists (the very ItemState, so a vanished
## strip's reused id is not one) and drops them when the last strip vanished; a joiner gets one
## BoothReplay per kept print, to it alone. Driven by FixtureBooth.

const P1 := FixtureBooth.P1
const P2 := FixtureBooth.P2
const P3 := FixtureBooth.P3
const PRINTED := BoothStepEvent.PRINTED


## P1 presses and the whole session runs.
func _session(game: Match, seq := 0) -> void:
	FixtureBooth.press(game, P1, seq)
	FixtureModes.run_ticks(game, FixtureBooth.whole())


## The strips the `nth` print made, as P1 was told.
func _printed(game: Match, nth := 0) -> PackedInt32Array:
	return FixtureBooth.steps_of(game, P1, PRINTED)[nth].items


func test_a_print_is_kept_while_a_strip_of_it_exists() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	_session(game)
	var strips := _printed(game)
	assert_int(BoothSessions.kept_prints(game.state)).is_equal(1)
	game.state.remove_item(strips[0])
	game.state.remove_item(strips[1])
	FixtureModes.run_ticks(game, 1)
	assert_int(BoothSessions.kept_prints(game.state)).is_equal(1)
	game.state.remove_item(strips[2])
	FixtureModes.run_ticks(game, 1)
	assert_int(BoothSessions.kept_prints(game.state)).is_equal(0)
	assert_array(game.diagnostics).is_empty()


func test_a_stopped_session_keeps_nothing() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	assert_array(FixtureBooth.steps_of(game, P2, BoothStepEvent.STOPPED)).has_size(1)
	assert_int(BoothSessions.kept_prints(game.state)).is_equal(0)


func test_a_reset_match_drops_the_kept_prints() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	_session(game)
	game.state.reset_match()
	assert_int(BoothSessions.kept_prints(game.state)).is_equal(0)
