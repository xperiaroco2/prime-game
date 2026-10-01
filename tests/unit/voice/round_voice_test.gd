extends GdUnitTestSuite
## RoundVoice (ARCHITECTURE §6, §9.4): a listener hears a living speaker within `living_m`, so the
## living hear the living and a downed player hears the living from where it lies; under the
## voice invariant (VoiceRule.speakers_of) nobody hears the downed or the dead, the dead hear
## nobody, and a player who left hears and is heard by nobody. Recorded per tick for view_of
## (§5).

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const EAST := Vector3(1, 0, 0)
const LIVING_M := 5.0


func test_the_living_hear_the_living_within_living_m() -> void:
	var game := FixtureVoiceMatch.in_round(_round_voice(), [P1, P2, P3])
	FixtureVoiceMatch.put(game, P1, Vector3(0, 0, 0))
	FixtureVoiceMatch.put(game, P2, Vector3(5, 0, 0))
	FixtureVoiceMatch.put(game, P3, Vector3(0, 0, 5.5))
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_equal([P2])
	assert_array(FixtureVoiceMatch.heard(game, P2)).is_equal([P1])
	assert_array(FixtureVoiceMatch.heard(game, P3)).is_empty()


func test_the_living_never_hear_a_downed_player_however_close() -> void:
	var game := FixtureVoiceMatch.in_round(_round_voice(), [P1, P2])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureVoiceMatch.put(game, P1, Vector3(0, 0, 0))
	FixtureVoiceMatch.put(game, P2, Vector3(0, 0, 0))
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_empty()
	assert_array(_round_voice().speakers_of(game.state, P1)).is_empty()
	assert_array(FixtureVoiceMatch.heard(game, P2)).is_equal([P1])


func test_a_downed_player_hears_the_living_within_living_m_one_way() -> void:
	var game := FixtureVoiceMatch.in_round(_round_voice(), [P1, P2])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureVoiceMatch.put(game, P1, Vector3(0, 0, 0))
	FixtureVoiceMatch.put(game, P2, Vector3(5, 0, 0))
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P2)).is_equal([P1])
	assert_array(FixtureVoiceMatch.heard(game, P1)).is_empty()
	FixtureVoiceMatch.put(game, P2, Vector3(5.1, 0, 0))
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P2)).is_empty()


func test_the_downed_never_hear_each_other_however_close() -> void:
	var game := FixtureVoiceMatch.in_round(_round_voice(), [P1, P2, P3])
	for peer: int in [P1, P2, P3]:
		game.state.player(peer).life = PlayerState.Life.DOWNED
		FixtureVoiceMatch.put(game, peer, Vector3.ZERO)
	for peer: int in [P1, P2, P3]:
		assert_array(FixtureVoiceMatch.tick_and_hear(game, peer)).is_empty()


func test_the_dead_hear_nobody_and_are_heard_by_nobody() -> void:
	# Nothing reaches DEAD before M4-2 (#138): the state is set directly.
	var game := FixtureVoiceMatch.in_round(_round_voice(), [P1, P2, P3])
	game.state.player(P2).life = PlayerState.Life.DEAD
	game.state.player(P3).life = PlayerState.Life.DOWNED
	for peer: int in [P1, P2, P3]:
		FixtureVoiceMatch.put(game, peer, Vector3.ZERO)
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_empty()
	assert_array(FixtureVoiceMatch.heard(game, P2)).is_empty()
	assert_array(FixtureVoiceMatch.heard(game, P3)).is_equal([P1])


func test_each_pair_is_measured_between_the_two_players() -> void:
	# P1 living, P2 downed 4 m away, P3 living 7 m away, P4 downed 2 m from P3.
	var game := FixtureVoiceMatch.in_round(_round_voice(), [P1, P2, P3, P4])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	game.state.player(P4).life = PlayerState.Life.DOWNED
	FixtureVoiceMatch.put(game, P1, Vector3(0, 0, 0))
	FixtureVoiceMatch.put(game, P2, Vector3(4, 0, 0))
	FixtureVoiceMatch.put(game, P3, Vector3(7, 0, 0))
	FixtureVoiceMatch.put(game, P4, Vector3(9, 0, 0))
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_empty()
	assert_array(FixtureVoiceMatch.heard(game, P2)).is_equal([P1, P3])
	assert_array(FixtureVoiceMatch.heard(game, P3)).is_empty()
	assert_array(FixtureVoiceMatch.heard(game, P4)).is_equal([P3])


func test_a_player_who_left_hears_and_is_heard_by_nobody() -> void:
	var game := FixtureVoiceMatch.in_round(_round_voice(), [P1, P2, P3])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	game.state.player(P3).life = PlayerState.Life.LEFT
	for peer: int in [P1, P2, P3]:
		FixtureVoiceMatch.put(game, peer, Vector3.ZERO)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureVoiceMatch.heard(game, P1)).is_empty()
	assert_array(FixtureVoiceMatch.heard(game, P2)).is_equal([P1])
	assert_bool(game.view_of(P3).speakers.has(game.ticked_through())).is_false()
	var rule := _round_voice()
	for peer: int in [P1, P2]:
		assert_bool(rule.hears(game.state, peer, P3)).is_false()
		assert_bool(rule.hears(game.state, P3, peer)).is_false()


func test_a_downed_player_moving_away_stops_hearing_at_living_m() -> void:
	var game := FixtureVoiceMatch.in_round(_round_voice(), [P1, P2])
	var p1 := game.state.player(P1)
	var downed := game.state.player(P2)
	downed.life = PlayerState.Life.DOWNED
	var heard_on: Array[bool] = []
	var within_on: Array[bool] = []
	# It crawls away: 0.09 m a tick, within the crawl's 0.05 m and its 0.05 m of slack.
	for i in 140:
		FixtureMoves.step(game, P2, EAST * 0.09, {"moving": true})
		heard_on.append(FixtureVoiceMatch.heard(game, P2) == [P1])
		within_on.append(p1.position.distance_to(downed.position) <= LIVING_M)
		assert_array(FixtureVoiceMatch.heard(game, P1)).is_empty()
	assert_array(heard_on).is_equal(within_on)
	assert_bool(heard_on.front()).is_true()
	assert_bool(heard_on.back()).is_false()


func test_the_radius_must_be_within_its_bounds() -> void:
	assert_array(_errors_of(_round_voice())).is_empty()
	assert_array(_errors_of(_radius(0.5))).is_empty()
	assert_array(_errors_of(_radius(100.0))).is_empty()
	assert_array(_errors_of(RoundVoice.new())).contains(["living_m is 0, outside 0.5 to 100"])
	assert_array(_errors_of(_radius(0.4))).contains(["living_m is 0.4, outside 0.5 to 100"])
	assert_array(_errors_of(_radius(100.5))).contains(["living_m is 100.5, outside 0.5 to 100"])


func _round_voice() -> RoundVoice:
	return _radius(LIVING_M)


func _radius(living_m: float) -> RoundVoice:
	var rule := RoundVoice.new()
	rule.living_m = living_m
	return rule


## The mode check's errors for FixtureModes.basic() with `rule` in the round, each without its
## path.
func _errors_of(rule: VoiceRule) -> Array[String]:
	var found: Array[String] = []
	for message: String in ModeCheck.run(FixtureVoiceMatch.mode(SilentVoice.new(), rule)).errors:
		found.append(message.get_slice(": ", 1))
	return found
