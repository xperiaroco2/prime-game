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
## The most physics frames walk_to() walks.
const MAX_WALK_FRAMES := 600

var host: Game
var client: Game
var mode: GameMode
## The simulated clock, in microseconds.
var now := 1000000
## The clock alternates: no advance in one physics frame, two frames' worth in the next.
var uneven := false
## Physics frames every packet between the two Games is held back, each way (#155): set before
## start(). The host's own client is not delayed.
var delay_frames := 0
## Up to this many physics frames more for each packet, drawn from a generator seeded per
## transport, the packets still arriving in order (#155): a network's jitter. Set before start().
var jitter_frames := 0
## The host's transport, which the joiner's packets reach (its latest_superseded counts the claims
## the LATEST lane merged); null until the host started.
var host_transport: DelayedTransport

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
	host = _game(["--host", "--local", "--no-replay", "--port=%d" % PORT], 1)
	client = _game(["--join=127.0.0.1", "--port=%d" % PORT], 2)
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


## Holds every packet that reaches the host from now on for `count` physics frames, then hands
## them over in one poll, as a network that stalls and bursts would (#155): the LATEST lane merges
## the claims among them into the newest. The packets held before stay in order.
func hold_at_host(count: int) -> void:
	host_transport.hold_for(count)


## Waits `count` physics frames.
func frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## The peer id of `game`'s own player.
func peer_of(game: Game) -> int:
	return game.client().model.own_peer


## Turns `player`'s camera at `point`.
func aim(player: PlayerController, point: Vector3) -> void:
	var eye := player.get_camera().global_position
	var to := point - eye
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var current_pitch := player.get_camera().get_parent_node_3d().rotation.x
	player.look(angle_difference(player.rotation.y, yaw), pitch - current_pitch)


## Walks `player` toward `target` on the floor, turning to it every frame; false when it is not
## within 0.2 m after MAX_WALK_FRAMES frames. It stops giving input once there.
func walk_to(player: PlayerController, target: Vector3) -> bool:
	for i: int in MAX_WALK_FRAMES:
		var to := target - player.global_position
		to.y = 0.0
		if to.length() < 0.2:
			player.move_input = Vector2.ZERO
			return true
		player.look(angle_difference(player.rotation.y, atan2(-to.x, -to.z)), 0.0)
		player.move_input = Vector2(0.0, 1.0)
		await frames(1)
	player.move_input = Vector2.ZERO
	return false


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


## Gives the mode knives and the pick-up (#319's suite), before start(): the item kind `knife`,
## the base mode's PickUp (ItemOnGround, InReach 2 m, InSight; TakeIntoHand: FixtureItemModes)
## accepted from the living in the round, and SpawnItems on the `all_loaded` row in place of the
## FixtureDemand of knife markers it stands in for, which puts `count` knives on steps_room's knife
## markers (at most its 3: (-10, 0, 10), (-8, 0, 10) and (-6, 0, 10)).
func with_knives(count: int) -> void:
	var knife := FixtureItemModes.item_kind(&"knife", [])
	mode.item_kinds.append(knife)
	mode.actions.append(FixtureItemModes.pick_up_rule(FixtureItemModes.REACH_M))
	mode.find_phase(&"round").accepts.append(AcceptSpec.of(Intents.PICK_UP, AcceptSpec.From.LIVING))
	mode.find_setting(&"knives").default_value = count
	var spawn := SpawnItems.new()
	spawn.kind = knife
	spawn.count_setting = &"knives"
	spawn.rng_purpose = &"knives"
	var actions := mode.find_transition(&"loading", LoadingPhase.ALL_LOADED).actions
	for i: int in actions.size():
		var demand := actions[i] as FixtureDemand
		if demand != null and demand.tag == &"knife":
			actions[i] = spawn


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


## A Game with these launch args; its transports are number `number`'s (1 the host, 2 the joiner).
func _game(args: Array[String], number: int) -> Game:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var game := GAME.instantiate() as Game
	game.mode = mode
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = _clock
	game.make_transport = _transport.bind(number)
	game.device_input = false
	viewport.add_child(game)
	return game


func _clock() -> int:
	return now


func _transport(number: int) -> NetTransport:
	var kinds := WireSchema.game(OS.is_debug_build()).kind_table()
	var transport := DelayedTransport.new(kinds, _hub, DelayedTransport.SEED + number)
	transport.delay = delay_frames
	transport.jitter = jitter_frames
	if number == 1:
		host_transport = transport
	return transport


## A LoopbackTransport that holds every packet it receives back for `delay` of its polls (one per
## physics frame) and up to `jitter` more, drawn from its own seed, in order, as a network's
## latency and jitter would, and holds them all while hold_for() says so; connection events pass
## at once.
class DelayedTransport:
	extends LoopbackTransport
	const SEED := 155
	var delay := 0
	var jitter := 0
	var _polls := 0
	## Packets received before this poll are handed over at it, all at once.
	var _hold_until := 0
	var _rng := RandomNumberGenerator.new()
	## The poll each held packet is due at, and the packets, oldest first.
	var _due: Array[int] = []
	var _held: Array[NetTransport.Inbound] = []

	func poll() -> void:
		_polls += 1
		while not _held.is_empty() and _due[0] <= _polls:
			_due.pop_front()
			var item: NetTransport.Inbound = _held.pop_front()
			super._push(item)
		super()

	func _init(kinds: NetKindTable, hub: LoopbackHub = null, rng_seed := SEED) -> void:
		super(kinds, hub)
		_rng.seed = rng_seed

	func hold_for(count: int) -> void:
		_hold_until = _polls + count

	func _push(item: NetTransport.Inbound) -> void:
		var holding := _hold_until > _polls
		if item.type != NetTransport.Inbound.Type.PACKET:
			super(item)
			return
		if delay <= 0 and jitter <= 0 and not holding:
			super(item)
			return
		var due := _polls + delay + _rng.randi_range(0, jitter)
		if holding:
			due = maxi(due, _hold_until)
		if not _due.is_empty():
			due = maxi(due, _due[-1])
		_due.append(due)
		_held.append(item)
