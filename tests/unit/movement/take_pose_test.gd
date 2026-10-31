extends GdUnitTestSuite
## TakePose and the Pose intent (#1296; GDD §12 "The camera wall": the seated watcher): a living
## player's Pose in the round sets `posed`, which every other peer's snapshot shows on its avatar;
## any own move ends it (a claim's moving input, a moved tick it covers or a new jump, also a
## refused claim; an accepted claim's travel with no one near to push it), a push without input
## does not; a placement, a knockdown and a reset end it; the lobby and the downed are not
## accepted; away from every seat (AtMarker) the pose is refused `out_of_reach`. The rule is
## FixtureMoves.posing()'s (the base mode's own is pinned in tests/unit/content/), the seats
## FixtureMoves.seat()'s.

const P1 := 1
const P2 := 2
const P3 := 3
const NORTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)


func test_a_pose_sets_the_flag_and_every_other_peer_sees_it() -> void:
	var game := _posing_round([P1, P2, P3])
	FixtureModes.run_ticks(game, 1)
	assert_bool(_shown(game, P2, P1)).is_false()
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_true()
	assert_bool(_shown(game, P2, P1)).is_true()
	assert_bool(_shown(game, P3, P1)).is_true()
	var recorded: Dictionary = game.view_of(P2).snapshots[game.ticked_through()]["avatars"][P1]
	assert_bool(recorded["posed"]).is_true()
	# The poser gets no avatar of its own (Snapshots), and nobody else is posed.
	assert_dict(game.snapshot_for(P1)["avatars"]).not_contains_keys([P1])
	assert_bool(_shown(game, P1, P2)).is_false()
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_a_second_pose_changes_nothing_and_is_not_refused() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1, 1)
	FixtureMoves.pose(game, P1, 2)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_true()
	assert_array(FixtureModes.rejections(game, P1)).is_empty()


func test_the_lobby_does_not_accept_a_pose() -> void:
	var game := FixtureModes.started(FixtureMoves.posing(FixtureModes.basic()), [P1, P2])
	assert_str(game.phase_id()).is_equal("lobby")
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_false()
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])


func test_a_still_claim_keeps_the_pose() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"facing": EAST})
	assert_vector(game.state.player(P1).facing).is_equal_approx(EAST, Vector3.ONE * 1e-6)
	assert_bool(game.state.player(P1).posed).is_true()
	assert_bool(_shown(game, P2, P1)).is_true()


func test_a_moving_claim_ends_the_pose() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, EAST * 0.1, {"moving": true})
	assert_bool(game.state.player(P1).posed).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()


func test_a_moving_claim_ends_it_even_where_it_does_not_move() -> void:
	# The input counts, not the travel: a walk into a wall stands the watcher up.
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"moving": true})
	assert_bool(game.state.player(P1).posed).is_false()


func test_a_new_jump_ends_the_pose() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, Vector3(0, 0.1, 0), FixtureMoves.jumped(game, P1))
	assert_int(FixtureMoves.jumps_of(game, P1)).is_equal(1)
	assert_bool(game.state.player(P1).posed).is_false()


func test_a_moved_tick_of_a_merged_claim_ends_the_pose() -> void:
	# The LATEST lane merged the moving claims away: the last one is still, its mask says it moved.
	var game := _posing_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 2)
	var player := game.state.player(P1)
	FixtureMoves.claim(
		game, P1, player.position, {"client_tick": player.claim_tick + 2, "moved_ticks": 0b10}
	)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_bool(player.posed).is_false()


func test_a_moved_tick_before_the_covered_ones_keeps_the_pose() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.step(game, P1, Vector3.ZERO)
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 2)
	var player := game.state.player(P1)
	FixtureMoves.claim(
		game, P1, player.position, {"client_tick": player.claim_tick + 2, "moved_ticks": 0b100}
	)
	FixtureModes.run_ticks(game, 1)
	assert_bool(player.posed).is_true()


func test_a_refused_moving_claim_ends_the_pose_too() -> void:
	# Its client stood up already; the host corrects the place and keeps nobody seated.
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	var epoch := game.state.player(P1).epoch
	var corrections := game.view_of(P1).events_named(&"Correction").size()
	FixtureMoves.step(game, P1, EAST * 5.0, {"moving": true})
	assert_int(game.state.player(P1).epoch).is_equal(epoch + 1)
	assert_array(game.view_of(P1).events_named(&"Correction")).has_size(corrections + 1)
	assert_bool(game.state.player(P1).posed).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()


func test_a_displacement_without_input_keeps_the_pose() -> void:
	# A push by another player (the claim's own input is still): GDD §12's "any move" is the
	# watcher's own.
	var game := _posing_round([P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureMoves.seat(game, P1)
	FixtureItemModes.stand(game, P2, EAST)
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	var corrections := game.view_of(P1).events_named(&"Correction").size()
	FixtureMoves.step(game, P1, NORTH * 0.1)
	assert_array(game.view_of(P1).events_named(&"Correction")).has_size(corrections)
	assert_vector(game.state.player(P1).position).is_equal_approx(NORTH * 0.1, Vector3.ONE * 1e-4)
	assert_bool(game.state.player(P1).posed).is_true()


func test_travel_without_input_and_without_a_pusher_ends_the_pose() -> void:
	# The host measures the move itself: a claim that clears its input bits and its mask but
	# travels, with nobody near to push it, is a walk all the same (the coasting allowance).
	var game := _posing_round([P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureMoves.seat(game, P1)
	FixtureItemModes.stand(game, P2, Vector3(10, 0, 10))
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_true()
	var corrections := game.view_of(P1).events_named(&"Correction").size()
	FixtureMoves.step(game, P1, NORTH * 0.1, {"moved_ticks": 0})
	assert_array(game.view_of(P1).events_named(&"Correction")).has_size(corrections)
	assert_vector(game.state.player(P1).position).is_equal_approx(NORTH * 0.1, Vector3.ONE * 1e-4)
	assert_bool(game.state.player(P1).posed).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()


func test_the_downed_cannot_pose_and_the_knockdown_ends_it() -> void:
	var game := FixtureCombatModes.in_round(
		FixtureMoves.posing(FixtureCombatModes.basic()), [P1, P2, P3]
	)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, NORTH)
	FixtureMoves.seat(game, P2)
	FixtureItemModes.stand(game, P3, Vector3(5, 0, 5))
	FixtureMoves.pose(game, P2)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P2).posed).is_true()
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, 1)
	var downed := game.state.player(P2)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_bool(downed.posed).is_false()
	assert_bool(_shown(game, P3, P2)).is_false()
	FixtureMoves.pose(game, P2)
	FixtureModes.run_ticks(game, 1)
	assert_bool(downed.posed).is_false()
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])


func test_the_rounds_placement_ends_the_pose() -> void:
	var game := FixtureModes.started(FixtureMoves.posing(FixtureModes.basic()), [P1, P2])
	# Set by hand, so only the placement can be seen clearing it.
	game.state.player(P1).posed = true
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.player(P1).posed).is_false()


func test_a_reset_ends_the_pose() -> void:
	var game := _posing_round([P1, P2])
	var player := game.state.player(P1)
	player.posed = true
	MatchState.reset_player(player, game.state.player_rules)
	assert_bool(player.posed).is_false()


func test_a_pose_stops_the_posers_raise() -> void:
	# A player action (RuleRunner's channel stop, §9.2): the raiser who sits down stops raising.
	var game := FixtureCombatModes.in_round(
		FixtureMoves.posing(FixtureCombatModes.raising()), [P1, P2, P3]
	)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, NORTH)
	FixtureItemModes.stand(game, P3, Vector3(1.5, 0, 1))
	FixtureMoves.seat(game, P3)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 1)
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	var seen := game.view_of(P1).events.size()
	FixtureMoves.pose(game, P3)
	FixtureModes.run_ticks(game, 1)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_bool(game.state.player(P3).posed).is_true()
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal([&"RaiseStopped"])


func test_take_pose_emits_nothing() -> void:
	# The flag travels in the snapshot and in the poser's own SelfStatus (the feed's, to the poser
	# alone): no event of the effect names the poser to anyone.
	assert_array(TakePose.new().emits()).is_empty()
	assert_array(TakePose.new().required_conditions()).is_equal([AtMarker])


func test_a_pose_away_from_every_seat_is_out_of_reach() -> void:
	var game := _posing_round([P1, P2])
	# The seats stand beside the placement spots; 3 m north of P1's own is outside every one.
	FixtureItemModes.stand(game, P1, game.state.player(P1).position + Vector3(0, 0, 3))
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_false()
	assert_bool(_shown(game, P2, P1)).is_false()
	assert_array(FixtureModes.rejections(game, P1)).is_equal([AtMarker.OUT_OF_REACH])


func test_a_map_without_a_seat_refuses_every_pose() -> void:
	var game := FixtureItemModes.in_round(
		FixtureMoves.posing(FixtureModes.basic()), [P1, P2], FixtureTerrainWorld.new()
	)
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_false()
	assert_array(FixtureModes.rejections(game, P1)).is_equal([AtMarker.OUT_OF_REACH])


func test_a_kill_from_the_chair_stands_the_body_up() -> void:
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_bool(game.state.player(P1).posed).is_true()
	LifeRules.kill(FixtureMoves.context(game), P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DEAD)
	assert_bool(game.state.player(P1).posed).is_false()


func test_a_crouched_claim_keeps_the_seat() -> void:
	# #1296: a crouched watcher stays seated (the look plays Crouch_Idle); only the wheel pose ends
	# on a crouch (#1485).
	var game := _posing_round([P1, P2])
	FixtureMoves.pose(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.step(game, P1, Vector3.ZERO, {"crouched": true})
	assert_bool(game.state.player(P1).crouched).is_true()
	assert_bool(game.state.player(P1).posed).is_true()


## A round of the posing fixture with a seat beside every player's placement spot.
func _posing_round(peers: Array[int]) -> Match:
	var game := FixtureItemModes.in_round(
		FixtureMoves.posing(FixtureModes.basic()), peers, FixtureTerrainWorld.new()
	)
	for peer: int in peers:
		FixtureMoves.seat(game, peer)
	return game


## Whether `viewer`'s newest snapshot shows `peer` posed.
func _shown(game: Match, viewer: int, peer: int) -> bool:
	var avatars: Dictionary = game.snapshot_for(viewer).get("avatars", {})
	var avatar: Dictionary = avatars.get(peer, {})
	return avatar.get("posed", false)
