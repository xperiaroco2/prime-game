extends GdUnitTestSuite
## A print's frames kept for a joiner (#1474; ARCHITECTURE §4.2, §9.5.29): BoothSessions keeps each
## print's FLASH records while any strip it made still exists (the very ItemState, so a vanished
## strip's reused id is not one) and drops them when the last strip vanished; a joiner gets one
## BoothReplay per kept print, to it alone. Driven by FixtureBooth.

const P1 := FixtureBooth.P1
const P2 := FixtureBooth.P2
const P3 := FixtureBooth.P3
const PRINTED := BoothStepEvent.PRINTED
const JOINER := 4


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


## The BoothReplay events `peer` received, in order.
func _replays(game: Match, peer: int) -> Array[BoothReplayEvent]:
	var found: Array[BoothReplayEvent] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"BoothReplay"):
		found.append(event as BoothReplayEvent)
	return found


## The FLASH records P1 was sent for session `strip`, in frame order.
func _flashes(game: Match, strip: int) -> Array:
	var found: Array = []
	for flash: BoothStepEvent in FixtureBooth.steps_of(game, P1, BoothStepEvent.FLASH):
		if flash.strip == strip:
			found.append(flash.record)
	return found


func test_a_joiner_gets_a_print_s_frames_and_its_strips_alone() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	_session(game)
	var printed: BoothStepEvent = FixtureBooth.steps_of(game, P1, PRINTED)[0]
	FixtureBaseMode.join(game, JOINER)
	var replays := _replays(game, JOINER)
	assert_array(replays).has_size(1)
	var replay := replays[0]
	assert_int(replay.peer).is_equal(JOINER)
	assert_int(replay.station).is_equal(FixtureBooth.booth_id(game))
	assert_int(replay.strip).is_equal(printed.strip)
	assert_int(replay.records.size()).is_equal(FixtureBooth.FRAMES)
	assert_array(replay.records).is_equal(_flashes(game, printed.strip))
	assert_array(Array(replay.items)).is_equal(Array(printed.items))
	for peer: int in [P1, P2, P3]:
		assert_array(_replays(game, peer)).is_empty()
	assert_array(game.diagnostics).is_empty()


func test_two_prints_replay_in_print_order() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	_session(game)
	_session(game, 1)
	FixtureBaseMode.join(game, JOINER)
	var replays := _replays(game, JOINER)
	assert_array(replays).has_size(2)
	assert_array(Array(replays[0].items)).is_equal(Array(_printed(game, 0)))
	assert_array(Array(replays[1].items)).is_equal(Array(_printed(game, 1)))
	assert_int(replays[1].strip).is_equal((replays[0].strip + 1) % BoothSessions.STRIP_IDS)


func test_a_replay_lists_only_the_strips_left_and_none_when_all_vanished() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2, P3])
	_session(game)
	var strips := _printed(game)
	game.state.remove_item(strips[1])
	FixtureBaseMode.join(game, JOINER)
	assert_array(Array(_replays(game, JOINER)[0].items)).is_equal([strips[0], strips[2]])
	var other := JOINER + 1
	FixtureModes.send(game, Intents.PEER_LEFT, JOINER)
	game.state.remove_item(strips[0])
	game.state.remove_item(strips[2])
	FixtureBaseMode.join(game, other)
	assert_array(_replays(game, other)).is_empty()
	assert_int(BoothSessions.kept_prints(game.state)).is_equal(0)


## The guard: a vanished strip's id given to a new item is not that strip, so the print it came
## from is dropped and not replayed (an id check alone would list the new item).
func test_a_strip_id_reused_by_a_new_item_is_not_replayed() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1])
	_session(game)
	var strip: ItemState = game.state.items[_printed(game)[0]]
	game.state.remove_item(strip.id)
	var reused := ItemState.new(strip.id, strip.kind, FixtureBooth.BOOTH)
	game.state.items[strip.id] = reused
	FixtureBaseMode.join(game, JOINER)
	assert_array(_replays(game, JOINER)).is_empty()
	assert_int(BoothSessions.kept_prints(game.state)).is_equal(0)


func test_a_joiner_mid_session_gets_the_frames_taken_so_far_without_strips() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	FixtureBooth.press(game, P1)
	FixtureModes.run_ticks(game, FixtureBooth.COUNTDOWN + FixtureBooth.GAP + 1)
	FixtureBaseMode.join(game, JOINER)
	var replays := _replays(game, JOINER)
	assert_array(replays).has_size(1)
	var strip: int = FixtureBooth.steps_of(game, P1, BoothStepEvent.STARTED)[0].strip
	assert_int(replays[0].strip).is_equal(strip)
	assert_int(replays[0].records.size()).is_equal(2)
	assert_array(replays[0].records).is_equal(_flashes(game, strip))
	assert_int(replays[0].items.size()).is_equal(0)
	# The rest comes as everyone gets it: the last FLASH and the PRINTED.
	FixtureModes.run_ticks(game, FixtureBooth.whole())
	assert_array(FixtureBooth.steps_of(game, JOINER, PRINTED)).has_size(1)
	assert_array(_replays(game, JOINER)).has_size(1)


func test_a_joiner_in_the_countdown_gets_the_replay_too() -> void:
	var game := FixtureBooth.in_booth(FixtureBooth.mode(), [P1, P2])
	_session(game)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	assert_str(String(game.current_phase().spec.id)).is_equal("countdown")
	FixtureBaseMode.join(game, JOINER)
	assert_array(_replays(game, JOINER)).has_size(1)
	assert_array(game.diagnostics).is_empty()


func test_a_join_in_a_mode_without_a_booth_makes_no_booth_state() -> void:
	var game := FixtureBaseMode.started()
	game.keep_history = true
	FixtureBaseMode.join(game, P1)
	assert_array(_replays(game, P1)).is_empty()
	assert_bool(game.state.has_part_state(BoothSessions.PART_KEY)).is_false()
