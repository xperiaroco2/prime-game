extends GdUnitTestSuite
## SilentVoice (ARCHITECTURE §6, §9.4): nobody hears anybody, whatever the distance and the life
## states, on every tick, as recorded for view_of (§5).

const VoiceTestMatch := preload("res://tests/unit/voice/voice_test_match.gd")
const P1 := 1
const P2 := 2
const P3 := 3


func test_nobody_hears_anybody_in_the_lobby() -> void:
	var game := VoiceTestMatch.in_lobby(SilentVoice.new(), [P1, P2, P3])
	for peer: int in [P1, P2, P3]:
		VoiceTestMatch.put(game, peer, Vector3.ZERO)
	FixtureModes.run_ticks(game, 3)
	for peer: int in [P1, P2, P3]:
		var speakers := game.view_of(peer).speakers
		assert_int(speakers.size()).is_equal(3)
		for at: int in speakers:
			assert_array(Array(speakers[at])).is_empty()


func test_nobody_hears_anybody_in_the_round_living_or_dead() -> void:
	var game := VoiceTestMatch.in_round(SilentVoice.new(), [P1, P2, P3])
	game.state.player(P3).life = PlayerState.Life.GHOST
	for peer: int in [P1, P2, P3]:
		assert_array(VoiceTestMatch.tick_and_hear(game, peer)).is_empty()
		assert_array(Array(game.speakers_for(peer))).is_empty()


func test_silence_emits_no_event() -> void:
	var game := VoiceTestMatch.in_round(SilentVoice.new(), [P1, P2])
	var emitted := game.emitted().size()
	FixtureModes.run_ticks(game, 2)
	assert_int(game.emitted().size()).is_equal(emitted)


func test_a_mode_with_silence_passes_the_mode_check() -> void:
	var check := ModeCheck.run(VoiceTestMatch.mode(SilentVoice.new(), SilentVoice.new()))
	assert_array(Array(check.errors)).is_empty()
