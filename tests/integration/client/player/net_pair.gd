extends Node
## Two game roots over a LoopbackHub, for the movement suites of M4-7 (ARCHITECTURE §4.7): a host
## Game (HostSession and its own ClientSession) and a Game that joins it, each in a SubViewport
## with a physics world of its own, as two machines would be. The level is the fixture
## `steps_room.tscn` in FixtureBaseMode's mode (its lobby and its map). The clock is simulated and
## advances one physics frame (1/60 s) before the sessions step, so 20 Hz claims, host ticks and
## snapshots keep pace with the physics; with `uneven` it stands still for one frame and then
## advances two, as a real clock does around a hitch. Nothing reads devices: a suite drives each
## PlayerController's wish fields. Forward is -Z.
##
## steps_room: a floor at y = 0; lobby markers (0, 0, 0) and (0, 0, -2) first (the host takes the
## first, the joiner the second); along z = -2 three steps of 0.3 m, each 0.5 m deep, from x = 6,
## then a top at 1.2 m from x = 7.5 to 13.5. The treads are 0.5 m on purpose: on 0.3 m treads,
## narrower than the capsule, the host's height check (MovementRule's slope rise from a landing
## floor found by five rays, #76's to tune) corrects an honest climb, walking or sprinting.
## Respawn markers at (8, 0, 12) and (12, 0, 12) serve with_life()'s respawn.

const GAME := preload("res://client/app/game.tscn")
const STEPS_ROOM := "res://tests/fixtures/client/steps_room.tscn"
const PORT := 7400
## One physics frame at 60 Hz, in microseconds.
const FRAME_USEC := 16667
## The most physics frames start() waits for both to stand in the lobby.
const MAX_START_FRAMES := 300
## The most physics frames to_round() waits: the fixture's 5 s countdown is 300, then the load.
const MAX_ROUND_FRAMES := 1200

var host: Game
var client: Game
var mode: GameMode
## The simulated clock, in microseconds.
var now := 1000000
## The clock alternates: no advance in one physics frame, two frames' worth in the next.
var uneven := false

var _held := false

var _hub := LoopbackHub.new()


func _init() -> void:
	# Before HostNode (-100): the clock moves first in every physics frame.
	process_physics_priority = -1000
	mode = FixtureBaseMode.mode()
	mode.lobby_level = STEPS_ROOM
	mode.maps = PackedStringArray([STEPS_ROOM])


## Hosts, joins, and waits until both players stand in the lobby; false when they never did.
func start() -> bool:
	host = _game(["--host", "--local", "--no-replay", "--port=%d" % PORT])
	client = _game(["--join=127.0.0.1", "--port=%d" % PORT])
	for i: int in MAX_START_FRAMES:
		if _both_in_the_lobby():
			# A frame more, so each player has stood still once on its own floor.
			await frames(5)
			return true
		await frames(1)
	return false


## Both ready up; the countdown runs, both load the map and the host places them at its round
## markers (PlayersPlaced and a Correction each, at Loading's end). Calls `each_frame` every
## physics frame on the way. False when the round never began for both.
func to_round(each_frame := Callable()) -> bool:
	host.set_ready(true)
	client.set_ready(true)
	for i: int in MAX_ROUND_FRAMES:
		if _both_in_the_round():
			await frames(5)
			return true
		await frames(1)
		if each_frame.is_valid():
			each_frame.call()
	return false


## Ends both sessions as the players would (the joiner leaves, the host closes) and lets the
## freed levels and views go: call it at the end of every test, or they are orphans.
func stop() -> void:
	if client != null:
		client.leave()
	if host != null:
		host.leave()
	await get_tree().process_frame


## Waits `count` physics frames.
func frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## The peer id of `game`'s own player.
func peer_of(game: Game) -> int:
	return game.client().model.own_peer


## Gives the mode the life rules of the base mode (M4-9's suites), before start(): the Round's
## LifeTicks with a Respawn on the `respawn` markers after `respawn_s` seconds, the raise (3 s,
## 2 m), StopRaise and GiveUp (FixtureCombatModes), accepted as the base mode accepts them.
func with_life(respawn_s: float) -> void:
	mode.player_rules.respawn_s = respawn_s
	var ticks := LifeTicks.new()
	ticks.respawn = FixtureCombatModes.respawn()
	var round_spec := mode.find_phase(&"round")
	round_spec.tick_systems.append_array([ticks, ChannelTicks.new()])
	round_spec.accepts.append(AcceptSpec.of(Intents.RAISE, AcceptSpec.From.LIVING))
	round_spec.accepts.append(AcceptSpec.of(Intents.STOP_RAISE, AcceptSpec.From.LIVING))
	round_spec.accepts.append(AcceptSpec.of(Intents.GIVE_UP, AcceptSpec.From.DOWNED))
	(
		mode
		. actions
		. append_array(
			[
				FixtureCombatModes.raise_rule(),
				FixtureCombatModes.stop_raise_rule(),
				FixtureCombatModes.give_up_rule(),
			]
		)
	)


## Knocks `game`'s player down on the host as a strike to 0 health would (LifeRules.knock_down,
## M4-2): KnockedDown to everyone and its Correction go out with the host's next tick. The fixture
## level has no weapon, so this reaches into the host's Match, which only a test may do: Game and
## HostNode keep it private (E18). The floor of steps_room's round spots is at y = 0.
func knock_down(game: Game) -> void:
	var node := host.get_node("HostNode") as HostNode
	var session := node.get("_session") as HostSession
	var played := session.game
	var peer := peer_of(game)
	var ctx := MatchContext.new(played)
	ctx.state = played.state
	ctx.mode = played.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = played.ticked_through()
	played.state.player(peer).health = 0
	LifeRules.knock_down(ctx, peer)


func _physics_process(_delta: float) -> void:
	if not uneven:
		now += FRAME_USEC
		return
	_held = not _held
	if not _held:
		now += 2 * FRAME_USEC


func _both_in_the_lobby() -> bool:
	for game: Game in [host, client]:
		var session := game.client()
		if session == null or not session.is_welcomed() or game.player() == null:
			return false
		if session.model.roster.size() != 2 or game.screen() != GameFlow.Screen.LOBBY:
			return false
	return true


func _both_in_the_round() -> bool:
	for game: Game in [host, client]:
		var session := game.client()
		if session == null or session.model.phase != &"round" or game.player() == null:
			return false
	return true


func _game(args: Array[String]) -> Game:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var game := GAME.instantiate() as Game
	game.mode = mode
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = _clock
	game.make_transport = _transport
	game.device_input = false
	viewport.add_child(game)
	return game


func _clock() -> int:
	return now


func _transport() -> NetTransport:
	return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)
