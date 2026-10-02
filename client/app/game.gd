class_name Game
extends Node
## The game's one persistent root, client/app/game.tscn (ARCHITECTURE §4.7, the M4 ADR's E18 to
## E21): the menu's choices, the sessions, the level swap under World, leaving and quitting, and
## why each session ended. It never calls SceneTree.change_scene_to_*, which would free this root
## and the HostNode with it, and there is no autoload.
##
## Hosting: HostNode.host() on an EnetTransport, then the own ClientSession on its own_client.
## Joining: a ClientSession on an EnetTransport. Everything shown comes from the own ClientModel
## and the client's own copy of the mode: the host's player reads nothing of the host's session
## (E18; client/app/ names server/ only through the HostNode façade, a source test holds it).
## The command line after -- (LaunchOptions: --host [--local], --join=, --port=, the runner's stop
## and alive files) skips the menu.
##
## Movement on the network (M4-7): the local PlayerController takes the mode's PlayerRules and
## claims to the session; every snapshot goes into a SnapshotBuffer, from which Avatars draws the
## others and the countdown and the clock read the estimated host tick. A debug build has the
## debug overlay (F3).
##
## Life (M4-9): the own controller follows the own life fold (_sync_life); `Bodies` (BodyViews)
## draws the bodies and `Life` (LifeView) the cameras of the downed and the dead, the countdowns,
## the life inputs and the lift music; the Ui's life panel shows its words in the round.
##
## Items (M4-8): `Items` (ItemWorld) draws the items, the circles and the destination marker, sends
## the item keys and plays the world sounds; the Ui's HUD and task screen show the round.

const MODE_PATH := "res://content/modes/base_mode.tres"
const PLAYER := preload("res://client/player/player.tscn")
const STOP_CHECK_MS := 200

## The client's own copy of the game mode; MODE_PATH unless a test sets one before _ready.
var mode: GameMode
## The arguments after --; OS.get_cmdline_user_args() unless a test sets `read_command_line` off.
var launch_args := PackedStringArray()
var read_command_line := true
## Makes a session's transport: an EnetTransport with the game's kind table unless a test sets
## one (a loopback). Called with no arguments.
var make_transport := Callable()
## The clock in microseconds of the host session and of the avatars' host-tick estimate: the real
## one unless a test sets one. The client session's claims count physics steps (SessionNode).
var clock := Callable()
var options: LaunchOptions
## Why the last session ended; empty before the first ended.
var last_reason: StringName = &""
## Whether the local player reads the keyboard and mouse when a screen lets it. Tests turn it off
## and drive the player's wish fields themselves (headless runs have no input).
var device_input := true
## The mouse pointer the game captures and frees: Input's unless a test sets one (headless keeps no
## mouse mode).
var pointer := MousePointer.new()

var _schema := WireSchema.game(OS.is_debug_build())
var _host: HostNode
var _client: ClientSession
var _session_node: SessionNode
var _buffer: SnapshotBuffer
## Debug builds only (invariant 8): F3 shows it.
var _overlay: DebugOverlay
var _player: PlayerController
var _level: Node
var _level_kind := PhaseSpec.Level.NONE
var _bodies := BodyViews.new()
var _life := LifeView.new()
var _items := ItemWorld.new()
var _ending := false
var _last_stop_check_ms := 0
var _screen := GameFlow.Screen.MENU

@onready var ui: GameUi = $Ui
@onready var _world: Node3D = $World
@onready var _avatars: AvatarViews = $World/Avatars


func _ready() -> void:
	get_tree().auto_accept_quit = false
	if mode == null:
		mode = load(MODE_PATH) as GameMode
	ui.esc.lobby.set_mode(mode)
	ui.menu.host_requested.connect(func(port: int) -> void: host(port))
	ui.menu.join_requested.connect(join)
	ui.menu.quit_requested.connect(quit)
	ui.connecting.cancel_requested.connect(leave)
	ui.esc.lobby.ready_toggled.connect(set_ready)
	ui.esc.lobby.setting_changed.connect(change_setting)
	ui.end.back_requested.connect(return_to_lobby)
	ui.esc.resume_requested.connect(close_esc)
	ui.esc.leave_requested.connect(leave)
	ui.esc.quit_requested.connect(quit)
	_world.add_child(_bodies)
	_world.add_child(_life)
	_world.add_child(_items)
	if OS.is_debug_build():
		_overlay = DebugOverlay.new()
		_overlay.name = "DebugOverlay"
		ui.add_child(_overlay)
	var args := OS.get_cmdline_user_args() if read_command_line else launch_args
	options = LaunchOptions.parse(args, true)
	if not options.problem.is_empty():
		print("session: %s" % options.problem)
		ui.menu.set_reason(options.problem)
	elif options.hosting:
		host(options.port, options.bind)
	elif options.joining:
		join(options.address, options.port)
	else:
		ui.menu.port_box.value = options.port


## The tree outlives this root in tests: give it back the quit it had.
func _exit_tree() -> void:
	get_tree().auto_accept_quit = true


## Hosts a session on `port`, listening on `bind` (every interface unless "127.0.0.1"); false,
## with the reason on the menu, when it could not start.
func host(port: int, bind := LaunchOptions.EVERY_INTERFACE) -> bool:
	if _client != null:
		return false
	var transport := _new_transport()
	var enet := transport as EnetTransport
	if enet != null:
		enet.bind_address = bind
	var node := HostNode.host(transport, mode, port, clock)
	if not node.is_running():
		var why := "; ".join(node.errors)
		node.free()
		print("session: cannot host: %s" % why)
		last_reason = EndReasons.CANNOT_HOST
		_show_menu(EndReasons.CANNOT_HOST, why)
		return false
	if options != null and not options.replay:
		node.skip_replay()
	node.name = "HostNode"
	_host = node
	_host.ended.connect(_on_host_ended)
	add_child(_host)
	_start_client(_host.own_client)
	print("%s %s on %s:%d" % [LaunchOptions.HOSTING, mode.resource_path.get_file(), bind, port])
	return true


## Joins the host at `address`:`port`.
func join(address: String, port: int) -> void:
	if _client != null:
		return
	var transport := _new_transport()
	_start_client(transport)
	ui.connecting.set_address("%s:%d" % [address, port])
	print("session: joining %s:%d" % [address, port])
	if transport.join(address, port) != OK:
		_end_session(ClientSession.CONNECT_FAILED)


func set_ready(on: bool) -> void:
	if _client != null:
		_client.send_intent(Intents.SET_READY, {"ready": on})


## The host changes one setting: a whole number, or the ids of a set (banned task types).
func change_setting(id: StringName, value: Variant) -> void:
	if _client != null:
		_client.send_intent(Intents.CHANGE_SETTINGS, {"settings": {id: value}})


## The host's Back to lobby on the end screen.
func return_to_lobby() -> void:
	if _client != null:
		_client.send_intent(Intents.RETURN_TO_LOBBY)


## Leaves the session: a client tells nobody and goes; the host ends it for everyone.
func leave() -> void:
	if _host != null:
		_end_session(EndReasons.CLOSED)
	elif _client != null:
		_client.leave()


## Ends any session, then the process.
func quit() -> void:
	leave()
	get_tree().quit()


## Esc: the Esc menu over the current screen, the mouse freed; the player stands still under it.
func open_esc() -> void:
	ui.open_esc(hosting(), _welcomed_model())
	pointer.capture(false)


## Esc again, or Resume: the menu closes; in the lobby and the round the mouse is captured again.
func close_esc() -> void:
	ui.close_esc()
	if not GameFlow.frees_pointer(screen()):
		pointer.capture(true)


## The Ready key (`ready`, F, #169): the Ready toggle's SetReady, with the own ready flag flipped.
func toggle_ready() -> void:
	var model := _welcomed_model()
	if model == null:
		return
	var own: ClientModel.Member = model.roster.get(model.own_peer)
	if own != null:
		set_ready(not own.ready)


## The own ClientSession; null without a session.
func client() -> ClientSession:
	return _client


func hosting() -> bool:
	return _host != null


func screen() -> GameFlow.Screen:
	return GameFlow.screen(_session_state(), _client.model if _client != null else null)


func level_kind() -> PhaseSpec.Level:
	return _level_kind


## The level under World; null when none plays.
func level() -> Node:
	return _level


func player() -> PlayerController:
	return _player


func avatars() -> AvatarViews:
	return _avatars


func bodies() -> BodyViews:
	return _bodies


## The cameras, countdowns and inputs of the own player's life.
func life() -> LifeView:
	return _life


## The items, circles, item keys and world sounds (M4-8).
func items() -> ItemWorld:
	return _items


## The debug overlay; null in a release build.
func overlay() -> DebugOverlay:
	return _overlay


func _process(_delta: float) -> void:
	_check_runner()
	var now := screen()
	if now != _screen:
		_screen = now
		# A mouse captured in the round would stay captured on the end screen's button.
		if GameFlow.frees_pointer(now):
			pointer.capture(false)
	ui.show_screen(now)
	ui.reads_device_input = device_input
	if _client != null:
		ui.refresh(_client.model, mode, _avatars.host_tick(), hosting())
		if now == GameFlow.Screen.ROUND:
			ui.life.show_hud(_life.hud(_avatars.host_tick()))
		ui.refresh_round(_client.model, mode, _avatars.host_tick(), _hud_local())
	_refresh_overlay()
	if _player != null:
		# The dead have no body to move: it stands still until its Respawned (M4-9).
		_player.set_physics_process(not GameFlow.frozen(now) and not _player_dead())
		var listening := not GameFlow.frozen(now) and not ui.esc_open()
		_player.reads_device_input = device_input and listening
		_life.reads_device_input = device_input
		_life.listening = listening and now == GameFlow.Screen.ROUND
		_items.interactions.reads_device_input = device_input
		_items.interactions.listening = listening and now == GameFlow.Screen.ROUND
		if not listening:
			# Nothing reads the keys now: W held when Esc opened must not keep walking.
			_player.move_input = Vector2.ZERO
			_player.sprint_held = false
			_player.jump_requested = false


func _input(event: InputEvent) -> void:
	if _overlay != null and event.is_action_pressed(&"debug_overlay"):
		_overlay.visible = not _overlay.visible
		get_viewport().set_input_as_handled()
		return
	if _client == null or not event.is_action_pressed(&"ui_cancel"):
		return
	if ui.esc_open():
		close_esc()
	else:
		open_esc()
	get_viewport().set_input_as_handled()


## The Ready key, while the player walks in the lobby with no Esc menu (gameplay input).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ready") or ui.esc_open():
		return
	if screen() == GameFlow.Screen.LOBBY:
		toggle_ready()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if hosting():
		open_esc()
		ui.esc.ask_quit(screen(), _welcomed_model())
	else:
		quit()


func _player_dead() -> bool:
	return _player.life == ClientModel.Life.DEAD or _player.life == ClientModel.Life.LEFT


## The own ClientModel once welcomed; null before and without a session.
func _welcomed_model() -> ClientModel:
	return _client.model if _client != null and _client.is_welcomed() else null


## What the HUD knows besides the model: the predicted stamina and the crosshair's hint (ItemWorld),
## and whom a dead player watches (LifeView, #168).
func _hud_local() -> HudText.Local:
	var local := _items.hud_local()
	local.watching = _life.target()
	return local


func _session_state() -> GameFlow.Session:
	if _client == null:
		return GameFlow.Session.NONE
	return GameFlow.Session.WELCOMED if _client.is_welcomed() else GameFlow.Session.CONNECTING


func _new_transport() -> NetTransport:
	if make_transport.is_valid():
		return make_transport.call() as NetTransport
	return EnetTransport.new(_schema.kind_table())


func _start_client(transport: NetTransport) -> void:
	_ending = false
	_client = ClientSession.new(transport, mode, _schema)
	_client.welcomed.connect(_on_welcomed)
	_client.corrected.connect(_on_corrected)
	_client.map_loaded.connect(_on_map_loaded)
	_client.event_received.connect(_on_event)
	_client.ended.connect(_end_session)
	_session_node = SessionNode.new(_client)
	_session_node.real_clock = clock
	_session_node.name = "SessionNode"
	add_child(_session_node)
	_buffer = SnapshotBuffer.new()
	_client.snapshot_received.connect(_on_snapshot)
	_client.event_received.connect(_avatars.on_event)
	_avatars.model = _client.model
	_avatars.buffer = _buffer
	_avatars.rules = mode.player_rules
	_avatars.clock = clock
	_bodies.model = _client.model
	_bodies.rules = mode.player_rules
	_life.setup(_client, mode, _avatars)
	_items.setup(_client, mode, _avatars)
	_life.items = _items.items


func _on_welcomed(own_peer: int) -> void:
	var member: ClientModel.Member = _client.model.roster.get(own_peer)
	print("session: welcomed as %s [%d]" % [member.name if member != null else "?", own_peer])
	_sync_level()
	_player = PLAYER.instantiate() as PlayerController
	_player.rules = mode.player_rules
	_player.attach(_client)
	_world.add_child(_player)
	_life.player = _player
	_items.set_player(_player)
	_place(_client.model.spots.get(own_peer, Vector3.ZERO) as Vector3, Vector3.ZERO)


func _on_snapshot(tick: int, avatars: Dictionary) -> void:
	_buffer.add(tick, avatars, _avatars.now_usec())


func _on_corrected(position: Vector3, velocity: Vector3) -> void:
	if _player != null:
		_place(position, velocity)


## Puts the player at `position` through teleport(), so the step-up check measures from there and
## not from where _ready found the body.
func _place(position: Vector3, velocity: Vector3) -> void:
	_player.teleport(Transform3D(_player.global_transform.basis, position))
	_player.velocity = velocity


## The map LoadMatch asked for: instanced now, before the session sends LoadAck.
func _on_map_loaded(_path: String, scene: PackedScene) -> void:
	_set_level(scene.instantiate(), PhaseSpec.Level.MAP)


func _on_event(event_name: StringName, _fields: Dictionary) -> void:
	if event_name == &"PhaseChanged":
		_sync_level()
	_sync_life()


## The own player's body follows its own life fold (M4-9): it crawls while downed (a KnockedDown
## naming it), has no body while dead (Died; the physics step stops in _process, so it neither
## walks nor claims until its Respawned), and walks again once living (Revived, Respawned, a new
## match, the lobby). Only a change switches the body, since switching stops it. A raise naming it
## holds it still (`held`).
func _sync_life() -> void:
	if _player == null:
		return
	var model := _client.model
	var own_life := model.life_of(model.own_peer)
	if _player.life != own_life:
		_player.life = own_life
	_player.held = model.raiser_of(model.own_peer) != 0


## The level of the current phase: the lobby, loaded at once when a lobby phase starts; a map
## phase drops the lobby and waits for map_loaded.
func _sync_level() -> void:
	var wanted := GameFlow.level(_session_state(), _client.model)
	if wanted == _level_kind:
		return
	if wanted == PhaseSpec.Level.LOBBY:
		_set_level((load(mode.lobby_level) as PackedScene).instantiate(), wanted)
	elif wanted == PhaseSpec.Level.NONE or _level_kind == PhaseSpec.Level.LOBBY:
		_clear_level()


func _set_level(node: Node, kind: PhaseSpec.Level) -> void:
	_clear_level()
	_level = node
	_level.name = "Level"
	_world.add_child(_level)
	_world.move_child(_level, 0)
	_level_kind = kind


func _clear_level() -> void:
	if _level != null:
		_world.remove_child(_level)
		_level.queue_free()
	_level = null
	_level_kind = PhaseSpec.Level.NONE


func _on_host_ended(reason: StringName) -> void:
	_end_session(reason)


## Every end comes here: the sessions, the level and the views go, and the menu says why.
func _end_session(reason: StringName) -> void:
	if _ending or _client == null:
		return
	_ending = true
	last_reason = reason
	print("session: ended: %s" % EndReasons.text(reason))
	if _host != null:
		# Leaving the tree closes the session: every client sees host_lost.
		remove_child(_host)
		_host.queue_free()
		_host = null
	if not _client.is_ended():
		_client.leave()
	_session_node.queue_free()
	_session_node = null
	_client = null
	_avatars.model = null
	_avatars.buffer = null
	_buffer = null
	_avatars.clear()
	_life.reset()
	_bodies.model = null
	_bodies.clear()
	_items.reset()
	_clear_level()
	if _player != null:
		_player.queue_free()
		_player = null
	_show_menu(reason)
	_ending = false


## The overlay's numbers, while it shows: the own client's, and on the host the session's counters.
func _refresh_overlay() -> void:
	if _overlay == null or not _overlay.visible:
		return
	var counters: Dictionary[StringName, int] = {}
	if _client == null:
		_overlay.show_numbers(-1, -1, -1, 0.0, counters)
		return
	if _host != null:
		counters = _host.counters()
	_overlay.show_numbers(
		_client.corrections, _client.placements, _avatars.host_tick(), _avatars.delay_ms(), counters
	)


func _show_menu(reason: StringName, detail := "") -> void:
	ui.close_esc()
	var why := EndReasons.words(reason) + (": " + detail if not detail.is_empty() else "")
	ui.menu.set_reason("The last session ended: %s." % why)
	ui.show_screen(GameFlow.Screen.MENU)
	pointer.capture(false)


## The runner's stop file, or its alive file gone stale (a killed runner): quit cleanly.
func _check_runner() -> void:
	if options == null:
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_stop_check_ms < STOP_CHECK_MS:
		return
	_last_stop_check_ms = now_ms
	if options.stop_requested() or options.runner_gone():
		print("session: stopped")
		quit()
