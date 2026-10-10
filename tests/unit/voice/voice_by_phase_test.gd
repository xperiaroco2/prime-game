extends GdUnitTestSuite
## The voice rules through the base mode's phases (ARCHITECTURE §6, §9.5), with the base mode's
## phase classes and rows built in code (FixtureBaseMode) and its voice rules: Lobby and
## Countdown ProximityVoice 8 m, Loading, Pregame and End SilentVoice, Round RoundVoice 8 m. A
## match is driven through Lobby -> Countdown -> Loading -> Pregame -> Round -> End -> Lobby, and
## on every tick
## view_of(peer).speakers is compared with the pairs the phase's rule allows, and with the voice
## invariant (§6) written independently of the rules: every speaker is living.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]
const RADIUS_M := 8.0
const FAR := Vector3(50, 0, 50)


func test_each_phase_routes_the_pairs_of_its_rule_on_every_tick() -> void:
	var game := _started()
	var seen: Dictionary[StringName, int] = {}
	for peer: int in PEERS:
		FixtureBaseMode.join(game, peer)
	FixtureVoiceMatch.put(game, P3, FAR)
	_check_ticks(game, 3, seen)
	for peer: int in PEERS:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	_check_ticks(game, 101, seen)
	assert_str(game.phase_id()).is_equal("loading")
	_check_ticks(game, 3, seen)
	for peer: int in PEERS:
		FixtureBaseMode.load_ack(game, peer)
	# Pregame routes nobody on every tick of its 3 s (#213), with everyone placed within 2 m of each
	# other, then the round begins by itself.
	assert_str(game.phase_id()).is_equal("pregame")
	_check_ticks(game, FixtureBaseMode.PREGAME_TICKS, seen)
	assert_str(game.phase_id()).is_equal("pregame")
	_check_ticks(game, 1, seen)
	assert_str(game.phase_id()).is_equal("round")
	_check_ticks(game, 2, seen)
	# P2 is downed beside P1; P3 walks off, out of every radius.
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureVoiceMatch.put(game, P2, game.state.player(P1).position + Vector3(0, 0, 1))
	_check_ticks(game, 2, seen)
	FixtureVoiceMatch.put(game, P3, FAR)
	_check_ticks(game, 2, seen)
	game.state.add_to_counter(0, &"crew_win", 1)
	_check_ticks(game, 1, seen)
	game.state.set_counter(0, &"crew_win", 0)
	assert_str(game.phase_id()).is_equal("end")
	# End routes nobody on every tick of its 3 s, until it returns everyone by itself (#212; the
	# silent post game of #213 relies on it).
	_check_ticks(game, 3 * Ticks.RATE - 1, seen)
	assert_str(game.phase_id()).is_equal("end")
	_check_ticks(game, 1, seen)
	assert_str(game.phase_id()).is_equal("lobby")
	_check_ticks(game, 3, seen)
	# Every phase was checked, and the phases with voice routed some pair.
	assert_array(seen.keys()).contains_exactly_in_any_order(
		[&"lobby", &"countdown", &"loading", &"pregame", &"round", &"end"]
	)
	assert_int(seen[&"lobby"]).is_greater(0)
	assert_int(seen[&"countdown"]).is_greater(0)
	assert_int(seen[&"round"]).is_greater(0)
	assert_int(seen[&"loading"]).is_equal(0)
	assert_int(seen[&"pregame"]).is_equal(0)
	assert_int(seen[&"end"]).is_equal(0)


func test_each_phase_s_hearing_radius_is_where_its_routing_stops() -> void:
	# E41: VoiceRule.radius_of the phase's rule, what the client's cutoff and the leak test read:
	# 8 m in the Lobby, the Countdown and the Round, 0 in Loading, Pregame and End. In each phase P2
	# stands at that radius from P1 and P3 just past it: P2 is heard where the radius is not 0.
	var game := _started()
	var radius_in: Dictionary[StringName, float] = {}
	for peer: int in PEERS:
		FixtureBaseMode.join(game, peer)
	_check_radius(game, radius_in)
	for peer: int in PEERS:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	_check_radius(game, radius_in)
	while game.phase_id() == &"countdown":
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("loading")
	_check_radius(game, radius_in)
	for peer: int in PEERS:
		FixtureBaseMode.load_ack(game, peer)
	assert_str(game.phase_id()).is_equal("pregame")
	_check_radius(game, radius_in)
	while game.phase_id() == &"pregame":
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("round")
	_check_radius(game, radius_in)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	game.state.set_counter(0, &"crew_win", 0)
	assert_str(game.phase_id()).is_equal("end")
	_check_radius(game, radius_in)
	var want: Dictionary[StringName, float] = {
		&"lobby": RADIUS_M,
		&"countdown": RADIUS_M,
		&"loading": 0.0,
		&"pregame": 0.0,
		&"round": RADIUS_M,
		&"end": 0.0,
	}
	assert_dict(radius_in).is_equal(want)


func test_in_the_round_a_downed_player_hears_a_living_player_who_cannot_hear_it() -> void:
	var game := _in_round()
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureVoiceMatch.put(game, P3, FAR)
	FixtureModes.run_ticks(game, 1)
	var at := game.ticked_through()
	assert_array(Array(game.view_of(P1).speakers[at])).is_empty()
	assert_array(Array(game.view_of(P2).speakers[at])).is_equal([P1])
	assert_array(Array(game.view_of(P3).speakers[at])).is_empty()


func test_nobody_hears_a_downed_player_on_any_tick() -> void:
	# The voice invariant (§6), written without reading the rules: every listener's speakers, on
	# every recorded tick, were alive on that tick.
	var game := _in_round()
	var alive_on: Dictionary[int, Array] = {}
	for step in 12:
		if step == 3:
			game.state.player(P2).life = PlayerState.Life.DOWNED
		if step == 6:
			game.state.player(P3).life = PlayerState.Life.DOWNED
		if step == 9:
			game.state.player(P2).life = PlayerState.Life.LEFT
		FixtureModes.run_ticks(game, 1)
		alive_on[game.ticked_through()] = _alive(game)
	var checked := 0
	for peer: int in PEERS:
		var speakers := game.view_of(peer).speakers
		for at: int in speakers:
			if not alive_on.has(at):
				continue
			for speaker: int in speakers[at]:
				assert_array(alive_on[at]).contains([speaker])
				checked += 1
	assert_int(checked).is_greater(0)


## A started match of the base mode's phases with its voice rules, keeping its history.
func _started() -> Match:
	var game := Match.new(_mode(), 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	assert_array(Array(game.refusals)).is_empty()
	return game


func _in_round() -> Match:
	var game := _started()
	for peer: int in PEERS:
		FixtureBaseMode.join(game, peer)
	for peer: int in PEERS:
		FixtureBaseMode.ready(game, peer)
	FixtureModes.run_ticks(game, 101)
	for peer: int in PEERS:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	assert_str(game.phase_id()).is_equal("round")
	return game


## FixtureBaseMode.mode() with the base mode's voice rules (§9.5).
func _mode() -> GameMode:
	var mode := FixtureBaseMode.mode()
	var near := ProximityVoice.new()
	near.radius_m = RADIUS_M
	var round_voice := RoundVoice.new()
	round_voice.living_m = RADIUS_M
	mode.find_phase(&"lobby").voice_rule = near
	mode.find_phase(&"countdown").voice_rule = near
	mode.find_phase(&"loading").voice_rule = SilentVoice.new()
	mode.find_phase(&"pregame").voice_rule = SilentVoice.new()
	mode.find_phase(&"round").voice_rule = round_voice
	mode.find_phase(&"end").voice_rule = SilentVoice.new()
	return mode


## Notes the hearing radius of `game`'s phase in `radius_in`, then puts P2 at that radius from P1
## and P3 just past it for one tick: P1 hears P2 alone where the radius is not 0, else nobody.
func _check_radius(game: Match, radius_in: Dictionary[StringName, float]) -> void:
	var phase := game.phase_id()
	var radius := VoiceRule.radius_of(game.mode.find_phase(phase).voice_rule)
	radius_in[phase] = radius
	FixtureVoiceMatch.put(game, P1, Vector3.ZERO)
	FixtureVoiceMatch.put(game, P2, Vector3(0, 0, radius))
	FixtureVoiceMatch.put(game, P3, Vector3(radius + 0.01, 0, 0))
	var heard := FixtureVoiceMatch.tick_and_hear(game, P1)
	assert_str(game.phase_id()).is_equal(phase)
	var want := [P2] if radius > 0.0 else []
	assert_array(heard).override_failure_message("phase %s heard %s" % [phase, heard]).is_equal(
		want
	)


## Runs `count` ticks; after each, compares every present peer's recorded speakers with
## _expected() and counts the routed pairs per phase into `seen`.
func _check_ticks(game: Match, count: int, seen: Dictionary[StringName, int]) -> void:
	for i in count:
		FixtureModes.run_ticks(game, 1)
		var at := game.ticked_through()
		var phase := game.phase_id()
		if not seen.has(phase):
			seen[phase] = 0
		for peer: int in game.state.present_peers():
			var got := Array(game.view_of(peer).speakers[at])
			var want := _expected(game, phase, peer)
			(
				assert_array(got)
				. override_failure_message(
					(
						"tick %d, phase %s, peer %d: heard %s, expected %s"
						% [at, phase, peer, got, want]
					)
				)
				. is_equal(want)
			)
			seen[phase] += got.size()
			# The voice invariant, independent of the rules: only the living are heard.
			for speaker: int in got:
				assert_bool(game.state.player(speaker).is_alive()).is_true()


## The speakers the base mode's §6 table allows `listener` in `phase`, from the state alone.
func _expected(game: Match, phase: StringName, listener: int) -> Array:
	var want := []
	if phase in [&"loading", &"pregame", &"end"]:
		return want
	var ear := game.state.player(listener)
	for speaker: int in game.state.present_peers():
		if speaker == listener:
			continue
		var mouth := game.state.player(speaker)
		var near := ear.position.distance_to(mouth.position) <= RADIUS_M
		# Only the living are heard, in every phase (the voice invariant).
		if near and mouth.life == PlayerState.Life.ALIVE:
			want.append(speaker)
	return want


func _alive(game: Match) -> Array[int]:
	var found: Array[int] = []
	for peer: int in game.state.peers():
		if game.state.player(peer).life == PlayerState.Life.ALIVE:
			found.append(peer)
	return found
