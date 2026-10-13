extends GdUnitTestSuite
## The §5 invariants with a body in motion (the knockdown rework's §9, KE5, #847): no scenario
## moves a body (the greybox, KE12), so this core-runner test drives a fixture mode whose
## motion_maps lists its map (FixtureModes.MOTION_MAP) through a launching strike and scripted
## reports (the test plays server/, feeding BodyMoved), running ScenarioInvariants (the snapshots,
## the own-avatar check, the voice and its distance) on every call and every tick of the motion.
## And the own-avatar check itself (ScenarioInvariants.own_avatar_problem, read from the life
## state, never from Snapshots.for_peer), seen failing on a planted own avatar of a living player
## and on a missing own avatar of a knocked-down one. LeakCheck's: bots_runner_test.gd.

const P1 := 1
const P2 := 2
const P3 := 3
const PEERS: Array[int] = [P1, P2, P3]
const NORTH := Vector3(0, 0, 1)

var _game: Match
var _invariants: ScenarioInvariants
var _checked := 0
var _found := PackedStringArray()


func test_the_invariants_hold_on_every_tick_of_a_motion() -> void:
	var mode := FixtureCombatModes.raising()
	var strike := mode.find_item_kind(&"knife").actions[0].effects[0] as Strike
	strike.launch_mps = 4.0
	strike.launch_up_mps = 3.0
	# The match starts on its first map, the one motion_maps lists; the Round hears within 20 m, so
	# the distance invariant has a radius to check.
	mode.maps = PackedStringArray([FixtureModes.MOTION_MAP, FixtureModes.MAP])
	var voice := RoundVoice.new()
	voice.living_m = 20.0
	mode.find_phase(&"round").voice_rule = voice
	_game = Match.new(mode, 7, FlatWorldQuery.new(), FixtureModes.layouts())
	_game.keep_history = true
	_invariants = ScenarioInvariants.new(_game, BotScenario.new())
	_game.start(0)
	for peer: int in PEERS:
		_send(Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in PEERS:
		_send(Intents.SET_READY, peer, {"ready": true})
	FixtureCombatModes.arm(_game, P1, Vector3.ZERO)
	FixtureItemModes.stand(_game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(_game, P3, Vector3(2, 0, 2))
	_send(Intents.USE, P1, {"facing": NORTH})
	for i in FixtureCombatModes.COOLDOWN_TICKS:
		_tick()
	_send(Intents.USE, P1, {"facing": NORTH})
	var downed := _game.state.player(P2)
	assert_object(downed.motion).is_not_null()
	# The flight, as server/ would report it: up, along, down, then slow on the floor.
	var at := downed.position
	var velocity := downed.velocity
	var moving_ticks := 0
	while downed.motion != null:
		velocity.y -= 0.5
		at += velocity / 20.0
		if at.y <= 0.0:
			at.y = 0.0
			velocity = velocity * 0.5
			velocity.y = 0.0
		var args := {"epoch": downed.motion.epoch, "position": at, "velocity": velocity}
		_apply(MatchCommand.new(Intents.BODY_MOVED, P2, _game.ticked_through() + 1, args))
		_tick()
		moving_ticks += 1
		if moving_ticks >= 200:
			break
	assert_int(moving_ticks).is_between(11, 199)
	assert_vector(downed.position).is_equal(Vector3(at.x, 0, at.z))
	# Then the body lies at rest, every tick still checked.
	for i in 40:
		_tick()
	assert_int(_checked).is_greater(moving_ticks)
	assert_array(Array(_found)).is_empty()
	assert_array(Array(_game.diagnostics)).is_empty()


func test_an_own_avatar_of_a_living_player_is_caught() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	var avatars: Dictionary = (game.snapshot_for(P1)["avatars"] as Dictionary).duplicate()
	assert_str(ScenarioInvariants.own_avatar_problem(P1, avatars, false)).is_empty()
	avatars[P1] = avatars[P2]
	assert_str(ScenarioInvariants.own_avatar_problem(P1, avatars, false)).is_equal(
		"shows peer 1 its own avatar, not knocked down"
	)


func test_a_missing_own_avatar_of_a_knocked_down_player_is_caught() -> void:
	var game := FixtureModes.in_round(FixtureModes.basic(), [P1, P2])
	game.state.player(P2).life = PlayerState.Life.DOWNED
	var avatars: Dictionary = (game.snapshot_for(P2)["avatars"] as Dictionary).duplicate()
	assert_bool(avatars.has(P2)).is_true()
	assert_str(ScenarioInvariants.own_avatar_problem(P2, avatars, true)).is_empty()
	avatars.erase(P2)
	assert_str(ScenarioInvariants.own_avatar_problem(P2, avatars, true)).is_equal(
		"lacks the own avatar of knocked-down peer 2"
	)


func _send(kind: StringName, peer: int, args: Dictionary) -> void:
	_apply(MatchCommand.new(kind, peer, _game.ticked_through() + 1, args))


## Applies `command` and checks its call, as the core runner does.
func _apply(command: MatchCommand) -> void:
	var from := _game.emitted().size()
	_game.apply(command)
	_found.append_array(_invariants.check_call(command, _since(from)))


## Runs the next tick and checks its events, its snapshots and its voice routing.
func _tick() -> void:
	var from := _game.emitted().size()
	_game.tick(_game.ticked_through() + 1)
	_found.append_array(_invariants.check_call(null, _since(from)))
	_checked += 1


func _since(from: int) -> Array[EmittedEvent]:
	var slice: Array[EmittedEvent] = []
	slice.assign(_game.emitted().slice(from))
	return slice
