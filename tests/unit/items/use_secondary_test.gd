extends GdUnitTestSuite
## UseSecondary (ARCHITECTURE §4.1, #1438): an item's own action on the right mouse button. It is
## routed as Use is (the held item's kind, then the role, then the mode, §9.2), but a rule runs only
## on the intent its trigger names: Use never runs a UseSecondary rule, nor the reverse. Only the
## living send it (Intents.PLAYER_ACTIONS). Built on FixtureItemModes.basic() (`tool` has a Use
## rule), with the kinds `cup` (a UseSecondary rule only) and `both` (one rule of each), and Round
## accepting UseSecondary from the living.

const P1 := 1
const P2 := 2
const HERE := Vector3.ZERO
const FACING := {"facing": Vector3.FORWARD}


func test_use_secondary_runs_the_held_item_s_own_rule() -> void:
	var game := _holding(&"cup")
	FixtureModes.send(game, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.notes(game)).is_equal(["cup sipped"])
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_use_does_not_run_a_use_secondary_rule_nor_the_reverse() -> void:
	var cup := _holding(&"cup")
	FixtureModes.send(cup, Intents.USE, P1, FACING)
	assert_array(FixtureModes.notes(cup)).is_empty()
	assert_array(FixtureModes.rejections(cup, P1)).is_equal([RejectReasons.NOTHING_TO_DO])
	var tool := _holding(&"tool")
	FixtureModes.send(tool, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.notes(tool)).is_empty()
	assert_array(FixtureModes.rejections(tool, P1)).is_equal([RejectReasons.NOTHING_TO_DO])


func test_a_kind_with_both_rules_runs_only_the_sent_intent_s() -> void:
	var game := _holding(&"both")
	FixtureModes.send(game, Intents.USE_SECONDARY, P1, FACING)
	FixtureModes.send(game, Intents.USE, P1, FACING)
	FixtureModes.send(game, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.notes(game)).is_equal(["both sipped", "both used", "both sipped"])


func test_an_empty_hand_and_a_belted_item_do_nothing() -> void:
	var empty := _game()
	FixtureModes.send(empty, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.rejections(empty, P1)).is_equal([RejectReasons.NOTHING_TO_DO])
	var belted := _game(FixtureItemModes.swapping(_mode()))
	var cup := FixtureItemModes.lay(belted, &"cup", HERE)
	FixtureItemModes.pick_up(belted, P1, cup)
	FixtureItemModes.swap(belted, P1)
	assert_int(belted.state.player(P1).belt_item).is_equal(cup.id)
	FixtureModes.send(belted, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.notes(belted)).is_empty()
	assert_array(FixtureModes.rejections(belted, P1)).is_equal([RejectReasons.NOTHING_TO_DO])


func test_the_mode_s_rule_runs_when_the_held_kind_has_none() -> void:
	var mode := _mode()
	mode.actions.append(FixtureModes.rule(Intents.USE_SECONDARY, [], [FixtureNote.of("mode")]))
	var tool := _game(mode)
	FixtureItemModes.pick_up(tool, P1, FixtureItemModes.lay(tool, &"tool", HERE))
	FixtureModes.send(tool, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.notes(tool)).is_equal(["mode"])
	# The held kind's own rule goes first (§9.2): the mode's is not tried.
	var cup := _game(_mode_with_rule())
	FixtureItemModes.pick_up(cup, P1, FixtureItemModes.lay(cup, &"cup", HERE))
	FixtureModes.send(cup, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.notes(cup)).is_equal(["cup sipped"])


func test_a_dead_downed_or_limp_sender_is_not_accepted() -> void:
	for life: PlayerState.Life in [PlayerState.Life.DOWNED, PlayerState.Life.DEAD]:
		var game := _holding(&"cup")
		game.state.player(P1).life = life
		FixtureModes.send(game, Intents.USE_SECONDARY, P1, FACING)
		assert_array(FixtureModes.notes(game)).is_empty()
		assert_array(FixtureModes.rejections(game, P1)).is_equal([RejectReasons.NOT_ACCEPTED])
	var limp := _holding(&"cup")
	FixtureHandOverModes.make_limp(limp, P1)
	FixtureModes.send(limp, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.notes(limp)).is_empty()
	assert_array(FixtureModes.rejections(limp, P1)).is_equal([RejectReasons.NOT_ACCEPTED])


func test_a_phase_without_the_accept_row_is_not_accepted() -> void:
	var mode := _mode()
	var round_spec := mode.find_phase(&"round")
	for accept: AcceptSpec in round_spec.accepts.duplicate():
		if accept.intent == Intents.USE_SECONDARY:
			round_spec.accepts.erase(accept)
	var game := _game(mode)
	FixtureItemModes.pick_up(game, P1, FixtureItemModes.lay(game, &"cup", HERE))
	FixtureModes.send(game, Intents.USE_SECONDARY, P1, FACING)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([RejectReasons.NOT_ACCEPTED])


func test_each_peer_sees_only_what_the_rule_s_events_show() -> void:
	var game := _holding(&"cup")
	var seen := game.view_of(P2).events.size()
	FixtureModes.send(game, Intents.USE_SECONDARY, P1, FACING)
	var notes := game.view_of(P1).events_named(&"FixtureNote")
	assert_array(notes).has_size(1)
	assert_str((notes[0] as FixtureNoteEvent).text).is_equal("cup sipped")
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_empty()


func test_it_is_a_player_action_with_a_facing() -> void:
	assert_bool(Intents.ALL.has(Intents.USE_SECONDARY)).is_true()
	assert_bool(Intents.PLAYER_ACTIONS.has(Intents.USE_SECONDARY)).is_true()
	assert_dict(Intents.FIELDS[Intents.USE_SECONDARY]).is_equal({"facing": TYPE_VECTOR3})


## FixtureItemModes.basic() with `cup` (UseSecondary notes "cup sipped" to its user) and `both`
## (Use notes "both used", UseSecondary "both sipped"), Round accepting UseSecondary from the
## living.
func _mode() -> GameMode:
	var mode := FixtureItemModes.basic()
	var sipped := FixtureNote.of("cup sipped")
	sipped.to_actor = true
	mode.item_kinds.append(
		FixtureItemModes.item_kind(&"cup", [FixtureModes.rule(Intents.USE_SECONDARY, [], [sipped])])
	)
	(
		mode
		. item_kinds
		. append(
			(
				FixtureItemModes
				. item_kind(
					&"both",
					[
						FixtureModes.rule(Intents.USE, [], [FixtureNote.of("both used")]),
						FixtureModes.rule(
							Intents.USE_SECONDARY, [], [FixtureNote.of("both sipped")]
						),
					]
				)
			)
		)
	)
	mode.find_phase(&"round").accepts.append(
		AcceptSpec.of(Intents.USE_SECONDARY, AcceptSpec.From.LIVING)
	)
	return mode


func _mode_with_rule() -> GameMode:
	var mode := _mode()
	mode.actions.append(FixtureModes.rule(Intents.USE_SECONDARY, [], [FixtureNote.of("mode")]))
	return mode


func _game(mode: GameMode = null) -> Match:
	var game := FixtureItemModes.in_round(mode if mode != null else _mode(), [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	FixtureItemModes.stand(game, P2, Vector3(5, 0, 0))
	return game


func _holding(kind_id: StringName) -> Match:
	var game := _game()
	FixtureItemModes.pick_up(game, P1, FixtureItemModes.lay(game, kind_id, HERE))
	assert_int(game.state.player(P1).held_item).is_not_equal(-1)
	return game
