extends GdUnitTestSuite
## ProximityVoice (ARCHITECTURE §6, §9.4): every pair of present players within `radius_m`, in 3D
## between their last accepted positions (§7.1), as recorded for view_of per tick (§5). The
## radius's bounds in the mode check (0.5 to 100; the class default 0 is refused).

const VoiceTestMatch := preload("res://tests/unit/voice/voice_test_match.gd")
const P1 := 1
const P2 := 2
const P3 := 3
const EAST := Vector3(1, 0, 0)


func test_players_within_the_radius_hear_each_other() -> void:
	var game := VoiceTestMatch.in_lobby(_proximity(8.0), [P1, P2, P3])
	VoiceTestMatch.put(game, P1, Vector3(0, 0, 0))
	VoiceTestMatch.put(game, P2, Vector3(0, 0, 6))
	VoiceTestMatch.put(game, P3, Vector3(0, 0, 12))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_equal([P2])
	assert_array(VoiceTestMatch.heard(game, P2)).is_equal([P1, P3])
	assert_array(VoiceTestMatch.heard(game, P3)).is_equal([P2])


func test_the_radius_is_inclusive() -> void:
	var game := VoiceTestMatch.in_lobby(_proximity(8.0), [P1, P2])
	VoiceTestMatch.put(game, P1, Vector3(0, 0, 0))
	VoiceTestMatch.put(game, P2, Vector3(8, 0, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_equal([P2])
	VoiceTestMatch.put(game, P2, Vector3(8.01, 0, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_empty()
	assert_array(VoiceTestMatch.heard(game, P2)).is_empty()


func test_the_distance_is_3d() -> void:
	# 3D, like the listener's fade (§6); horizontal is open for the engineer (#65).
	var game := VoiceTestMatch.in_lobby(_proximity(8.0), [P1, P2])
	VoiceTestMatch.put(game, P1, Vector3(0, 0, 0))
	VoiceTestMatch.put(game, P2, Vector3(6, 6, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_empty()
	VoiceTestMatch.put(game, P2, Vector3(0, 7.5, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_equal([P2])


func test_hearing_follows_honest_moves_tick_by_tick() -> void:
	var game := VoiceTestMatch.in_round(_proximity(3.0), [P1, P2])
	var p1 := game.state.player(P1)
	var p2 := game.state.player(P2)
	var heard_on: Array[bool] = []
	var within_on: Array[bool] = []
	for i in 20:
		FixtureMoves.step(game, P2, EAST * 0.2, {"moving": true})
		heard_on.append(VoiceTestMatch.heard(game, P1) == [P2])
		within_on.append(p1.position.distance_to(p2.position) <= 3.0)
		assert_bool(VoiceTestMatch.heard(game, P2) == [P1]).is_equal(heard_on.back())
	assert_array(heard_on).is_equal(within_on)
	assert_bool(heard_on.front()).is_true()
	assert_bool(heard_on.back()).is_false()


func test_the_living_never_hear_a_ghost_even_under_proximity() -> void:
	# §5, enforced by core for every rule (VoiceRule.speakers_of): a mode that puts Proximity in a
	# phase with ghosts must not let the living hear who is dead. The ghost still hears them.
	var game := VoiceTestMatch.in_round(_proximity(8.0), [P1, P2, P3])
	game.state.player(P2).life = PlayerState.Life.GHOST
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_equal([P3])
	assert_array(VoiceTestMatch.heard(game, P3)).is_equal([P1])
	assert_array(VoiceTestMatch.heard(game, P2)).is_equal([P1, P3])
	game.state.player(P3).life = PlayerState.Life.GHOST
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_empty()
	assert_array(VoiceTestMatch.heard(game, P2)).is_equal([P1, P3])
	assert_array(VoiceTestMatch.heard(game, P3)).is_equal([P1, P2])


func test_a_player_who_left_hears_and_is_heard_by_nobody() -> void:
	var game := VoiceTestMatch.in_lobby(_proximity(8.0), [P1, P2, P3])
	game.state.player(P3).life = PlayerState.Life.LEFT
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_equal([P2])
	assert_array(VoiceTestMatch.heard(game, P2)).is_equal([P1])
	assert_bool(game.view_of(P3).speakers.has(game.ticked_through())).is_false()
	assert_array(Array(game.speakers_for(P3))).is_empty()
	assert_bool(_proximity(8.0).hears(game.state, P1, P3)).is_false()


func test_the_radius_must_be_within_its_bounds() -> void:
	assert_array(_errors_of(_proximity(0.5))).is_empty()
	assert_array(_errors_of(_proximity(100.0))).is_empty()
	assert_array(_errors_of(ProximityVoice.new())).contains(["radius_m is 0, outside 0.5 to 100"])
	assert_array(_errors_of(_proximity(0.4))).contains(["radius_m is 0.4, outside 0.5 to 100"])
	assert_array(_errors_of(_proximity(100.5))).contains(["radius_m is 100.5, outside 0.5 to 100"])


func _proximity(radius_m: float) -> ProximityVoice:
	var rule := ProximityVoice.new()
	rule.radius_m = radius_m
	return rule


## The mode check's errors for FixtureModes.basic() with `rule` in the lobby, each without its
## path.
func _errors_of(rule: VoiceRule) -> Array[String]:
	var found: Array[String] = []
	for message: String in ModeCheck.run(VoiceTestMatch.mode(rule, SilentVoice.new())).errors:
		found.append(message.get_slice(": ", 1))
	return found
