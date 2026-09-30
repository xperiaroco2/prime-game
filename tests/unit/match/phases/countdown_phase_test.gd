extends GdUnitTestSuite
## Countdown (ARCHITECTURE §3.2, §3.5, §9.4): `countdown_done` on its end tick; cancelled by
## SetReady(false), a join or a leave, with CountdownCancelled(reason), and no row actions, so
## after a leave `all_ready` fires again on entry.

const P1 := 1
const P2 := 2
const P3 := 3


func test_the_countdown_ends_on_its_announced_tick() -> void:
	var game := FixtureBaseMode.in_countdown([P1, P2])
	var end := (game.view_of(P1).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent).end_tick
	assert_int(end).is_equal(game.current_phase().entered_tick + 100)
	while game.ticked_through() < end - 1:
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("countdown")
	FixtureModes.run_ticks(game, 1)
	assert_int(game.ticked_through()).is_equal(end)
	assert_str(game.phase_id()).is_equal("loading")


func test_un_ready_cancels_and_the_other_flags_stay() -> void:
	var game := FixtureBaseMode.in_countdown([P1, P2])
	var from := game.view_of(P1).events.size()
	FixtureBaseMode.ready(game, P2, false)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_array(FixtureBaseMode.names_since(game, P1, from)).is_equal(
		[&"ReadyChanged", &"CountdownCancelled", &"PhaseChanged"]
	)
	var cancelled := game.view_of(P1).events_named(&"CountdownCancelled")[0]
	assert_str((cancelled as CountdownCancelledEvent).reason).is_equal("un_ready")
	assert_bool(game.state.player(P1).ready).is_true()
	assert_bool(game.state.player(P2).ready).is_false()


func test_set_ready_true_is_not_accepted_in_the_countdown() -> void:
	var game := FixtureBaseMode.in_countdown([P1])
	FixtureBaseMode.ready(game, P1, true, 3)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_str(game.phase_id()).is_equal("countdown")


func test_a_malformed_set_ready_is_rejected_and_does_not_cancel() -> void:
	# A missing or non-bool `ready` is never read as SetReady(false).
	var game := FixtureBaseMode.in_countdown([P1, P2])
	FixtureModes.send(game, Intents.SET_READY, P2, {}, 1)
	FixtureModes.send(game, Intents.SET_READY, P2, {"ready": 0}, 2)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"bad_args", &"bad_args"])
	assert_str(game.phase_id()).is_equal("countdown")
	assert_bool(game.state.player(P2).ready).is_true()


func test_settings_are_locked_in_the_countdown() -> void:
	var game := FixtureBaseMode.in_countdown([P1])
	FixtureModes.send(game, Intents.CHANGE_SETTINGS, P1, {"settings": {"knives": 1}})
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_int(game.state.settings[&"knives"]).is_equal(2)


func test_a_join_cancels() -> void:
	var game := FixtureBaseMode.in_countdown([P1])
	var from := game.view_of(P1).events.size()
	FixtureBaseMode.join(game, P2)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_array(FixtureBaseMode.names_since(game, P1, from)).is_equal(
		[&"PlayerJoined", &"SettingsChanged", &"CountdownCancelled", &"PhaseChanged"]
	)
	assert_array(game.view_of(P2).event_names()).is_equal(
		[&"Welcome", &"PlayerJoined", &"SettingsChanged", &"CountdownCancelled", &"PhaseChanged"]
	)
	var cancelled := game.view_of(P2).events_named(&"CountdownCancelled")[0]
	assert_str((cancelled as CountdownCancelledEvent).reason).is_equal("join")
	assert_bool(game.state.player(P1).ready).is_true()


func test_a_leave_cancels_and_the_countdown_restarts_on_entry() -> void:
	var game := FixtureBaseMode.in_countdown([P1, P2, P3])
	var first_entry := game.current_phase().entered_tick
	var spot := game.state.player(P1).position
	FixtureModes.run_ticks(game, 10)
	var from := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	(
		assert_array(FixtureBaseMode.names_since(game, P1, from))
		. is_equal(
			[
				&"PlayerLeft",
				&"SettingsChanged",
				&"CountdownCancelled",
				&"PhaseChanged",
				&"PhaseChanged",
			]
		)
	)
	var cancelled := game.view_of(P1).events_named(&"CountdownCancelled")[0]
	assert_str((cancelled as CountdownCancelledEvent).reason).is_equal("leave")
	# No row actions: nobody was placed, and the lobby's all_ready fired on entry.
	assert_str(game.phase_id()).is_equal("countdown")
	assert_vector(game.state.player(P1).position).is_equal(spot)
	assert_int(game.state.player(P1).epoch).is_equal(1)
	var restarted := game.view_of(P1).events_named(&"PhaseChanged")[-1] as PhaseChangedEvent
	assert_int(restarted.end_tick).is_equal(first_entry + 10 + 100)
	assert_array(FixtureBaseMode.directives(game)).is_equal(["AllowJoins", "AllowJoins"])


func test_a_newcomer_leaving_does_not_cancel() -> void:
	var game := FixtureBaseMode.in_countdown([P1])
	FixtureModes.send(game, Intents.PEER_CONNECTED, P2)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_str(game.phase_id()).is_equal("countdown")
