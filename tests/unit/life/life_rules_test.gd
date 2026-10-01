extends GdUnitTestSuite
## LifeRules (ARCHITECTURE §3.4, §5, §7.1, §9.2): damage, death, the body, the downed player at the
## body with its new epoch, the order Died, Correction, player_died, then the drop, and the
## widening of the downed's view. Driven by the knife's Use (FixtureCombatModes: 50 damage, so
## two hits kill).
## Leaving mid-round: tests/unit/match/phases/round_phase_test.gd.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const NORTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)
const HALF := 50000


func test_a_player_at_zero_health_is_downed_and_its_body_rests_on_the_floor_below() -> void:
	var game := _duel()
	# The victim is in mid-air, at the top of a jump: its body falls to the floor.
	FixtureItemModes.stand(game, P2, Vector3(0, 0.5, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HALF)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.ALIVE)
	_kill_again(game, P1)
	var victim := game.state.player(P2)
	assert_int(victim.health).is_equal(0)
	assert_int(victim.life).is_equal(PlayerState.Life.DOWNED)
	assert_dict(game.state.bodies).is_equal({P2: Vector3(0, 0, 1)})
	var damaged := FixtureCombatModes.received(game, P2, &"Damaged")
	assert_dict(damaged[1].to_dict()).is_equal({"amount": 50000, "health": 0})
	assert_array(Array(game.diagnostics)).is_empty()


func test_died_reaches_everyone_with_the_body_and_names_no_killer() -> void:
	var game := _duel()
	FixtureCombatModes.use(game, P1, NORTH)
	_kill_again(game, P1)
	for peer: int in [P1, P2, P3]:
		var died := FixtureCombatModes.received(game, peer, &"Died")
		assert_array(died).has_size(1)
		assert_dict(died[0].to_dict()).is_equal({"peer": P2, "position": Vector3(0, 0, 1)})


func test_the_downed_player_appears_at_the_body_with_a_new_epoch_told_to_it_alone() -> void:
	var game := _duel()
	FixtureItemModes.stand(game, P2, Vector3(0, 0.4, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	var epoch := game.state.player(P2).epoch
	var others: Dictionary[int, int] = {}
	for peer: int in [P1, P3]:
		others[peer] = FixtureMoves.corrections(game, peer).size()
	var seen := FixtureMoves.corrections(game, P2).size()
	_kill_again(game, P1)
	var downed := game.state.player(P2)
	assert_vector(downed.position).is_equal(Vector3(0, 0, 1))
	assert_int(downed.epoch).is_equal(epoch + 1)
	var corrections := FixtureMoves.corrections(game, P2)
	assert_int(corrections.size()).is_equal(seen + 1)
	assert_dict(corrections[corrections.size() - 1].to_dict()).is_equal(
		{"epoch": epoch + 1, "position": Vector3(0, 0, 1), "velocity": Vector3.ZERO}
	)
	for peer: int in [P1, P3]:
		assert_int(FixtureMoves.corrections(game, peer).size()).is_equal(others[peer])


func test_the_downed_players_honest_claims_pass_and_its_claims_from_life_are_dropped() -> void:
	var game := _duel()
	FixtureCombatModes.use(game, P1, NORTH)
	_kill_again(game, P1)
	var downed := game.state.player(P2)
	var seen := FixtureMoves.corrections(game, P2).size()
	# A claim it sent while alive, still in flight: the old epoch, dropped without a Correction.
	FixtureMoves.claim(game, P2, Vector3(0, 0, 1.2), {"epoch": downed.epoch - 1})
	assert_vector(downed.position).is_equal(Vector3(0, 0, 1))
	# Then it walks and sprints at the ghosts' old speeds (0.2925 and 0.455 m per tick), for free, and
	# jumps from the floor at the body.
	FixtureMoves.steps(game, P2, 5, EAST * 0.29, {"moving": true})
	FixtureMoves.steps(game, P2, 5, EAST * 0.45, FixtureMoves.sprinting())
	FixtureMoves.step(game, P2, Vector3(0, 0.5, 0), FixtureMoves.jumped(game, P2))
	FixtureMoves.step(game, P2, Vector3(0, 0.4, 0), {"on_floor": false})
	FixtureMoves.step(game, P2, Vector3(0, -0.9, 0))
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)
	assert_vector(downed.position).is_equal_approx(Vector3(3.7, 0, 1), Vector3.ONE * 1e-4)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)


func test_a_downed_player_cannot_use_and_nothing_happens() -> void:
	var game := _duel()
	FixtureCombatModes.use(game, P1, NORTH)
	_kill_again(game, P1)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	var swings := FixtureCombatModes.received(game, P3, &"Swung").size()
	FixtureCombatModes.use(game, P2, Vector3(0, 0, -1))
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	assert_int(FixtureCombatModes.received(game, P3, &"Swung").size()).is_equal(swings)


func test_the_fact_comes_before_the_held_item_drops_at_the_body() -> void:
	var game := _duel()
	FixtureItemModes.stand(game, P2, Vector3(0, 0.3, 1))
	var package := FixtureItemModes.lay(game, &"package", Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P2, package)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	var seen := game.view_of(P3).events.size()
	var notes := FixtureModes.notes(game).size()
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureItemModes.names_after(game, P3, seen)).is_equal(
		[&"Swung", &"Died", &"FixtureNote", &"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	(
		assert_array(FixtureModes.notes(game).slice(notes))
		. is_equal(
			[
				"task player_died",
				FixtureRestedNote.text(package.id, &"death", Vector3(0, 0, 1)),
				"task item_rested",
			]
		)
	)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_vector(package.position).is_equal(Vector3(0, 0, 1))
	# The dead player's own events: its Damaged, Died and Correction, then the drop.
	var own := game.view_of(P2).event_names()
	var from := own.rfind(&"Damaged")
	assert_array(own.slice(from, from + 5)).is_equal(
		[&"Damaged", &"Died", &"Correction", &"FixtureNote", &"ItemPlaced"]
	)


func test_killing_the_last_crew_member_over_its_circle_is_a_dissident_win() -> void:
	# The crew's fixture win stands for "every task done" (it holds once any item came to rest,
	# here the package dropping into its circle), the dissidents' for "no crew alive". In the base
	# mode's order: the crew's first (§3.4).
	var game := FixtureCombatModes.in_round(_crew_or_dissidents_mode(), [P1, P2])
	game.state.player(P1).role = &"dissident"
	game.state.player(P2).role = &"crew"
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P2, FixtureItemModes.lay(game, &"package", Vector3(0, 0, 1)))
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.notes(game)).contains(["won dissidents"])
	assert_array(FixtureModes.notes(game)).not_contains(["won crew"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_crew_fixture_win_holds_when_the_package_rests_without_a_death() -> void:
	# The control of the test above: the same package put down wins for the crew.
	var game := FixtureCombatModes.in_round(_crew_or_dissidents_mode(), [P1, P2])
	game.state.player(P1).role = &"dissident"
	game.state.player(P2).role = &"crew"
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P2, FixtureItemModes.lay(game, &"package", Vector3(0, 0, 1)))
	FixtureItemModes.put_down(game, P2, NORTH)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.notes(game)).contains(["won crew"])


func test_the_dead_see_the_downed_from_their_death_and_the_living_never_do() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3, P4])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(3, 0, 3))
	FixtureItemModes.stand(game, P4, Vector3(-3, 0, 3))
	FixtureModes.run_ticks(game, 2)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	var p2_died := game.ticked_through() + 1
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, 3)
	# P3 steps into the zone and dies too; the downed P2 there is not hit.
	FixtureItemModes.stand(game, P3, Vector3(0, 0, 1.2))
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	var p3_died := game.ticked_through() + 1
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, 3)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.DOWNED)
	assert_array(FixtureCombatModes.received(game, P2, &"Damaged")).has_size(2)
	# Written independently of Snapshots: who is downed from which tick, and who sees whom.
	var downed_from := {P2: p2_died, P3: p3_died}
	for viewer: int in [P1, P2, P3, P4]:
		var view := game.view_of(viewer)
		assert_bool(view.snapshots.has(p2_died - 1)).is_true()
		for at_tick: int in view.snapshots:
			var avatars: Dictionary = view.snapshots[at_tick]["avatars"]
			var viewer_dead: bool = downed_from.has(viewer) and at_tick >= downed_from[viewer]
			for other: int in [P1, P2, P3, P4]:
				if other == viewer:
					assert_bool(avatars.has(other)).is_false()
					continue
				var other_dead: bool = downed_from.has(other) and at_tick >= downed_from[other]
				# A living peer never gets a downed player's entity; the downed see everyone.
				var expected := not other_dead or viewer_dead
				(
					assert_bool(avatars.has(other))
					. override_failure_message(
						"tick %d: peer %d sees peer %d" % [at_tick, viewer, other]
					)
					. is_equal(expected)
				)
			if at_tick >= p2_died:
				assert_dict(view.snapshots[at_tick]["bodies"]).contains_keys([P2])


func test_a_death_with_no_floor_below_leaves_the_body_where_the_player_was_and_logs_it() -> void:
	var game := _duel(FlatWorldQuery.new(5.0))
	FixtureCombatModes.use(game, P1, NORTH)
	_kill_again(game, P1)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_dict(game.state.bodies).is_equal({P2: Vector3(0, 0, 1)})
	assert_str(";".join(game.diagnostics)).contains("no floor below")


func test_the_held_item_drops_at_the_body_and_a_missing_floor_is_logged_once() -> void:
	var game := _duel(FlatWorldQuery.new(5.0))
	var carried := FixtureCombatModes.arm(game, P2, Vector3(0, 0, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	_kill_again(game, P1)
	assert_int(carried.where).is_equal(ItemState.Where.GROUND)
	assert_vector(carried.position).is_equal(game.state.bodies[P2])
	assert_int(";".join(game.diagnostics).count("no floor below")).is_equal(1)


## A round of P1, P2 and P3 in `world`: P1 at the origin with a knife, P2 1 m north, P3 away.
func _duel(world: WorldQuery = null) -> Match:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3], world)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	return game


## After a first hit: waits out the cooldown and hits north again.
func _kill_again(game: Match, attacker: int) -> void:
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, attacker, NORTH)


## FixtureCombatModes.basic() whose win conditions are, in order: the crew when peer 0's counter
## `crew_win` is at least 1, which a reaction on item_rested bumps; the dissidents when every
## crew member is dead or left.
func _crew_or_dissidents_mode() -> GameMode:
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
	return mode
