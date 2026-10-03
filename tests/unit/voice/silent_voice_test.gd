extends GdUnitTestSuite
## SilentVoice (ARCHITECTURE §6, §9.4): nobody hears anybody, whatever the distance and the life
## states, on every tick, as recorded for view_of (§5).

const P1 := 1
const P2 := 2
const P3 := 3


func test_nobody_hears_anybody_in_the_lobby() -> void:
	var game := FixtureVoiceMatch.in_lobby(SilentVoice.new(), [P1, P2, P3])
	for peer: int in [P1, P2, P3]:
		FixtureVoiceMatch.put(game, peer, Vector3.ZERO)
	FixtureModes.run_ticks(game, 3)
	for peer: int in [P1, P2, P3]:
		var speakers := game.view_of(peer).speakers
		assert_int(speakers.size()).is_equal(3)
		for at: int in speakers:
			assert_array(Array(speakers[at])).is_empty()


func test_nobody_hears_anybody_in_the_round_living_or_dead() -> void:
	var game := FixtureVoiceMatch.in_round(SilentVoice.new(), [P1, P2, P3])
	game.state.player(P3).life = PlayerState.Life.DOWNED
	for peer: int in [P1, P2, P3]:
		assert_array(FixtureVoiceMatch.tick_and_hear(game, peer)).is_empty()
		assert_array(Array(game.speakers_for(peer))).is_empty()


func test_silence_emits_no_event() -> void:
	var game := FixtureVoiceMatch.in_round(SilentVoice.new(), [P1, P2])
	var emitted := game.emitted().size()
	FixtureModes.run_ticks(game, 2)
	assert_int(game.emitted().size()).is_equal(emitted)


func test_its_hearing_radius_is_0() -> void:
	# E41: the client's cutoff in a silent phase, which sends and plays nothing.
	var game := FixtureVoiceMatch.in_round(SilentVoice.new(), [P1, P2])
	var rule := game.mode.find_phase(game.phase_id()).voice_rule
	assert_object(rule).is_instanceof(SilentVoice)
	assert_float(rule.hearing_radius_m()).is_equal(0.0)
	assert_float(VoiceRule.radius_of(rule)).is_equal(0.0)


func test_a_mode_with_silence_passes_the_mode_check() -> void:
	var check := ModeCheck.run(FixtureVoiceMatch.mode(SilentVoice.new(), SilentVoice.new()))
	assert_array(Array(check.errors)).is_empty()
