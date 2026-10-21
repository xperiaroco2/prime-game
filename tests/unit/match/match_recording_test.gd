extends GdUnitTestSuite
## Match.recording (#1191; ARCHITECTURE §3.3, §4.5.10): off, a match keeps no command, no
## WorldQuery answer and no event take_outbox() handed out, and delivers exactly the events it
## delivers with it on; keep_history still keeps the events for view_of(); turned off late, it
## drops what it kept; it never comes back on.

const SEED := 11
const PEERS: Array[int] = [1, 2]


func test_recording_is_on_by_default() -> void:
	var game := _match()
	assert_bool(game.recording).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_off_it_keeps_nothing_that_grows_and_delivers_the_same_events() -> void:
	var kept := _match()
	var light := _match()
	light.recording = false
	var kept_delivered := _play(kept)
	var light_delivered := _play(light)
	# With it on (the default) the match keeps all three, so their absence below is the flag's.
	assert_int(kept.command_log.commands.size()).is_equal(PEERS.size() * 2)
	assert_array(kept.command_log.world_answers).is_not_empty()
	assert_array(_described(kept.emitted())).is_equal(kept_delivered)
	assert_array(kept_delivered).is_not_empty()
	assert_array(light.command_log.commands).is_empty()
	assert_array(light.command_log.world_answers).is_empty()
	assert_array(light.emitted()).is_empty()
	assert_array(light_delivered).is_equal(kept_delivered)
	assert_int(light.ticked_through()).is_equal(kept.ticked_through())
	assert_int(light.command_log.ticked_through).is_equal(kept.ticked_through())
	assert_str(String(light.phase_id())).is_equal(String(kept.phase_id()))
	assert_array(Array(light.diagnostics)).is_empty()


func test_off_the_events_not_handed_out_yet_stay_until_take_outbox() -> void:
	var game := _match()
	game.recording = false
	game.start(0)
	_hello(game, 1)
	var waiting := _described(game.emitted())
	assert_array(waiting).is_not_empty()
	assert_array(_described(game.take_outbox())).is_equal(waiting)
	assert_array(game.emitted()).is_empty()
	assert_array(game.take_outbox()).is_empty()


func test_keep_history_keeps_the_events_for_view_of_with_recording_off() -> void:
	var game := _match()
	game.recording = false
	game.keep_history = true
	var delivered := _play(game)
	assert_array(_described(game.emitted())).is_equal(delivered)
	assert_array(game.view_of(2).events).is_not_empty()
	assert_array(game.command_log.commands).is_empty()
	assert_array(game.command_log.world_answers).is_empty()


func test_turned_off_late_it_drops_what_it_kept() -> void:
	var game := _match()
	game.start(0)
	game.take_outbox()
	var handed_out := game.emitted().size()
	assert_int(handed_out).is_greater(0)
	for peer: int in PEERS:
		_hello(game, peer)
	for peer: int in PEERS:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(String(game.phase_id())).is_not_equal("lobby")
	var outbox := _described(game.emitted().slice(handed_out))
	assert_array(outbox).is_not_empty()
	assert_array(game.command_log.commands).is_not_empty()
	game.recording = false
	assert_bool(game.recording).is_false()
	assert_array(game.command_log.commands).is_empty()
	assert_array(game.command_log.world_answers).is_empty()
	# Only what the outbox still holds stays, and it is still handed out.
	assert_array(_described(game.emitted())).is_equal(outbox)
	assert_array(_described(game.take_outbox())).is_equal(outbox)
	assert_array(game.emitted()).is_empty()


func test_it_never_comes_back_on() -> void:
	var game := _match()
	game.recording = false
	game.recording = true
	assert_bool(game.recording).is_false()
	assert_int(game.diagnostics.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("cannot come back on")


func test_a_recorded_match_still_replays() -> void:
	var game := _match()
	_play(game)
	var replayed := Match.replay(game.command_log, _mode())
	assert_array(Array(replayed.refusals)).is_empty()
	assert_array(Array(replayed.diagnostics)).is_empty()
	assert_array(FixtureModes.describe(replayed)).is_equal(FixtureModes.describe(game))


## FixtureModes.basic() whose lobby -> round row asks the world for a floor (an answer to keep).
func _mode() -> GameMode:
	var mode := FixtureModes.basic()
	mode.transitions[0].actions.push_front(FixtureAskFloor.new())
	return mode


func _match() -> Match:
	return Match.new(_mode(), SEED, FlatWorldQuery.new(), FixtureModes.layouts())


func _hello(game: Match, peer: int) -> void:
	FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})


## Starts `game`, joins PEERS, readies them into the round (the row asks the world) and runs 20
## ticks, taking the outbox after every call as HostSession does; what it handed out, described.
func _play(game: Match) -> Array[Dictionary]:
	var delivered: Array[Dictionary] = []
	game.start(0)
	delivered.append_array(_described(game.take_outbox()))
	for peer: int in PEERS:
		_hello(game, peer)
		delivered.append_array(_described(game.take_outbox()))
	for peer: int in PEERS:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
		delivered.append_array(_described(game.take_outbox()))
	for _i in 20:
		game.tick(game.ticked_through() + 1)
		delivered.append_array(_described(game.take_outbox()))
	return delivered


func _described(events: Array[EmittedEvent]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for emitted: EmittedEvent in events:
		found.append(emitted.describe())
	return found
