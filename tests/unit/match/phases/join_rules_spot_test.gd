extends GdUnitTestSuite
## A joiner's spot (ARCHITECTURE §3.5; #599, E72): in a phase whose spec's level is NONE (the
## tutorial's `gather`) the joiner stands at the origin with no match error; the rule keys on the
## spec's level, never on the layout being null, so a lobby level with no `lobby_player` marker,
## or whose layout failed to load, still records its match error, and a lobby whose markers are
## all taken still puts the joiner on the first. A Match refuses a lobby layout short of markers
## (LayoutCheck), so those cases call JoinRules.hello with a context built by hand.

const P1 := 1
const P2 := 2
const P3 := 3
const NO_MARKER := "no lobby_player marker for a joiner"


func test_a_join_at_no_level_stands_at_the_origin_with_no_error() -> void:
	var game := _started(_no_level_mode())
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.join(game, peer, "p%d" % peer)
	assert_array(game.state.peers()).is_equal([P1, P2, P3])
	assert_array(Array(game.diagnostics)).is_empty()
	for peer: int in [P1, P2, P3]:
		var player := game.state.player(peer)
		assert_vector(player.position).is_equal(Vector3.ZERO)
		assert_int(player.epoch).is_equal(1)
		var welcome := game.view_of(peer).events_named(&"Welcome")[0] as WelcomeEvent
		assert_vector(welcome.spot).is_equal(Vector3.ZERO)
		assert_str(welcome.phase).is_equal("lobby")
	var joined := game.view_of(P1).events_named(&"PlayerJoined")
	assert_int(joined.size()).is_equal(3)
	assert_vector((joined[2] as PlayerJoinedEvent).spot).is_equal(Vector3.ZERO)
	assert_int(game.state.joins).is_equal(3)
	# Everyone ready: all_ready, the countdown, a join there at no level too, still no error.
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	FixtureBaseMode.join(game, 4, "p4")
	assert_vector(game.state.player(4).position).is_equal(Vector3.ZERO)
	assert_array(Array(game.diagnostics)).is_empty()


func test_at_no_level_the_markers_of_a_layout_are_not_read() -> void:
	# Keys on the spec: a layout at hand (with markers) does not matter at no level.
	var game := FixtureBaseMode.started()
	var ctx := _context(game, _lobby_layout(2))
	var spec := game.mode.find_phase(&"lobby").duplicate() as PhaseSpec
	spec.level = PhaseSpec.Level.NONE
	assert_bool(_hello(game, ctx, P1, spec)).is_true()
	assert_vector(game.state.player(P1).position).is_equal(Vector3.ZERO)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_lobby_level_with_no_lobby_marker_still_errs() -> void:
	var game := FixtureBaseMode.started()
	var layout := LevelLayout.new(FixtureBaseMode.LOBBY)
	layout.add_marker(&"round_player", Vector3(3, 0, 3))
	assert_bool(_hello(game, _context(game, layout), P1, _lobby(game))).is_true()
	assert_vector(game.state.player(P1).position).is_equal(Vector3.ZERO)
	assert_array(Array(game.diagnostics)).has_size(1)
	assert_str(game.diagnostics[0]).contains(NO_MARKER)


func test_a_lobby_level_whose_layout_failed_to_load_still_errs() -> void:
	# Match._layout_of gives null for a lobby layout that is missing, as for no level.
	var game := FixtureBaseMode.started()
	assert_bool(_hello(game, _context(game, null), P1, _lobby(game))).is_true()
	assert_array(Array(game.diagnostics)).has_size(1)
	assert_str(game.diagnostics[0]).contains(NO_MARKER)


func test_a_lobby_whose_markers_are_all_taken_puts_the_joiner_on_the_first() -> void:
	var game := FixtureBaseMode.started()
	var layout := _lobby_layout(2)
	var markers := layout.positions(LayoutCheck.LOBBY_PLAYER)
	var ctx := _context(game, layout)
	assert_bool(_hello(game, ctx, P1, _lobby(game))).is_true()
	assert_bool(_hello(game, ctx, P2, _lobby(game))).is_true()
	assert_vector(game.state.player(P1).position).is_equal(markers[0])
	assert_vector(game.state.player(P2).position).is_equal(markers[1])
	assert_bool(_hello(game, ctx, P3, _lobby(game))).is_true()
	assert_vector(game.state.player(P3).position).is_equal(markers[0])
	assert_array(Array(game.diagnostics)).is_empty()


## FixtureBaseMode's mode with the lobby and the countdown at no level and no lobby level, as the
## tutorial's `gather` (design §2.3); `End -> Lobby` keeps its placement, which these tests never
## reach.
func _no_level_mode() -> GameMode:
	var mode := FixtureBaseMode.mode()
	mode.lobby_level = ""
	for id: StringName in [&"lobby", &"countdown"]:
		mode.find_phase(id).level = PhaseSpec.Level.NONE
	return mode


func _started(mode: GameMode) -> Match:
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureBaseMode.layouts())
	game.keep_history = true
	game.start(0)
	return game


func _lobby(game: Match) -> PhaseSpec:
	return game.mode.find_phase(&"lobby")


func _lobby_layout(count: int) -> LevelLayout:
	var layout := LevelLayout.new(FixtureBaseMode.LOBBY)
	for i in count:
		layout.add_marker(LayoutCheck.LOBBY_PLAYER, Vector3(5 + i * 2, 0, 0))
	return layout


func _context(game: Match, layout: LevelLayout) -> MatchContext:
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	ctx.layout = layout
	return ctx


## `peer` connects through the match, then its Hello goes to JoinRules.hello with `ctx` and `spec`.
func _hello(game: Match, ctx: MatchContext, peer: int, spec: PhaseSpec) -> bool:
	FixtureModes.send(game, Intents.PEER_CONNECTED, peer)
	var fields := {"name": "p%d" % peer, "version": JoinRules.PROTOCOL_VERSION, "content": 0}
	ctx.command = MatchCommand.new(Intents.HELLO, peer, ctx.tick, fields, 0)
	return JoinRules.hello(ctx, ctx.command, spec)
