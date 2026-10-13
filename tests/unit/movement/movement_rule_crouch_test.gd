extends GdUnitTestSuite
## MovementRule and the crouch (the crouch ADR, KE1, KE2, KE3 (a), KE10; KD5 (b), #790): an
## accepted claim's `crouched` is kept as its `on_floor` is and shown in every snapshot, only where
## the crouch plays (a phase on the match's map, a map PlayerRules.crouch_maps lists or any when it
## is empty); a downed claim's bit, a lobby claim's and one on an unlisted map are ignored; a
## crouched claim gets the standing bounds (no new check, KE3 (a)) and a crouched sprint is charged
## as a sprint (KD5 (b)). A placement and a knockdown stand the player up, and a phase where the
## crouch does not play clears it on entry.

const P1 := 1
const P2 := 2
const P3 := 3
const EAST := Vector3(1, 0, 0)
const NORTH := Vector3(0, 0, 1)
const ELSEWHERE := "fixture://elsewhere"
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


func test_with_an_empty_crouch_maps_the_crouch_plays_on_the_match_map() -> void:
	var game := FixtureMoves.in_round([P1, P2])
	assert_bool(game.mode.player_rules.crouch_maps.is_empty()).is_true()
	assert_bool(game.crouch_plays()).is_true()


func test_on_a_map_crouch_maps_does_not_list_the_bit_is_ignored() -> void:
	var game := _round_with_crouch_maps(PackedStringArray([ELSEWHERE]))
	assert_str(game.state.map).is_equal(FixtureModes.MAP)
	assert_bool(game.crouch_plays()).is_false()
	FixtureMoves.step(game, P1, Vector3.ZERO, CROUCHED)
	assert_bool(game.state.player(P1).crouched).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


func test_on_a_map_crouch_maps_lists_the_bit_is_kept() -> void:
	var game := _round_with_crouch_maps(PackedStringArray([FixtureModes.MAP]))
	FixtureMoves.step(game, P1, Vector3.ZERO, CROUCHED)
	assert_bool(game.state.player(P1).crouched).is_true()


func test_in_the_lobby_the_bit_is_ignored_though_the_next_map_plays_it() -> void:
	var game := FixtureModes.started(FixtureModes.basic(), [P1, P2])
	assert_str(game.phase_id()).is_equal("lobby")
	assert_bool(game.state.player_rules.crouch_plays_on(game.state.map)).is_true()
	assert_bool(game.crouch_plays()).is_false()
	FixtureMoves.claim(game, P1, game.state.player(P1).position, CROUCHED)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).crouched).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()


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
	# Set by hand: the lobby never keeps a crouch, so only a placement can be seen clearing it.
	game.state.player(P1).crouched = true
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.player(P1).crouched).is_false()


func test_a_phase_on_the_map_keeps_the_crouch_and_one_off_it_clears_it_on_entry() -> void:
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
	assert_bool(other.state.player(P1).crouched).is_true()
	other.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(other, 1)
	assert_str(other.phase_id()).is_equal("end")
	assert_bool(other.state.player(P1).crouched).is_false()


## Whether `viewer`'s newest snapshot shows `peer` crouched.
func _shown(game: Match, viewer: int, peer: int) -> bool:
	var avatars: Dictionary = game.snapshot_for(viewer).get("avatars", {})
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("crouched", false)


## A round of FixtureModes.basic() with a second map, ELSEWHERE, and `crouch_maps`; the match is
## on FixtureModes.MAP, the lobby's first pick. Its motion_maps is crouch_maps.
func _round_with_crouch_maps(crouch_maps: PackedStringArray) -> Match:
	var mode := FixtureModes.basic()
	mode.maps = PackedStringArray([FixtureModes.MAP, ELSEWHERE])
	mode.player_rules.crouch_maps = crouch_maps
	# A body moves only where the crouch plays (KD11, the mode check): never knocked down here.
	mode.player_rules.motion_maps = crouch_maps
	assert_array(Array(mode.player_rules.check(mode))).is_empty()
	var layouts := FixtureModes.layouts()
	var elsewhere := LevelLayout.new(ELSEWHERE)
	for marker: Vector3 in [Vector3(0, 0, 5), Vector3(1, 0, 5)]:
		elsewhere.add_marker(&"round_player", marker)
	layouts[ELSEWHERE] = elsewhere
	var game := Match.new(mode, 7, FixtureTerrainWorld.new(), layouts)
	assert_array(Array(game.refusals)).is_empty()
	_join(game, [P1, P2])
	assert_str(game.phase_id()).is_equal("round")
	return game


func _join(game: Match, peers: Array[int]) -> void:
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
