extends GdUnitTestSuite
## StartBooth and the session's clock (#1396; ARCHITECTURE §9.4.2, §9.5.29): an Interact at the
## booth starts one session (BoothStep STARTED to everyone, with the presser and the numbers in
## ticks); a second press while it runs, and any press in a phase without BoothTicks (Countdown),
## is refused `unavailable` and starts nothing; the flashes come on the host's clock, exactly
## COUNTDOWN ticks after the press and GAP apart; the presser leaving stops it (STOPPED, no strip);
## readying up stops it with the lobby (StopBooth); ResetMatch's part state drops it. Driven by
## FixtureBooth.

const P1 := FixtureBooth.P1
const P2 := FixtureBooth.P2
const P3 := FixtureBooth.P3
const STARTED := BoothStepEvent.STARTED
const FLASH := BoothStepEvent.FLASH
const PRINTED := BoothStepEvent.PRINTED
const STOPPED := BoothStepEvent.STOPPED


func test_a_press_starts_a_session_that_everyone_hears() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	for peer: int in [P1, P2]:
		var started := FixtureBooth.steps(game, peer)
		assert_array(started).has_size(1)
		assert_int(started[0].step).is_equal(STARTED)
		assert_int(started[0].station).is_equal(FixtureBooth.booth_id(game))
		assert_int(started[0].presser).is_equal(P1)
		assert_int(started[0].frames).is_equal(FixtureBooth.FRAMES)
		assert_int(started[0].countdown).is_equal(FixtureBooth.COUNTDOWN)
		assert_int(started[0].gap).is_equal(FixtureBooth.GAP)
	assert_object(BoothSessions.running(game.state)).is_not_null()


func test_a_second_press_during_a_session_is_unavailable() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1, 1)
	FixtureModes.run_ticks(game, 5)
	FixtureBooth.press(game, P2, 1)
	FixtureBooth.press(game, P1, 2)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable"])
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureBooth.steps_of(game, P2, STARTED)).has_size(1)
	assert_array(game.diagnostics).is_empty()


func test_a_press_out_of_the_booth_is_out_of_reach() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureItemModes.stand(game, P1, FixtureBooth.BOOTH + Vector3(FixtureBooth.RADIUS + 0.5, 0, 0))
	FixtureBooth.press(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"out_of_reach"])
	assert_array(FixtureBooth.steps(game, P1)).is_empty()


func test_a_press_in_the_countdown_is_unavailable() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	assert_str(String(game.current_phase().spec.id)).is_equal("countdown")
	FixtureBooth.press(game, P1, 3)
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(FixtureBooth.steps(game, P2)).is_empty()
	assert_object(BoothSessions.running(game.state)).is_null()


func test_flashes_fire_on_the_host_clock_and_the_print_ends_the_session() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN)
	assert_array(FixtureBooth.steps_of(game, P2, FLASH)).is_empty()
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureBooth.steps_of(game, P2, FLASH)).has_size(1)
	FixtureModes.run_ticks(game, FixtureBooth.GAP - 1)
	assert_array(FixtureBooth.steps_of(game, P2, FLASH)).has_size(1)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureBooth.steps_of(game, P2, FLASH)).has_size(2)
	assert_array(FixtureBooth.steps_of(game, P2, PRINTED)).is_empty()
	FixtureModes.run_ticks(game, FixtureBooth.GAP)
	var flashes := FixtureBooth.steps_of(game, P2, FLASH)
	assert_array(flashes).has_size(FixtureBooth.FRAMES)
	for k in flashes.size():
		assert_int(flashes[k].frame).is_equal(k)
	# The print comes in the last flash's tick, and the session ends.
	assert_array(FixtureBooth.steps_of(game, P2, PRINTED)).has_size(1)
	assert_object(BoothSessions.running(game.state)).is_null()
	assert_array(game.diagnostics).is_empty()


func test_a_press_after_the_print_starts_the_next_strip() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1, 1)
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	FixtureBooth.press(game, P2, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	var started := FixtureBooth.steps_of(game, P1, STARTED)
	assert_array(started).has_size(2)
	assert_int(started[1].strip).is_equal(started[0].strip + 1)
	assert_int(started[1].presser).is_equal(P2)


func test_the_presser_leaving_stops_the_session_with_no_strip() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	assert_array(FixtureBooth.steps_of(game, P2, FLASH)).has_size(1)
	assert_array(FixtureBooth.steps_of(game, P2, STOPPED)).has_size(1)
	assert_array(FixtureBooth.steps_of(game, P2, PRINTED)).is_empty()
	assert_array(game.view_of(P2).events_named(&"ItemSpawned")).is_empty()
	assert_object(BoothSessions.running(game.state)).is_null()
	assert_array(game.diagnostics).is_empty()
	# The booth is free again.
	FixtureBooth.press(game, P2, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()


func test_readying_up_stops_the_session_before_the_countdown() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + 1)
	var from := game.view_of(P2).events.size()
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	var names := FixtureBaseMode.names_since(game, P2, from)
	assert_int(names.find(&"BoothStep")).is_greater_equal(0)
	assert_int(names.find(&"BoothStep")).is_less(names.find(&"PhaseChanged"))
	assert_object(BoothSessions.running(game.state)).is_null()
	# A cancelled countdown brings no session back.
	FixtureBaseMode.ready(game, P1, false, 1)
	assert_str(String(game.current_phase().spec.id)).is_equal("lobby")
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	assert_array(FixtureBooth.steps_of(game, P2, FLASH)).has_size(1)
	assert_array(FixtureBooth.steps_of(game, P2, PRINTED)).is_empty()


func test_stop_booth_with_no_session_emits_nothing() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	assert_array(FixtureBooth.steps(game, P2)).is_empty()
	FixtureLobbyHands.through_countdown(game)
	assert_object(BoothSessions.running(game.state)).is_null()
	assert_dict(game.state.stations).is_empty()
