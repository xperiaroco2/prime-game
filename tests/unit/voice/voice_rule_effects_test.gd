extends GdUnitTestSuite
## The voice rule's drunk effect (#1392; ARCHITECTURE §6, §9.4.5): a speaker's strength follows its
## public drunk value (0 sober, 255 at drunk_max, at least 1 while drunk); effects_of and
## Match.voice_effects_for carry it only for a speaker the listener hears, under the voice
## invariant, and view_of records it per tick; a rule with no drunk_effect carries none; the mode
## check refuses an effect in a mode with no drunk scale. The routing (speakers_of) is unchanged.

const P1 := 1
const P2 := 2
const P3 := 3
const DRUNK_MAX := 100


func test_the_strength_follows_the_drunk_value() -> void:
	assert_int(VoiceRule.strength_of(0, DRUNK_MAX)).is_equal(0)
	assert_int(VoiceRule.strength_of(1, DRUNK_MAX)).is_equal(3)
	assert_int(VoiceRule.strength_of(50, DRUNK_MAX)).is_equal(128)
	assert_int(VoiceRule.strength_of(99, DRUNK_MAX)).is_equal(253)
	assert_int(VoiceRule.strength_of(DRUNK_MAX, DRUNK_MAX)).is_equal(VoiceRule.MAX_STRENGTH)
	# A value past the scale stays at the top; a mode with no scale gives none.
	assert_int(VoiceRule.strength_of(DRUNK_MAX + 5, DRUNK_MAX)).is_equal(VoiceRule.MAX_STRENGTH)
	assert_int(VoiceRule.strength_of(40, 0)).is_equal(0)
	assert_int(VoiceRule.strength_of(-1, DRUNK_MAX)).is_equal(0)


func test_a_heard_drunk_speaker_carries_its_strength_and_a_sober_one_none() -> void:
	var game := _lobby(_drunk_rule(), [P1, P2, P3])
	game.state.player(P2).drunk = 50
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_equal([P2, P3])
	assert_dict(game.voice_effects_for(P1)).is_equal({P2: 128})
	assert_dict(game.voice_effects_for(P3)).is_equal({P2: 128})
	# The speaker's own entry never names itself.
	assert_dict(game.voice_effects_for(P2)).is_empty()
	assert_dict(game.voice_strengths()).is_equal({P2: 128})


func test_the_strength_fades_with_the_drunk_value() -> void:
	var game := _lobby(_drunk_rule(), [P1, P2])
	game.state.player(P2).drunk = DRUNK_MAX
	FixtureModes.run_ticks(game, 1)
	var first := game.ticked_through()
	game.state.player(P2).drunk = 10
	FixtureModes.run_ticks(game, 1)
	var second := game.ticked_through()
	game.state.player(P2).drunk = 0
	FixtureModes.run_ticks(game, 1)
	var effects := game.view_of(P1).effects
	assert_dict(effects[first]).is_equal({P2: VoiceRule.MAX_STRENGTH})
	assert_dict(effects[second]).is_equal({P2: 26})
	# Sober: no entry, and a tick with none is not recorded.
	assert_bool(effects.has(game.ticked_through())).is_false()
	assert_dict(game.voice_effects_for(P1)).is_empty()
	assert_dict(game.voice_strengths()).is_empty()


func test_no_effect_for_a_speaker_the_listener_cannot_hear() -> void:
	var game := _lobby(_drunk_rule(), [P1, P2, P3])
	game.state.player(P2).drunk = 60
	game.state.player(P3).drunk = 60
	# P3 is past the radius from P1.
	FixtureVoiceMatch.put(game, P3, Vector3(20, 0, 0))
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_equal([P2])
	assert_dict(game.voice_effects_for(P1)).is_equal({P2: 153})
	var at := game.ticked_through()
	assert_dict(game.view_of(P1).effects[at]).is_equal({P2: 153})
	# P3 hears nobody, so it gets no effect, though P2 is drunk.
	assert_bool(game.view_of(P3).effects.has(at)).is_false()


func test_the_voice_invariant_holds_for_the_effects() -> void:
	var game := _lobby(_drunk_rule(), [P1, P2, P3])
	game.state.player(P2).drunk = 60
	game.state.player(P3).drunk = 60
	game.state.player(P2).life = PlayerState.Life.DOWNED
	game.state.player(P1).life = PlayerState.Life.DEAD
	FixtureModes.run_ticks(game, 1)
	# Nobody hears the downed P2; the dead P1 hears nobody.
	assert_dict(game.voice_effects_for(P1)).is_empty()
	assert_dict(game.voice_effects_for(P3)).is_empty()
	# The downed P2 still hears the living P3.
	assert_dict(game.voice_effects_for(P2)).is_equal({P3: 153})


func test_a_rule_with_no_drunk_effect_carries_none() -> void:
	var rule := _proximity()
	var game := _lobby(rule, [P1, P2])
	game.state.player(P2).drunk = DRUNK_MAX
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_equal([P2])
	assert_int(rule.effect_strength(game.state, P2)).is_equal(0)
	assert_dict(game.voice_effects_for(P1)).is_empty()
	assert_dict(game.voice_strengths()).is_empty()
	assert_dict(game.view_of(P1).effects).is_empty()


func test_the_routing_is_the_same_with_and_without_the_effect() -> void:
	var with_effect := _lobby(_drunk_rule(), [P1, P2, P3])
	var without := _lobby(_proximity(), [P1, P2, P3])
	for game: Match in [with_effect, without]:
		game.state.player(P2).drunk = 70
		FixtureVoiceMatch.put(game, P3, Vector3(0, 0, 7))
		FixtureModes.run_ticks(game, 1)
	for peer: int in [P1, P2, P3]:
		assert_array(Array(with_effect.speakers_for(peer))).is_equal(
			Array(without.speakers_for(peer))
		)


func test_an_effect_in_a_mode_with_no_drunk_scale_is_refused() -> void:
	var rule := _drunk_rule()
	var mode := FixtureVoiceMatch.mode(rule, SilentVoice.new())
	mode.player_rules.drunk_max = 0
	var errors := _errors_of(mode)
	assert_array(errors).contains(
		["drunk_effect is set, but the mode has no drunk_max, so it would never sound"]
	)
	var round_rule := RoundVoice.new()
	round_rule.living_m = 8.0
	round_rule.drunk_effect = _wobble()
	assert_array(_errors_of(FixtureVoiceMatch.mode(SilentVoice.new(), round_rule))).contains(
		["drunk_effect is set, but the mode has no drunk_max, so it would never sound"]
	)


func test_an_effect_in_a_mode_with_a_drunk_scale_passes() -> void:
	var mode := FixtureVoiceMatch.mode(_drunk_rule(), SilentVoice.new())
	_scale(mode)
	assert_array(_errors_of(mode)).is_empty()


func _lobby(rule: VoiceRule, peers: Array[int]) -> Match:
	var mode := FixtureVoiceMatch.mode(rule, rule)
	_scale(mode)
	var game := FixtureModes.started(mode, peers)
	for i in peers.size():
		FixtureVoiceMatch.put(game, peers[i], Vector3(0, 0, 2 * i))
	return game


static func _scale(mode: GameMode) -> void:
	mode.player_rules.drunk_max = DRUNK_MAX
	mode.player_rules.drunk_too_much_at = 90
	mode.player_rules.drunk_point_s = 1.0


func _proximity() -> ProximityVoice:
	var rule := ProximityVoice.new()
	rule.radius_m = 8.0
	return rule


func _drunk_rule() -> ProximityVoice:
	var rule := _proximity()
	rule.drunk_effect = _wobble()
	return rule


static func _wobble() -> VoiceEffect:
	var effect := VoiceEffect.new()
	effect.id = &"wobble"
	effect.bus_effect = &"FixtureBusEffect"
	effect.parameter = &"depth"
	effect.rest = 1.0
	effect.swing = 0.5
	effect.wobble_hz = 1.0
	return effect


## The mode check's errors for `mode`, each without its path.
func _errors_of(mode: GameMode) -> Array[String]:
	var found: Array[String] = []
	for message: String in ModeCheck.run(mode).errors:
		found.append(message.get_slice(": ", 1))
	return found
