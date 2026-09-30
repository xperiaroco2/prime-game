extends GdUnitTestSuite
## RoundVoice (ARCHITECTURE §6, §9.4): the living hear the living within `living_m`; a ghost hears
## the living within `ghost_hears_living_m` and ghosts within `ghost_hears_ghost_m`, measured from
## the ghost; the living never hear the dead; a player who left hears and is heard by nobody.
## Distinct radii (5, 10, 3) show which one applies. Recorded per tick for view_of (§5).

const VoiceTestMatch := preload("res://tests/unit/voice/voice_test_match.gd")
const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const EAST := Vector3(1, 0, 0)


func test_the_living_hear_the_living_within_living_m() -> void:
	var game := VoiceTestMatch.in_round(_round_voice(), [P1, P2, P3])
	VoiceTestMatch.put(game, P1, Vector3(0, 0, 0))
	VoiceTestMatch.put(game, P2, Vector3(5, 0, 0))
	VoiceTestMatch.put(game, P3, Vector3(0, 0, 5.5))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_equal([P2])
	assert_array(VoiceTestMatch.heard(game, P2)).is_equal([P1])
	assert_array(VoiceTestMatch.heard(game, P3)).is_empty()


func test_the_living_never_hear_a_ghost_however_close() -> void:
	var game := VoiceTestMatch.in_round(_round_voice(), [P1, P2])
	game.state.player(P2).life = PlayerState.Life.GHOST
	VoiceTestMatch.put(game, P1, Vector3(0, 0, 0))
	VoiceTestMatch.put(game, P2, Vector3(0, 0, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_empty()
	assert_bool(_round_voice().hears(game.state, P1, P2)).is_false()


func test_a_ghost_hears_the_living_within_its_own_radius_one_way() -> void:
	var game := VoiceTestMatch.in_round(_round_voice(), [P1, P2])
	game.state.player(P2).life = PlayerState.Life.GHOST
	VoiceTestMatch.put(game, P1, Vector3(0, 0, 0))
	VoiceTestMatch.put(game, P2, Vector3(10, 0, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P2)).is_equal([P1])
	assert_array(VoiceTestMatch.heard(game, P1)).is_empty()
	VoiceTestMatch.put(game, P2, Vector3(10.1, 0, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P2)).is_empty()


func test_a_ghost_hears_other_ghosts_within_ghost_hears_ghost_m() -> void:
	var game := VoiceTestMatch.in_round(_round_voice(), [P1, P2, P3])
	for peer: int in [P1, P2, P3]:
		game.state.player(peer).life = PlayerState.Life.GHOST
	VoiceTestMatch.put(game, P1, Vector3(0, 0, 0))
	VoiceTestMatch.put(game, P2, Vector3(3, 0, 0))
	VoiceTestMatch.put(game, P3, Vector3(-3.5, 0, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_equal([P2])
	assert_array(VoiceTestMatch.heard(game, P2)).is_equal([P1])
	assert_array(VoiceTestMatch.heard(game, P3)).is_empty()


func test_each_listener_uses_its_own_radius() -> void:
	# P1 living, P2 a ghost 4 m away, P3 living 7 m away, P4 a ghost 2 m from P2.
	var game := VoiceTestMatch.in_round(_round_voice(), [P1, P2, P3, P4])
	game.state.player(P2).life = PlayerState.Life.GHOST
	game.state.player(P4).life = PlayerState.Life.GHOST
	VoiceTestMatch.put(game, P1, Vector3(0, 0, 0))
	VoiceTestMatch.put(game, P2, Vector3(4, 0, 0))
	VoiceTestMatch.put(game, P3, Vector3(7, 0, 0))
	VoiceTestMatch.put(game, P4, Vector3(6, 0, 0))
	assert_array(VoiceTestMatch.tick_and_hear(game, P1)).is_empty()
	assert_array(VoiceTestMatch.heard(game, P2)).is_equal([P1, P3, P4])
	assert_array(VoiceTestMatch.heard(game, P3)).is_empty()
	assert_array(VoiceTestMatch.heard(game, P4)).is_equal([P1, P2, P3])


func test_a_player_who_left_hears_and_is_heard_by_nobody() -> void:
	var game := VoiceTestMatch.in_round(_round_voice(), [P1, P2, P3])
	game.state.player(P2).life = PlayerState.Life.GHOST
	game.state.player(P3).life = PlayerState.Life.LEFT
	for peer: int in [P1, P2, P3]:
		VoiceTestMatch.put(game, peer, Vector3.ZERO)
	FixtureModes.run_ticks(game, 1)
	assert_array(VoiceTestMatch.heard(game, P1)).is_empty()
	assert_array(VoiceTestMatch.heard(game, P2)).is_equal([P1])
	assert_bool(game.view_of(P3).speakers.has(game.ticked_through())).is_false()
	var rule := _round_voice()
	for peer: int in [P1, P2]:
		assert_bool(rule.hears(game.state, peer, P3)).is_false()
		assert_bool(rule.hears(game.state, P3, peer)).is_false()


func test_a_ghost_walking_away_stops_hearing_at_its_radius() -> void:
	var game := VoiceTestMatch.in_round(_round_voice(), [P1, P2])
	var p1 := game.state.player(P1)
	var ghost := game.state.player(P2)
	ghost.life = PlayerState.Life.GHOST
	var heard_on: Array[bool] = []
	var within_on: Array[bool] = []
	for i in 30:
		FixtureMoves.step(game, P2, EAST * 0.4, FixtureMoves.sprinting())
		heard_on.append(VoiceTestMatch.heard(game, P2) == [P1])
		within_on.append(p1.position.distance_to(ghost.position) <= 10.0)
		assert_array(VoiceTestMatch.heard(game, P1)).is_empty()
	assert_array(heard_on).is_equal(within_on)
	assert_bool(heard_on.front()).is_true()
	assert_bool(heard_on.back()).is_false()


func test_each_radius_must_be_within_its_bounds() -> void:
	assert_array(_errors_of(_round_voice())).is_empty()
	assert_array(_errors_of(_radii(0.5, 100.0, 0.5))).is_empty()
	var defaults := _errors_of(RoundVoice.new())
	(
		assert_array(defaults)
		. contains(
			[
				"living_m is 0, outside 0.5 to 100",
				"ghost_hears_living_m is 0, outside 0.5 to 100",
				"ghost_hears_ghost_m is 0, outside 0.5 to 100",
			]
		)
	)
	assert_array(_errors_of(_radii(8.0, 100.5, 8.0))).contains(
		["ghost_hears_living_m is 100.5, outside 0.5 to 100"]
	)
	assert_array(_errors_of(_radii(8.0, 8.0, 0.4))).contains(
		["ghost_hears_ghost_m is 0.4, outside 0.5 to 100"]
	)


func _round_voice() -> RoundVoice:
	return _radii(5.0, 10.0, 3.0)


func _radii(living_m: float, ghost_hears_living_m: float, ghost_hears_ghost_m: float) -> RoundVoice:
	var rule := RoundVoice.new()
	rule.living_m = living_m
	rule.ghost_hears_living_m = ghost_hears_living_m
	rule.ghost_hears_ghost_m = ghost_hears_ghost_m
	return rule


## The mode check's errors for FixtureModes.basic() with `rule` in the round, each without its
## path.
func _errors_of(rule: VoiceRule) -> Array[String]:
	var found: Array[String] = []
	for message: String in ModeCheck.run(VoiceTestMatch.mode(SilentVoice.new(), rule)).errors:
		found.append(message.get_slice(": ", 1))
	return found
