extends GdUnitTestSuite
## Match's allowlist by sender (ARCHITECTURE §3.1, §7.1; invariant 1): the flags PLAYER, HOST and
## DOWNED each against the life states they must refuse, with a control that the same phase
## accepts the intent from the sender it names. Found by the mutants audit of #270.

const P1 := 1
const P2 := 2


func test_a_player_who_left_is_refused_where_every_player_is_accepted() -> void:
	# A left player (life LEFT, still on the roster in the round) sends nothing a rule hears, even
	# under PLAYER, which takes every other player, and even when it is the host under HOST.
	var mode := FixtureModes.basic()
	var round_spec := mode.find_phase(&"round")
	round_spec.accepts = [
		AcceptSpec.of(Intents.USE, AcceptSpec.From.PLAYER | AcceptSpec.From.HOST),
	]
	var game := FixtureModes.in_round(mode, [P1, P2])
	for peer: int in [P1, P2]:
		game.state.player(peer).life = PlayerState.Life.LEFT
	FixtureModes.send(game, Intents.USE, P2, {"facing": Vector3.FORWARD}, 5)
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD}, 6)
	assert_array(FixtureModes.notes(game)).not_contains(["used"])
	for peer: int in [P1, P2]:
		assert_array(game.view_of(peer).events_named(&"FixtureNote")).is_empty()
	# Each is refused, and the refusal reaches nobody: a peer who left is told nothing (§5).
	var last := game.emitted()[game.emitted().size() - 1]
	assert_str((last.event as RejectedEvent).reason).is_equal("not_accepted")
	assert_array(Array(last.recipients)).is_empty()
	# The control: the same phase takes it from a present player.
	game.state.player(P2).life = PlayerState.Life.ALIVE
	FixtureModes.send(game, Intents.USE, P2, {"facing": Vector3.FORWARD}, 7)
	assert_array(FixtureModes.notes(game)).contains(["used"])


func test_an_intent_only_the_downed_may_send_is_refused_from_the_living() -> void:
	# DOWNED takes the downed, and no one else: a living player is refused an intent a phase takes
	# from the downed alone (the base mode's GiveUp).
	var mode := FixtureModes.basic()
	var round_spec := mode.find_phase(&"round")
	round_spec.accepts = [AcceptSpec.of(Intents.USE, AcceptSpec.From.DOWNED)]
	var game := FixtureModes.in_round(mode, [P1, P2])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD}, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_array(FixtureModes.notes(game)).not_contains(["used"])
	# The control: the downed player's is accepted.
	FixtureModes.send(game, Intents.USE, P2, {"facing": Vector3.FORWARD}, 6)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	assert_array(FixtureModes.notes(game)).contains(["used"])
