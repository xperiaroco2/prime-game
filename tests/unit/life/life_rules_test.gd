extends GdUnitTestSuite
## LifeRules and LifeTicks (ARCHITECTURE §3.4, §3.5, §5, §7.1, §9.2), every transition of the life
## states: living to downed at 0 health (KnockedDown to everyone, the private Correction with a new
## epoch, nothing drops, no body), downed to dead when the knockdown time runs out (Died to
## everyone, the body, no Correction, player_died before the drop), and leaving while living,
## downed or dead (no body). Also what the downed and the dead may do and who sees them. Driven by
## the knife's Use (FixtureCombatModes: 50 damage, so two hits knock down) and the fixture's
## knockdown time of 10 s (200 ticks).
## Leaving while living: tests/unit/match/phases/round_phase_test.gd.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const NORTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)
const HALF := 50000
## The fixture's knockdown time in host ticks: 10 s at 20 Hz.
const KNOCKDOWN_TICKS := 200


func test_a_player_at_zero_health_is_knocked_down_on_the_floor_below_and_keeps_its_hand() -> void:
	var game := _duel()
	var package := FixtureItemModes.lay(game, &"package", Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P2, package)
	# The victim is in mid-air, at the top of a jump: it lies on the floor below.
	FixtureItemModes.stand(game, P2, Vector3(0, 0.5, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HALF)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.ALIVE)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	var knocked_at := game.ticked_through() + 1
	FixtureCombatModes.use(game, P1, NORTH)
	var victim := game.state.player(P2)
	assert_int(victim.health).is_equal(0)
	assert_int(victim.life).is_equal(PlayerState.Life.DOWNED)
	assert_vector(victim.position).is_equal(Vector3(0, 0, 1))
	assert_int(victim.life_deadline).is_equal(knocked_at + KNOCKDOWN_TICKS)
	# Nothing drops and nobody has a body yet.
	assert_int(package.holder).is_equal(P2)
	assert_int(package.where).is_equal(ItemState.Where.HAND)
	assert_dict(game.state.bodies).is_empty()
	assert_array(FixtureCombatModes.received(game, P3, &"ItemPlaced")).is_empty()
	var damaged := FixtureCombatModes.received(game, P2, &"Damaged")
	assert_dict(damaged[1].to_dict()).is_equal({"amount": 50000, "health": 0})
	assert_array(Array(game.diagnostics)).is_empty()


func test_knocked_down_reaches_everyone_and_names_no_attacker_and_nobody_died() -> void:
	var game := _duel()
	_knock_down(game)
	for peer: int in [P1, P2, P3]:
		var knocked := FixtureCombatModes.received(game, peer, &"KnockedDown")
		assert_array(knocked).has_size(1)
		assert_dict(knocked[0].to_dict()).is_equal({"peer": P2, "position": Vector3(0, 0, 1)})
		assert_array(FixtureCombatModes.received(game, peer, &"Died")).is_empty()
	assert_array(FixtureModes.notes(game)).is_empty()


func test_the_downed_player_gets_a_new_epoch_told_to_it_alone() -> void:
	var game := _duel()
	FixtureItemModes.stand(game, P2, Vector3(0, 0.4, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	var epoch := game.state.player(P2).epoch
	var others: Dictionary[int, int] = {}
	for peer: int in [P1, P3]:
		others[peer] = FixtureMoves.corrections(game, peer).size()
	var seen := FixtureMoves.corrections(game, P2).size()
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	var downed := game.state.player(P2)
	assert_int(downed.epoch).is_equal(epoch + 1)
	var corrections := FixtureMoves.corrections(game, P2)
	assert_int(corrections.size()).is_equal(seen + 1)
	assert_dict(corrections[corrections.size() - 1].to_dict()).is_equal(
		{"epoch": epoch + 1, "position": Vector3(0, 0, 1), "velocity": Vector3.ZERO}
	)
	for peer: int in [P1, P3]:
		assert_int(FixtureMoves.corrections(game, peer).size()).is_equal(others[peer])
	# KnockedDown, then the Correction, in the downed player's own events.
	var own := game.view_of(P2).event_names()
	var at := own.find(&"KnockedDown")
	assert_array(own.slice(at, at + 2)).is_equal([&"KnockedDown", &"Correction"])


func test_the_downed_crawl_and_their_walking_claims_in_flight_are_dropped_as_stale() -> void:
	var game := _duel()
	_knock_down(game)
	var downed := game.state.player(P2)
	var seen := FixtureMoves.corrections(game, P2).size()
	# A walking claim it sent while living, still in flight: the old epoch, dropped silently.
	FixtureMoves.claim(game, P2, Vector3(0, 0, 1.2), {"epoch": downed.epoch - 1})
	assert_vector(downed.position).is_equal(Vector3(0, 0, 1))
	# Then it crawls at 1 m/s (0.05 m per tick), holding sprint or not.
	FixtureMoves.steps(game, P2, 5, EAST * 0.05, {"moving": true})
	FixtureMoves.steps(game, P2, 5, EAST * 0.05, FixtureMoves.sprinting())
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)
	assert_vector(downed.position).is_equal_approx(Vector3(0.5, 0, 1), Vector3.ONE * 1e-4)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)


func test_strikes_skip_a_downed_player() -> void:
	var game := _duel()
	_knock_down(game)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	var swings := FixtureCombatModes.received(game, P3, &"Swung").size()
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(FixtureCombatModes.received(game, P3, &"Swung").size()).is_equal(swings + 1)
	assert_array(FixtureCombatModes.received(game, P2, &"Damaged")).has_size(2)
	assert_array(FixtureCombatModes.received(game, P2, &"KnockedDown")).has_size(1)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_downed_player_cannot_use_pick_up_or_put_down() -> void:
	var game := _duel()
	var knife := FixtureCombatModes.arm(game, P2, Vector3(0, 0, 1))
	_knock_down(game)
	var lying := FixtureItemModes.lay(game, &"package", Vector3(0.5, 0, 1))
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	var swings := FixtureCombatModes.received(game, P3, &"Swung").size()
	FixtureCombatModes.use(game, P2, Vector3(0, 0, -1))
	FixtureItemModes.pick_up(game, P2, lying)
	FixtureItemModes.put_down(game, P2, EAST)
	assert_array(FixtureModes.rejections(game, P2)).is_equal(
		[&"not_accepted", &"not_accepted", &"not_accepted"]
	)
	assert_int(FixtureCombatModes.received(game, P3, &"Swung").size()).is_equal(swings)
	assert_int(knife.holder).is_equal(P2)
	assert_int(lying.where).is_equal(ItemState.Where.GROUND)


func test_the_knockdown_runs_out_after_its_time_and_the_player_dies_where_it_lay() -> void:
	var game := _duel()
	_knock_down(game)
	var deadline := game.state.player(P2).life_deadline
	FixtureMoves.steps(game, P2, 4, EAST * 0.05, {"moving": true})
	var corrections := FixtureMoves.corrections(game, P2).size()
	FixtureModes.run_ticks(game, deadline - 1 - game.ticked_through())
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_array(FixtureCombatModes.received(game, P1, &"Died")).is_empty()
	FixtureModes.run_ticks(game, 1)
	var dead := game.state.player(P2)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_int(dead.life_deadline).is_equal(-1)
	var body := Vector3(0.2, 0, 1)
	assert_dict(game.state.bodies).is_equal({P2: body})
	for peer: int in [P1, P2, P3]:
		var died := FixtureCombatModes.received(game, peer, &"Died")
		assert_array(died).has_size(1)
		assert_dict(died[0].to_dict()).is_equal({"peer": P2, "position": body})
	# No Correction at a death: the dead send no claims.
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(corrections)
	assert_array(Array(game.diagnostics)).is_empty()


func test_at_the_death_the_fact_comes_before_the_held_item_drops_at_the_body() -> void:
	var game := _duel()
	FixtureItemModes.stand(game, P2, Vector3(0, 0.3, 1))
	var package := FixtureItemModes.lay(game, &"package", Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P2, package)
	_knock_down(game)
	assert_array(FixtureModes.notes(game)).is_empty()
	var seen := game.view_of(P3).events.size()
	# The knockdown's tick is run first: its SelfStatus flush goes to P2 before the death.
	FixtureModes.run_ticks(game, 1)
	var own_seen := game.view_of(P2).events.size()
	_run_out(game)
	assert_array(FixtureItemModes.names_after(game, P3, seen)).is_equal(
		[&"Died", &"FixtureNote", &"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)
	(
		assert_array(FixtureModes.notes(game))
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
	# The dead player's own events: its Died, then the drop; no Correction.
	assert_array(FixtureItemModes.names_after(game, P2, own_seen).slice(0, 3)).is_equal(
		[&"Died", &"FixtureNote", &"ItemPlaced"]
	)
	assert_array(FixtureItemModes.names_after(game, P2, own_seen)).not_contains([&"Correction"])


func test_the_dead_send_no_accepted_intent() -> void:
	var game := _duel()
	var knife := FixtureCombatModes.arm(game, P2, Vector3(0, 0, 1))
	_kill(game)
	var lying := FixtureItemModes.lay(game, &"package", Vector3(0.5, 0, 1))
	var dead := game.state.player(P2)
	var emitted := game.emitted().size()
	# A MoveClaim is dropped silently (E15): no Rejected, no Correction, no move.
	FixtureMoves.claim(game, P2, Vector3(0.2, 0, 1))
	assert_int(game.emitted().size()).is_equal(emitted)
	assert_vector(dead.position).is_equal(Vector3(0, 0, 1))
	FixtureCombatModes.use(game, P2, NORTH)
	FixtureItemModes.pick_up(game, P2, lying)
	FixtureItemModes.put_down(game, P2, EAST)
	assert_array(FixtureModes.rejections(game, P2)).is_equal(
		[&"not_accepted", &"not_accepted", &"not_accepted"]
	)
	assert_int(lying.where).is_equal(ItemState.Where.GROUND)
	assert_int(knife.where).is_equal(ItemState.Where.GROUND)
	assert_array(FixtureCombatModes.received(game, P3, &"Swung")).has_size(2)


func test_the_downed_are_public_and_the_dead_have_no_avatar_but_keep_their_snapshots() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3, P4])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(3, 0, 3))
	FixtureItemModes.stand(game, P4, Vector3(-3, 0, 3))
	FixtureModes.run_ticks(game, 2)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	var downed_from := game.ticked_through() + 1
	FixtureCombatModes.use(game, P1, NORTH)
	var dead_from := game.state.player(P2).life_deadline
	FixtureModes.run_ticks(game, dead_from + 3 - game.ticked_through())
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	# Written independently of Snapshots: who is downed and dead from which tick, and who sees whom.
	for viewer: int in [P1, P2, P3, P4]:
		var view := game.view_of(viewer)
		assert_bool(view.snapshots.has(downed_from - 1)).is_true()
		assert_bool(view.snapshots.has(dead_from + 3)).is_true()
		for at_tick: int in view.snapshots:
			var avatars: Dictionary = view.snapshots[at_tick]["avatars"]
			for other: int in [P1, P2, P3, P4]:
				var dead: bool = other == P2 and at_tick >= dead_from
				# Everyone sees every other living or downed player; nobody sees a dead one.
				var expected := other != viewer and not dead
				(
					assert_bool(avatars.has(other))
					. override_failure_message(
						"tick %d: peer %d sees peer %d" % [at_tick, viewer, other]
					)
					. is_equal(expected)
				)
			if avatars.has(P2):
				var downed: bool = at_tick >= downed_from
				assert_bool(avatars[P2]["downed"]).is_equal(downed)
			var bodies: Dictionary = view.snapshots[at_tick]["bodies"]
			assert_bool(bodies.has(P2)).is_equal(at_tick >= dead_from)


func test_leaving_while_downed_leaves_no_body_drops_the_hand_and_never_dies() -> void:
	var game := _duel()
	var knife := FixtureCombatModes.arm(game, P2, Vector3(0, 0, 1))
	_knock_down(game)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	var leaver := game.state.player(P2)
	assert_int(leaver.life).is_equal(PlayerState.Life.LEFT)
	assert_int(leaver.life_deadline).is_equal(-1)
	assert_dict(game.state.bodies).is_empty()
	assert_int(knife.where).is_equal(ItemState.Where.GROUND)
	assert_vector(knife.position).is_equal(Vector3(0, 0, 1))
	FixtureModes.run_ticks(game, KNOCKDOWN_TICKS + 1)
	assert_array(FixtureCombatModes.received(game, P3, &"Died")).is_empty()
	assert_int(leaver.life).is_equal(PlayerState.Life.LEFT)
	assert_array(Array(game.diagnostics)).is_empty()


func test_leaving_while_dead_removes_the_body() -> void:
	var game := _duel()
	_kill(game)
	assert_dict(game.state.bodies).is_equal({P2: Vector3(0, 0, 1)})
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.LEFT)
	assert_dict(game.state.bodies).is_empty()
	assert_array(FixtureCombatModes.received(game, P3, &"PlayerLeft")).has_size(1)
	FixtureModes.run_ticks(game, 1)
	var snapshots := game.view_of(P3).snapshots
	assert_dict(snapshots[game.ticked_through()]["bodies"]).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_downed_carrier_dying_over_its_circle_drops_the_package_in_for_the_crew() -> void:
	# The crew's fixture win stands for "every task done" (it holds once any item came to rest,
	# here the package dropping at the body), the dissidents' for "no crew present". In the base
	# mode's order: the crew's first (§3.4). A death ends nothing by itself (vision revision 1).
	var game := FixtureCombatModes.in_round(_crew_or_dissidents_mode(), [P1, P2])
	game.state.player(P1).role = &"dissident"
	game.state.player(P2).role = &"crew"
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P2, FixtureItemModes.lay(game, &"package", Vector3(0, 0, 1)))
	_knock_down(game)
	assert_str(game.phase_id()).is_equal("round")
	_run_out(game)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureModes.notes(game)).contains(["won crew"])
	assert_array(FixtureModes.notes(game)).not_contains(["won dissidents"])
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


func test_with_no_floor_below_a_knockdown_and_a_death_stay_put_and_log_it() -> void:
	var game := _duel(FlatWorldQuery.new(5.0))
	var carried := FixtureCombatModes.arm(game, P2, Vector3(0, 0, 1))
	_knock_down(game)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_vector(game.state.player(P2).position).is_equal(Vector3(0, 0, 1))
	assert_str(";".join(game.diagnostics)).contains("knock_down: no floor below")
	_run_out(game)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_dict(game.state.bodies).is_equal({P2: Vector3(0, 0, 1)})
	# The item rests at the body itself: one floor query per transition, each logged once.
	assert_vector(carried.position).is_equal(game.state.bodies[P2])
	assert_int(carried.where).is_equal(ItemState.Where.GROUND)
	assert_int(";".join(game.diagnostics).count("no floor below")).is_equal(2)


func test_life_ticks_kill_only_the_downed_whose_time_ran_out() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	_knock_down(game)
	# P3 is knocked down later by hand, with a later deadline.
	FixtureModes.run_ticks(game, 10)
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	game.state.player(P3).health = 0
	LifeRules.knock_down(ctx, P3)
	var p2_deadline := game.state.player(P2).life_deadline
	assert_int(game.state.player(P3).life_deadline).is_equal(ctx.tick + KNOCKDOWN_TICKS)
	FixtureModes.run_ticks(game, p2_deadline - game.ticked_through())
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DEAD)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.ALIVE)
	assert_array(Array(game.diagnostics)).is_empty()


## A round of P1, P2 and P3 in `world`: P1 at the origin with a knife, P2 1 m north, P3 away.
func _duel(world: WorldQuery = null) -> Match:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3], world)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	return game


## P1 hits P2 twice, the cooldown apart: P2 is knocked down.
func _knock_down(game: Match) -> void:
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)


## P2 is knocked down, and its knockdown time runs out: it is dead.
func _kill(game: Match) -> void:
	_knock_down(game)
	_run_out(game)


## Runs ticks through P2's knockdown deadline: the tick it dies on.
func _run_out(game: Match) -> void:
	FixtureModes.run_ticks(game, game.state.player(P2).life_deadline - game.ticked_through())


## FixtureCombatModes.basic() whose win conditions are, in order: the crew when peer 0's counter
## `crew_win` is at least 1, which a reaction on item_rested bumps; the dissidents when every
## crew member left.
func _crew_or_dissidents_mode() -> GameMode:
	var mode := FixtureCombatModes.basic()
	mode.reactions = [
		FixtureModes.rule(
			Facts.ITEM_RESTED, [], [FixtureRestedNote.new(), FixtureBump.of(&"crew_win")]
		)
	]
	mode.win_conditions = [
		FixtureModes.win(&"crew", FixtureCounterAtLeast.of(&"crew_win")),
		FixtureModes.win(&"dissidents", FixtureRoleAllLeft.of(&"crew")),
	]
	return mode
