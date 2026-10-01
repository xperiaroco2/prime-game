extends GdUnitTestSuite
## Respawn and the invulnerability it grants (ARCHITECTURE §3.4, §5, §7.1, §9.4; vision revision 1,
## V6 and V8): the dead respawn PlayerRules.respawn_s after the death at a random free respawn
## marker (from all of them when none is free, answer 5), living with their role, full health and
## stamina and empty hands; Respawned (everyone) removes the body, then the private Correction;
## strikes skip them for PlayerRules.invulnerable_s, which nothing ends early (answer 3); the
## avatar's flag `invulnerable`. Driven by the knife's Use (FixtureCombatModes, 50 damage) and the
## fixture's numbers: a knockdown of 10 s, a respawn of 30 s (600 ticks), 3 s of invulnerability
## (60 ticks), a free radius of 1 m; respawn markers FixtureModes.RESPAWNS.

const P1 := 1
const P2 := 2
const P3 := 3
const NORTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)
## The fixture's respawn time and invulnerability in host ticks, at 20 Hz.
const RESPAWN_TICKS := 600
const INVULNERABLE_TICKS := 60
const FULL := 100000
const HALF := 50000


func test_the_dead_respawn_after_their_time_with_full_numbers_and_empty_hands() -> void:
	var game := _duel()
	var package := FixtureItemModes.lay(game, &"package", Vector3(0, 0, 1))
	FixtureItemModes.pick_up(game, P2, package)
	var role := game.state.player(P2).role
	_kill(game)
	var died_at := game.ticked_through()
	var dead := game.state.player(P2)
	assert_int(dead.life_deadline).is_equal(died_at + RESPAWN_TICKS)
	FixtureModes.run_ticks(game, RESPAWN_TICKS - 1)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_dict(game.state.bodies).contains_keys([P2])
	var epoch := dead.epoch
	FixtureModes.run_ticks(game, 1)
	assert_int(dead.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(dead.life_deadline).is_equal(-1)
	assert_int(dead.health).is_equal(FULL)
	assert_int(dead.stamina).is_equal(FULL)
	assert_int(dead.held_item).is_equal(-1)
	assert_str(dead.role).is_equal(role)
	assert_int(dead.epoch).is_equal(epoch + 1)
	assert_bool(FixtureModes.RESPAWNS.has(dead.position)).is_true()
	assert_dict(game.state.bodies).is_empty()
	# The package it held lies where it died; nothing came back with it.
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_array(Array(game.diagnostics)).is_empty()


func test_respawned_reaches_everyone_then_the_correction_and_selfstatus_reach_that_player() -> void:
	var game := _duel()
	_kill(game)
	var seen := FixtureMoves.corrections(game, P2).size()
	var own_seen := game.view_of(P2).events.size()
	var others: Dictionary[int, int] = {}
	for peer: int in [P1, P3]:
		others[peer] = FixtureMoves.corrections(game, peer).size()
	_run_out(game)
	var back := game.state.player(P2)
	for peer: int in [P1, P2, P3]:
		var respawned := FixtureCombatModes.received(game, peer, &"Respawned")
		assert_array(respawned).has_size(1)
		assert_dict(respawned[0].to_dict()).is_equal({"peer": P2, "position": back.position})
	assert_array(FixtureItemModes.names_after(game, P2, own_seen)).is_equal(
		[&"Respawned", &"Correction", &"SelfStatus"]
	)
	var corrections := FixtureMoves.corrections(game, P2)
	assert_int(corrections.size()).is_equal(seen + 1)
	assert_dict(corrections[seen].to_dict()).is_equal(
		{"epoch": back.epoch, "position": back.position, "velocity": Vector3.ZERO}
	)
	for peer: int in [P1, P3]:
		assert_int(FixtureMoves.corrections(game, peer).size()).is_equal(others[peer])
	var statuses := FixtureMoves.statuses(game, P2)
	assert_dict(statuses[statuses.size() - 1].to_dict()).is_equal(
		{"health": FULL, "stamina": FULL, "sprint_available": true}
	)


func test_the_respawned_walk_from_the_marker_and_old_claims_are_dropped() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	var back := game.state.player(P2)
	var marker := back.position
	var seen := FixtureMoves.corrections(game, P2).size()
	FixtureMoves.claim(game, P2, marker + EAST, {"epoch": back.epoch - 1})
	assert_vector(back.position).is_equal(marker)
	FixtureMoves.steps(game, P2, 5, EAST * 0.2, {"moving": true})
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(seen)
	assert_vector(back.position).is_equal_approx(marker + EAST, Vector3.ONE * 1e-4)


func test_a_marker_with_a_living_or_downed_player_within_the_free_radius_is_not_drawn() -> void:
	# Over several seeds, P2 always lands on the one free marker: P1 (living) stands 0.9 m from
	# the first, P3 (downed) on the second.
	for seed_value: int in [1, 2, 3, 4, 5, 6]:
		var game := _duel(seed_value)
		_kill(game)
		FixtureItemModes.stand(game, P1, FixtureModes.RESPAWNS[0] + EAST * 0.9)
		FixtureItemModes.stand(game, P3, FixtureModes.RESPAWNS[1])
		game.state.player(P3).life = PlayerState.Life.DOWNED
		game.state.player(P3).life_deadline = game.ticked_through() + 10 * RESPAWN_TICKS
		_run_out(game)
		assert_vector(game.state.player(P2).position).is_equal(FixtureModes.RESPAWNS[2])
		assert_array(Array(game.diagnostics)).is_empty()


func test_a_marker_just_outside_the_free_radius_or_by_a_body_is_free() -> void:
	var game := _duel()
	_kill(game)
	var spots := PackedVector3Array(FixtureModes.RESPAWNS)
	FixtureItemModes.stand(game, P1, FixtureModes.RESPAWNS[0] + EAST * 1.01)
	# A body (P3, dead) does not take a marker: only the living and the downed do.
	FixtureItemModes.stand(game, P3, FixtureModes.RESPAWNS[1])
	game.state.player(P3).life = PlayerState.Life.DEAD
	assert_array(Array(Respawn.free_markers(game.state, spots))).is_equal(
		Array(FixtureModes.RESPAWNS)
	)
	FixtureItemModes.stand(game, P1, FixtureModes.RESPAWNS[0] + EAST * 1.0)
	assert_array(Array(Respawn.free_markers(game.state, spots))).is_equal(
		[FixtureModes.RESPAWNS[1], FixtureModes.RESPAWNS[2]]
	)


func test_with_no_free_marker_the_draw_is_from_all_of_them() -> void:
	var landed: Dictionary[Vector3, bool] = {}
	for seed_value: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		var game := FixtureCombatModes.in_round(
			FixtureCombatModes.respawning(), [P1, P2, P3, 4], null, seed_value
		)
		FixtureCombatModes.arm(game, P1, FixtureModes.RESPAWNS[0])
		FixtureItemModes.stand(game, P2, FixtureModes.RESPAWNS[0] + NORTH)
		FixtureItemModes.stand(game, P3, FixtureModes.RESPAWNS[1])
		FixtureItemModes.stand(game, 4, FixtureModes.RESPAWNS[2])
		_kill(game)
		# Its body lies next to P1; P1 steps back onto the first marker.
		FixtureItemModes.stand(game, P1, FixtureModes.RESPAWNS[0])
		_run_out(game)
		var back := game.state.player(P2)
		assert_int(back.life).is_equal(PlayerState.Life.ALIVE)
		assert_bool(FixtureModes.RESPAWNS.has(back.position)).is_true()
		landed[back.position] = true
		assert_array(Array(game.diagnostics)).is_empty()
	# Uniform over all three: eight seeds reach more than one of them.
	assert_int(landed.size()).is_greater(1)


func test_the_draw_is_uniform_over_the_free_markers_with_the_purpose_respawn() -> void:
	var counts: Dictionary[Vector3, int] = {}
	for seed_value in range(1, 31):
		var game := _duel(seed_value)
		_kill(game)
		# The draw is the stream `respawn`'s next number over the three free markers: peeked on
		# one match, played on its twin of the same seed.
		var expected := FixtureModes.RESPAWNS[game.state.rng.stream(&"respawn").randi_range(0, 2)]
		var twin := _duel(seed_value)
		_kill(twin)
		_run_out(twin)
		counts[twin.state.player(P2).position] = counts.get(twin.state.player(P2).position, 0) + 1
		assert_vector(twin.state.player(P2).position).is_equal(expected)
	assert_int(counts.size()).is_equal(3)


func test_without_a_respawn_the_dead_stay_dead() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	_kill(game)
	FixtureModes.run_ticks(game, RESPAWN_TICKS + 20)
	var dead := game.state.player(P2)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_int(dead.life_deadline).is_equal(-1)
	assert_dict(game.state.bodies).contains_keys([P2])
	assert_array(FixtureCombatModes.received(game, P1, &"Respawned")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_strikes_skip_the_respawned_for_the_invulnerability_then_hit_again() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	var respawned_at := game.ticked_through()
	var back := game.state.player(P2)
	var until := respawned_at + INVULNERABLE_TICKS
	assert_int(back.invulnerable_until).is_equal(until)
	# P1 (armed) south of P2, P3 armed north of it: each 1 m away, facing it.
	FixtureItemModes.stand(game, P1, back.position - NORTH)
	FixtureCombatModes.arm(game, P3, back.position + NORTH)
	var damaged := FixtureCombatModes.received(game, P2, &"Damaged").size()
	var swings := FixtureCombatModes.received(game, P3, &"Swung").size()
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(FixtureCombatModes.received(game, P3, &"Swung").size()).is_equal(swings + 1)
	assert_int(FixtureCombatModes.received(game, P2, &"Damaged").size()).is_equal(damaged)
	assert_int(back.health).is_equal(FULL)
	# The last tick of the invulnerability (a Use is applied at the next tick): still skipped.
	FixtureModes.run_ticks(game, until - 2 - game.ticked_through())
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(FixtureCombatModes.received(game, P3, &"Swung").size()).is_equal(swings + 2)
	assert_int(FixtureCombatModes.received(game, P2, &"Damaged").size()).is_equal(damaged)
	# The first tick after it: P3's swing hits.
	FixtureModes.run_ticks(game, 1)
	FixtureCombatModes.use(game, P3, -NORTH)
	assert_int(game.ticked_through()).is_equal(until - 1)
	assert_int(FixtureCombatModes.received(game, P2, &"Damaged").size()).is_equal(damaged + 1)
	assert_int(back.health).is_equal(HALF)
	assert_array(Array(game.diagnostics)).is_empty()


func test_nothing_ends_the_invulnerability_early_not_even_the_players_own_attack() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	var back := game.state.player(P2)
	var until := back.invulnerable_until
	# P2 arms itself and strikes P3, at once: P3 is hit, P2 stays invulnerable.
	FixtureCombatModes.arm(game, P2, back.position)
	FixtureItemModes.stand(game, P3, back.position + NORTH)
	FixtureCombatModes.use(game, P2, NORTH)
	assert_array(FixtureCombatModes.received(game, P3, &"Damaged")).has_size(1)
	assert_int(back.invulnerable_until).is_equal(until)
	FixtureItemModes.stand(game, P1, back.position - NORTH)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.ticked_through()).is_less(until)
	assert_array(FixtureCombatModes.received(game, P2, &"Damaged")).has_size(2)
	assert_int(back.health).is_equal(FULL)


func test_the_avatar_flag_shows_the_invulnerability_to_the_others_only_while_it_runs() -> void:
	var game := _duel()
	FixtureModes.run_ticks(game, 1)
	assert_bool(_flag(game, P1, P2)).is_false()
	_kill(game)
	_run_out(game)
	var until := game.state.player(P2).invulnerable_until
	FixtureModes.run_ticks(game, 1)
	assert_bool(_flag(game, P1, P2)).is_true()
	assert_bool(_flag(game, P3, P2)).is_true()
	assert_bool(_flag(game, P2, P1)).is_false()
	assert_dict(game.view_of(P2).snapshots[game.ticked_through()]["avatars"]).not_contains_keys(
		[P2]
	)
	FixtureModes.run_ticks(game, until - 1 - game.ticked_through())
	assert_bool(_flag(game, P1, P2)).is_true()
	FixtureModes.run_ticks(game, 1)
	assert_bool(_flag(game, P1, P2)).is_false()
	assert_bool(game.snapshot_for(P1)["avatars"][P2]["invulnerable"]).is_false()


func test_nobody_is_invulnerable_at_a_rounds_start() -> void:
	var game := _duel()
	_kill(game)
	_run_out(game)
	assert_int(game.state.player(P2).invulnerable_until).is_greater(0)
	# The match ends and the next one starts: ResetMatch clears it with the rest.
	game.state.reset_match()
	for peer: int in [P1, P2, P3]:
		assert_int(game.state.player(peer).invulnerable_until).is_equal(-1)
		assert_bool(game.state.player(peer).is_invulnerable(game.ticked_through())).is_false()
	var fresh := _duel()
	for peer: int in [P1, P2, P3]:
		assert_int(fresh.state.player(peer).invulnerable_until).is_equal(-1)


func test_a_respawn_of_a_player_who_is_not_dead_is_a_rule_error() -> void:
	var game := _duel()
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	ctx.layout = game.layout(FixtureModes.MAP)
	ctx.actor = P2
	FixtureCombatModes.respawn().run(ctx)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.ALIVE)
	assert_str("\n".join(game.diagnostics)).contains("Respawn: player 2 is not dead")


func _duel(seed_value: int = 7) -> Match:
	var game := FixtureCombatModes.in_round(
		FixtureCombatModes.respawning(), [P1, P2, P3], null, seed_value
	)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	return game


## P1 hits P2 twice, the cooldown apart, and P2's knockdown runs out: P2 is dead.
func _kill(game: Match) -> void:
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	_run_out(game)


## Runs ticks through P2's life deadline: the tick it dies or respawns on.
func _run_out(game: Match) -> void:
	FixtureModes.run_ticks(game, game.state.player(P2).life_deadline - game.ticked_through())


## Whether `viewer`'s newest recorded snapshot shows `peer` invulnerable.
func _flag(game: Match, viewer: int, peer: int) -> bool:
	var snapshot: Dictionary = game.view_of(viewer).snapshots[game.ticked_through()]
	return snapshot["avatars"][peer]["invulnerable"]
