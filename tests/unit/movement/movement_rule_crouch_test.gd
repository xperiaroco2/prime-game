extends GdUnitTestSuite
## MovementRule and the crouch (the crouch ADR, KE1, KE2, KE3 (a); KD5 (b), #790; KE10 as #991
## amended it): an accepted claim's `crouched` is kept as its `on_floor` is and shown in every
## snapshot, in every phase that takes a claim, the lobby included (the crouch plays everywhere);
## a downed claim's bit is ignored; a crouched claim gets the standing bounds (no new check, KE3
## (a)) and a crouched sprint is charged as a sprint (KD5 (b)). A placement and a knockdown stand
## the player up; a phase change does not.

const P1 := 1
const P2 := 2
const P3 := 3
const EAST := Vector3(1, 0, 0)
const NORTH := Vector3(0, 0, 1)
const CROUCHED := {"crouched": true}


func test_a_crouched_claim_is_kept_and_shown_to_the_others() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO, CROUCHED)
	assert_bool(player.crouched).is_true()
	assert_bool(_shown(game, P2, P1)).is_true()
	FixtureMoves.step(game, P1, Vector3.ZERO)
	assert_bool(player.crouched).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()


# The engineer's change (#989, #991): the crouch plays in the lobby too. This test asserted the
# lobby ignored the bit before.
func test_in_the_lobby_a_crouched_claim_is_kept_and_shown() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	assert_str(game.phase_id()).is_equal("lobby")
	FixtureMoves.claim(game, P1, game.state.player(P1).position, CROUCHED)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).crouched).is_true()
	assert_bool(_shown(game, P2, P1)).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_downed_claims_bit_is_ignored_and_the_knockdown_stands_it_up() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, NORTH)
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	FixtureMoves.step(game, P2, Vector3.ZERO, CROUCHED)
	assert_bool(game.state.player(P2).crouched).is_true()
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, 1)
	var downed := game.state.player(P2)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_bool(downed.crouched).is_false()
	FixtureMoves.claim(game, P2, downed.position, {"crouched": true, "facing": EAST})
	FixtureModes.run_ticks(game, 1)
	assert_vector(downed.facing).is_equal_approx(EAST, Vector3.ONE * 1e-6)
	assert_bool(downed.crouched).is_false()
	assert_bool(_shown(game, P3, P2)).is_false()


func test_a_crouched_claim_gets_the_walk_bound_and_beyond_it_is_corrected() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO, CROUCHED)
	var seen := FixtureMoves.corrections(game, P1).size()
	# Walk 0.225 + slack 0.05 = 0.275 m per tick, crouched or not (KE3 (a)).
	FixtureMoves.step(game, P1, EAST * 0.27, {"moving": true, "crouched": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen)
	assert_bool(player.crouched).is_true()
	var at := player.position
	FixtureMoves.step(game, P1, EAST * 0.3, {"moving": true, "crouched": true})
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(seen + 1)
	assert_vector(player.position).is_equal(at)


func test_a_crouched_sprint_is_charged_as_a_sprint() -> void:
	var game := FixtureMoves.in_round([P1])
	var player := game.state.player(P1)
	FixtureMoves.step(game, P1, Vector3.ZERO, CROUCHED)
	var stamina_before := player.stamina
	var fields := FixtureMoves.sprinting()
	fields.merge(CROUCHED)
	# 0.14 m a tick is the faster crouch walk (2.8 m/s): the sprint state, its cost (KD5 (b)).
	FixtureMoves.step(game, P1, EAST * 0.14, fields)
	assert_bool(player.sprinting).is_true()
	assert_bool(player.crouched).is_true()
	assert_int(player.stamina).is_equal(stamina_before - 1000)


func test_the_rounds_placement_stands_everyone_up() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	# Set by hand, so only the placement can be seen clearing it.
	game.state.player(P1).crouched = true
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.player(P1).crouched).is_false()


# The engineer's change (#989, #991): no phase clears a crouch on entry any more; before, a phase
# off the match's map did.
func test_a_crouch_is_kept_across_a_phase_change_with_or_without_a_level() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO, CROUCHED)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	assert_bool(game.state.player(P1).crouched).is_true()
	var off_map := FixtureModes.basic()
	off_map.find_phase(&"end").level = PhaseSpec.Level.NONE
	var other := Match.new(off_map, 7, FixtureTerrainWorld.new(), FixtureModes.layouts())
	_join(other, [P1, P2])
	FixtureMoves.step(other, P1, Vector3.ZERO, CROUCHED)
	other.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(other, 1)
	assert_str(other.phase_id()).is_equal("end")
	assert_bool(other.state.player(P1).crouched).is_true()


## Whether `viewer`'s newest snapshot shows `peer` crouched.
func _shown(game: Match, viewer: int, peer: int) -> bool:
	var avatars: Dictionary = game.snapshot_for(viewer).get("avatars", {})
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("crouched", false)


func _join(game: Match, peers: Array[int]) -> void:
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
