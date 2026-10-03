extends GdUnitTestSuite
## The voice invariant (ARCHITECTURE §6, vision revision 1 rework item 3), which
## VoiceRule.speakers_of enforces before any mode's rule runs: only the living speak, so nobody
## hears a downed or dead player; a downed player hears the living; a dead player hears nobody; a
## player who left hears and is heard by nobody. Driven through a seeded match whose round uses
## FixtureEveryoneHears, a rule that lets everyone hear everyone, so what is routed is the
## invariant alone; asserted on the speakers recorded for view_of (§5).

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const PEERS: Array[int] = [P1, P2, P3, P4]


func test_under_a_rule_that_lets_everyone_hear_everyone_the_living_hear_each_other() -> void:
	var game := _in_round()
	FixtureVoiceMatch.put(game, P4, Vector3(90, 0, 90))
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_equal([P2, P3, P4])
	assert_array(FixtureVoiceMatch.heard(game, P4)).is_equal([P1, P2, P3])


func test_nobody_hears_a_downed_player_and_the_downed_hear_only_the_living() -> void:
	var game := _in_round()
	game.state.player(P2).life = PlayerState.Life.DOWNED
	game.state.player(P3).life = PlayerState.Life.DOWNED
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_equal([P4])
	assert_array(FixtureVoiceMatch.heard(game, P4)).is_equal([P1])
	assert_array(FixtureVoiceMatch.heard(game, P2)).is_equal([P1, P4])
	assert_array(FixtureVoiceMatch.heard(game, P3)).is_equal([P1, P4])


func test_a_dead_player_hears_nobody_and_nobody_hears_it() -> void:
	# The state is set directly, as LifeTicks sets it at the end of a knockdown.
	var game := _in_round()
	game.state.player(P2).life = PlayerState.Life.DEAD
	game.state.player(P3).life = PlayerState.Life.DOWNED
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureVoiceMatch.heard(game, P2)).is_empty()
	assert_array(Array(game.speakers_for(P2))).is_empty()
	assert_array(FixtureVoiceMatch.heard(game, P1)).is_equal([P4])
	assert_array(FixtureVoiceMatch.heard(game, P3)).is_equal([P1, P4])
	assert_array(FixtureVoiceMatch.heard(game, P4)).is_equal([P1])


func test_a_player_who_left_hears_and_is_heard_by_nobody() -> void:
	var game := _in_round()
	game.state.player(P4).life = PlayerState.Life.LEFT
	assert_array(FixtureVoiceMatch.tick_and_hear(game, P1)).is_equal([P2, P3])
	assert_bool(game.view_of(P4).speakers.has(game.ticked_through())).is_false()
	assert_array(Array(game.speakers_for(P4))).is_empty()


func test_the_invariant_holds_on_every_tick_as_life_states_change() -> void:
	# Written from the life states alone, never the rule: every recorded speaker was living on
	# that tick, and a listener dead on that tick heard nobody.
	var game := _in_round()
	var life_on: Dictionary[int, Dictionary] = {}
	for step in 10:
		match step:
			2:
				game.state.player(P2).life = PlayerState.Life.DOWNED
			4:
				game.state.player(P3).life = PlayerState.Life.DEAD
			6:
				game.state.player(P2).life = PlayerState.Life.ALIVE
			8:
				game.state.player(P4).life = PlayerState.Life.LEFT
		FixtureModes.run_ticks(game, 1)
		var lives := {}
		for peer: int in PEERS:
			lives[peer] = game.state.player(peer).life
		life_on[game.ticked_through()] = lives
	var checked := 0
	for peer: int in PEERS:
		var speakers := game.view_of(peer).speakers
		for at: int in speakers:
			if not life_on.has(at):
				continue
			var lives: Dictionary = life_on[at]
			if lives[peer] == PlayerState.Life.DEAD:
				assert_array(Array(speakers[at])).is_empty()
			for speaker: int in speakers[at]:
				assert_int(lives[speaker] as int).is_equal(PlayerState.Life.ALIVE)
				checked += 1
	assert_int(checked).is_greater(0)


func test_the_base_class_hears_nobody_and_its_hearing_radius_is_0() -> void:
	# E41: the client's cutoff for a rule that routes nobody.
	var game := FixtureVoiceMatch.in_round(VoiceRule.new(), PEERS)
	for peer: int in PEERS:
		FixtureVoiceMatch.put(game, peer, Vector3.ZERO)
	for peer: int in PEERS:
		assert_array(FixtureVoiceMatch.tick_and_hear(game, peer)).is_empty()
	var rule := game.mode.find_phase(game.phase_id()).voice_rule
	assert_float(rule.hearing_radius_m()).is_equal(0.0)
	assert_float(VoiceRule.radius_of(rule)).is_equal(0.0)


func test_a_phase_with_no_voice_rule_hears_nobody_and_its_radius_is_0() -> void:
	# VoiceRule.radius_of(null): the one helper the client and the leak test read (E41).
	var mode := FixtureVoiceMatch.mode(null, FixtureEveryoneHears.new())
	var game := FixtureModes.started(mode, PEERS)
	for peer: int in PEERS:
		FixtureVoiceMatch.put(game, peer, Vector3.ZERO)
	assert_str(game.phase_id()).is_equal("lobby")
	for peer: int in PEERS:
		assert_array(FixtureVoiceMatch.tick_and_hear(game, peer)).is_empty()
		assert_bool(game.view_of(peer).speakers.has(game.ticked_through())).is_true()
	assert_object(game.mode.find_phase(game.phase_id()).voice_rule).is_null()
	assert_float(VoiceRule.radius_of(null)).is_equal(0.0)


func test_radius_of_reads_the_rule_s_own_hearing_radius() -> void:
	var near := ProximityVoice.new()
	near.radius_m = 12.5
	var round_voice := RoundVoice.new()
	round_voice.living_m = 3.25
	assert_float(VoiceRule.radius_of(near)).is_equal(12.5)
	assert_float(VoiceRule.radius_of(round_voice)).is_equal(3.25)
	assert_float(VoiceRule.radius_of(SilentVoice.new())).is_equal(0.0)


func _in_round() -> Match:
	return FixtureVoiceMatch.in_round(FixtureEveryoneHears.new(), PEERS)
