extends GdUnitTestSuite
## MovementRule and the sneak (#990, the mechanic #989): an accepted claim's `sneaking` is kept as
## its `crouched` is and shown in every snapshot, in the round and in the lobby (the sneak plays
## everywhere); a downed claim's bit is ignored and the knockdown clears a kept one, as the
## crouch's; a claim of both bits keeps only the crouch (the crouch wins); a placement clears it.

const P1 := 1
const P2 := 2
const P3 := 3
const NORTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)
const SNEAKING := {"sneaking": true}


func test_a_sneaking_claim_is_kept_and_shown_to_the_others() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO, SNEAKING)
	assert_bool(player.sneaking).is_true()
	assert_bool(player.crouched).is_false()
	assert_bool(_shown(game, P2, P1)).is_true()
	FixtureMoves.step(game, P1, Vector3.ZERO)
	assert_bool(player.sneaking).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()


func test_in_the_lobby_a_sneaking_claim_is_kept_and_shown() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	assert_str(game.phase_id()).is_equal("lobby")
	FixtureMoves.claim(game, P1, game.state.player(P1).position, SNEAKING)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).sneaking).is_true()
	assert_bool(_shown(game, P2, P1)).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_claim_of_both_bits_keeps_only_the_crouch() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"sneaking": true, "crouched": true})
	assert_bool(player.crouched).is_true()
	assert_bool(player.sneaking).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()


func test_a_downed_claims_bit_is_ignored_and_the_knockdown_clears_it() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, NORTH)
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	FixtureMoves.step(game, P2, Vector3.ZERO, SNEAKING)
	assert_bool(game.state.player(P2).sneaking).is_true()
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, 1)
	var downed := game.state.player(P2)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_bool(downed.sneaking).is_false()
	FixtureMoves.claim(game, P2, downed.position, {"sneaking": true, "facing": EAST})
	FixtureModes.run_ticks(game, 1)
	assert_vector(downed.facing).is_equal_approx(EAST, Vector3.ONE * 1e-6)
	assert_bool(downed.sneaking).is_false()
	assert_bool(_shown(game, P3, P2)).is_false()


func test_the_rounds_placement_clears_the_sneak() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	# Set by hand, so only the placement can be seen clearing it.
	game.state.player(P1).sneaking = true
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.player(P1).sneaking).is_false()


## Whether `viewer`'s newest snapshot shows `peer` sneaking.
func _shown(game: Match, viewer: int, peer: int) -> bool:
	var avatars: Dictionary = game.snapshot_for(viewer).get("avatars", {})
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("sneaking", false)
