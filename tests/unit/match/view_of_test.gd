extends GdUnitTestSuite
## Match.view_of and the recorded recipients (ARCHITECTURE §5): audiences evaluated at emission,
## per-peer snapshots and speakers per tick, and invariants written independently of the
## audience declarations.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4


func test_recipients_are_recorded_with_every_event() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	for emitted: EmittedEvent in game.emitted():
		var kind := emitted.event.event_name()
		if kind == &"PlayersPlaced":
			assert_array(Array(emitted.recipients)).is_equal([P1, P2])
		elif kind == &"Correction":
			var correction := emitted.event as CorrectionEvent
			assert_array(Array(emitted.recipients)).is_equal([correction.peer])


func test_each_peer_sees_only_its_own_correction() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2, P3])
	for peer: int in [P1, P2, P3]:
		var corrections := game.view_of(peer).events_named(&"Correction")
		assert_int(corrections.size()).is_equal(1)
		assert_int((corrections[0] as CorrectionEvent).peer).is_equal(peer)
		assert_int((corrections[0] as CorrectionEvent).epoch).is_equal(1)
		assert_int(game.view_of(peer).events_named(&"PlayersPlaced").size()).is_equal(1)


func test_audiences_are_evaluated_at_emission() -> void:
	var mode := FixtureModes.basic()
	var to_dissidents := FixtureNote.of("dissidents only")
	to_dissidents.to_role = &"dissident"
	var to_downed := FixtureNote.of("downed only")
	to_downed.to_downed = true
	var to_actor := FixtureNote.of("actor only")
	to_actor.to_actor = true
	mode.actions = [FixtureModes.rule(Intents.USE, [], [to_dissidents, to_downed, to_actor])]
	var game := FixtureModes.in_round(mode, [P1, P2, P3])
	game.state.player(P2).role = &"dissident"
	game.state.player(P3).life = PlayerState.Life.DOWNED
	FixtureModes.send(game, Intents.USE, P1)
	game.state.player(P1).role = &"dissident"
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(_notes_of(game, P1)).is_equal(["actor only", "dissidents only", "actor only"])
	assert_array(_notes_of(game, P2)).is_equal(
		["dissidents only", "dissidents only", "downed only"]
	)
	assert_array(_notes_of(game, P3)).is_equal(["downed only", "downed only"])


func test_a_player_who_left_receives_nothing() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).life = PlayerState.Life.LEFT
	FixtureModes.send(game, Intents.USE, P1)
	assert_array(_notes_of(game, P1)).is_equal(["used"])
	assert_array(_notes_of(game, P2)).is_empty()
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.view_of(P2).snapshots.has(game.ticked_through())).is_false()


func test_a_server_directive_reaches_no_peer() -> void:
	var mode := FixtureModes.basic()
	var directive := FixtureNote.of("to server/")
	directive.to_server = true
	mode.actions = [FixtureModes.rule(Intents.USE, [], [directive])]
	var game := FixtureModes.in_round(mode, [P1])
	FixtureModes.send(game, Intents.USE, P1)
	var last := game.emitted()[game.emitted().size() - 1]
	assert_bool(last.is_directive).is_true()
	assert_array(Array(last.recipients)).is_empty()
	assert_array(_notes_of(game, P1)).is_empty()


func test_a_newcomer_gets_its_rejection_before_it_is_a_player() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1])
	FixtureModes.send(game, Intents.SET_READY, 9, {"ready": true}, 3)
	assert_array(FixtureModes.rejections(game, 9)).is_equal([&"not_accepted"])
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_the_outbox_hands_out_each_event_once() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1])
	var first := game.take_outbox()
	assert_int(first.size()).is_equal(1)
	assert_array(game.take_outbox()).is_empty()
	FixtureModes.send(game, Intents.SET_READY, P1, {"ready": true})
	assert_int(game.take_outbox().size()).is_equal(3)


func test_snapshots_follow_the_visibility_rules() -> void:
	# The downed are public (M4-2); the dead have no avatar, and still get every snapshot.
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2, P3, P4])
	game.state.player(P3).life = PlayerState.Life.DOWNED
	game.state.player(P4).life = PlayerState.Life.DEAD
	FixtureModes.run_ticks(game, 1)
	var at := game.ticked_through()
	var living: Dictionary = game.view_of(P1).snapshots[at]["avatars"]
	assert_array(living.keys()).is_equal([P2, P3])
	assert_bool(living[P2]["downed"]).is_false()
	assert_bool(living[P3]["downed"]).is_true()
	var downed: Dictionary = game.view_of(P3).snapshots[at]["avatars"]
	assert_array(downed.keys()).is_equal([P1, P2])
	var dead: Dictionary = game.view_of(P4).snapshots[at]["avatars"]
	assert_array(dead.keys()).is_equal([P1, P2, P3])
	assert_dict(game.snapshot_for(P2)["avatars"]).contains_keys([P1, P3])
	assert_dict(game.snapshot_for(P2)["avatars"]).not_contains_keys([P2, P4])


func test_snapshots_hold_no_private_numbers() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	FixtureModes.run_ticks(game, 1)
	var avatar: Dictionary = game.view_of(P1).snapshots[game.ticked_through()]["avatars"][P2]
	assert_array(avatar.keys()).is_equal(
		["position", "velocity", "facing", "downed", "invulnerable", "held_item", "belt_item"]
	)


func test_speakers_are_recorded_per_tick() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2, P3])
	FixtureModes.run_ticks(game, 1)
	game.state.player(P3).life = PlayerState.Life.DOWNED
	FixtureModes.run_ticks(game, 1)
	var at := game.ticked_through()
	assert_array(Array(game.view_of(P1).speakers[at - 1])).is_equal([P2, P3])
	assert_array(Array(game.view_of(P1).speakers[at])).is_equal([P2])
	assert_array(Array(game.view_of(P3).speakers[at])).is_empty()
	assert_array(Array(game.speakers_for(P2))).is_equal([P1])


func test_no_event_holds_the_seed() -> void:
	var seed_value := 8_123_456_789
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2], seed_value)
	FixtureModes.send(game, Intents.USE, P1)
	FixtureModes.run_ticks(game, 3)
	var match_seed := game.state.rng.match_seed()
	for peer: int in [P1, P2]:
		var view := game.view_of(peer)
		for event: MatchEvent in view.events:
			var text := var_to_str(event.describe())
			assert_str(text).not_contains(str(seed_value))
			assert_str(text).not_contains(str(match_seed))
		for at: int in view.snapshots:
			assert_str(var_to_str(view.snapshots[at])).not_contains(str(seed_value))


func _notes_of(game: Match, peer: int) -> Array[String]:
	var found: Array[String] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"FixtureNote"):
		found.append((event as FixtureNoteEvent).text)
	return found


func test_the_history_is_kept_only_when_asked() -> void:
	var game := Match.new(FixtureModes.basic(), 7, FlatWorldQuery.new(), FixtureModes.layouts())
	assert_bool(game.keep_history).is_false()
	game.start(0)
	FixtureModes.send(game, Intents.HELLO, 1, {"name": "p1"})
	FixtureModes.run_ticks(game, 2)
	var view := game.view_of(1)
	assert_dict(view.snapshots).is_empty()
	assert_dict(view.speakers).is_empty()
	assert_dict(game.snapshot_for(1)).is_not_empty()


func test_snapshot_for_gives_a_player_who_left_or_a_newcomer_nothing() -> void:
	# Match.snapshot_for, what server/ sends each tick, is empty for anyone but a present player:
	# a player who left, and a connected peer whose Hello was not accepted (§5: a non-player
	# receives at most a Rejected).
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2, P3])
	game.state.player(P2).life = PlayerState.Life.LEFT
	FixtureModes.send(game, Intents.PEER_CONNECTED, 9)
	FixtureModes.run_ticks(game, 1)
	assert_dict(game.snapshot_for(P2)).is_empty()
	assert_dict(game.snapshot_for(9)).is_empty()
	# The recorded history follows present_peers(), not snapshot_for: a second guard, kept as a
	# control that the newcomer's view holds no snapshot either.
	assert_dict(game.view_of(9).snapshots).is_empty()
	# The control: a present player's snapshot holds the others present, never who left.
	var avatars: Dictionary = game.snapshot_for(P1)["avatars"]
	assert_array(avatars.keys()).is_equal([P3])
