extends GdUnitTestSuite
## RoundPhase (ARCHITECTURE §3.5, §9.4): a leave mid-round goes to the life rule (LifeRules.leave):
## life `left`, which counts as dead for the win conditions; no body; PlayerLeft to everyone else;
## the fact player_left before the held item drops on the floor below where the player stood. A
## newcomer that never joined is forgotten silently (2b's JoinRules.forget_newcomer).

const P1 := 1
const P2 := 2
const P3 := 3
const NEWCOMER := 9


func test_a_player_leaving_mid_round_is_left_with_no_body_and_everyone_else_is_told() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3])
	FixtureItemModes.stand(game, P2, Vector3(2, 0, 2))
	var seen: Dictionary[int, int] = {}
	for peer: int in [P1, P2, P3]:
		seen[peer] = game.view_of(peer).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.LEFT)
	assert_dict(game.state.bodies).is_empty()
	for peer: int in [P1, P3]:
		var names := FixtureItemModes.names_after(game, peer, seen[peer])
		assert_array(names).is_equal([&"PlayerLeft", &"FixtureNote"])
		var left := FixtureCombatModes.received(game, peer, &"PlayerLeft")
		assert_dict(left[0].to_dict()).is_equal({"peer": P2})
	assert_int(game.view_of(P2).events.size()).is_equal(seen[P2])
	assert_array(FixtureModes.notes(game)).is_equal(["task player_left"])
	# The avatar is gone from every snapshot from now on.
	FixtureModes.run_ticks(game, 1)
	for peer: int in [P1, P3]:
		var snapshots := game.view_of(peer).snapshots
		var avatars: Dictionary = snapshots[game.ticked_through()]["avatars"]
		assert_bool(avatars.has(P2)).is_false()
		assert_dict(snapshots[game.ticked_through()]["bodies"]).is_empty()


func test_the_held_item_drops_on_the_floor_below_after_the_fact() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2])
	FixtureItemModes.stand(game, P2, Vector3(2, 0, 2))
	var package := FixtureItemModes.lay(game, &"package", Vector3(2, 0, 2))
	FixtureItemModes.pick_up(game, P2, package)
	# The last accepted position is in mid-air, at the top of a jump.
	FixtureItemModes.stand(game, P2, Vector3(2, 0.8, 2))
	var seen := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"PlayerLeft", &"FixtureNote", &"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	(
		assert_array(FixtureModes.notes(game))
		. is_equal(
			[
				"task player_left",
				FixtureRestedNote.text(package.id, &"leave", Vector3(2, 0, 2)),
				"task item_rested",
			]
		)
	)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_vector(package.position).is_equal(Vector3(2, 0, 2))


func test_the_last_crew_member_leaving_over_its_circle_is_a_dissident_win() -> void:
	var mode := FixtureCombatModes.basic()
	mode.reactions = [
		FixtureModes.rule(
			Facts.ITEM_RESTED, [], [FixtureRestedNote.new(), FixtureBump.of(&"crew_win")]
		)
	]
	mode.win_conditions = [
		FixtureModes.win(&"crew", FixtureCounterAtLeast.of(&"crew_win")),
		FixtureModes.win(&"dissidents", FixtureRoleAllDead.of(&"crew")),
	]
	var game := FixtureCombatModes.in_round(mode, [P1, P2])
	game.state.player(P1).role = &"dissident"
	game.state.player(P2).role = &"crew"
	FixtureItemModes.stand(game, P2, Vector3(2, 0, 2))
	FixtureItemModes.pick_up(game, P2, FixtureItemModes.lay(game, &"package", Vector3(2, 0, 2)))
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.notes(game)).contains(["won dissidents"])
	assert_array(FixtureModes.notes(game)).not_contains(["won crew"])


func test_a_downed_player_leaving_keeps_its_body() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureCombatModes.use(game, P1, Vector3(0, 0, 1))
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, Vector3(0, 0, 1))
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.LEFT)
	assert_dict(game.state.bodies).is_equal({P2: Vector3(0, 0, 1)})
	assert_array(FixtureCombatModes.received(game, P1, &"PlayerLeft")).has_size(1)


func test_a_second_leave_changes_nothing() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2])
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	var emitted := game.emitted().size()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_int(game.emitted().size()).is_equal(emitted)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_newcomer_leaving_mid_round_is_forgotten_silently() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1])
	# A peer that connected in the lobby and never said Hello is still a newcomer in the round.
	game.state.newcomers[NEWCOMER] = true
	var emitted := game.emitted().size()
	FixtureModes.send(game, Intents.PEER_LEFT, NEWCOMER)
	assert_bool(game.state.newcomers.has(NEWCOMER)).is_false()
	assert_int(game.emitted().size()).is_equal(emitted)
	assert_array(Array(game.diagnostics)).is_empty()
