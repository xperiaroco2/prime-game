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

const MODE_PATH := "res://content/modes/base_mode.tres"
const PLAYER := preload("res://client/player/player.tscn")
## The runner starts the local clients once a host printed this (tools/runner/hostjoin.py).
const HOSTING := "session: hosting"
const STOP_CHECK_MS := 200
## The host's own player.
const HOST_PEER := 1

## The client's own copy of the game mode; MODE_PATH unless a test sets one before _ready.
var mode: GameMode
## The arguments after --; OS.get_cmdline_user_args() unless a test sets `read_command_line` off.
var launch_args := PackedStringArray()
var read_command_line := true
## Makes a session's transport: an EnetTransport with the game's kind table unless a test sets
## one (a loopback). Called with no arguments.
var make_transport := Callable()
## The clock in microseconds for both sessions: the real one unless a test sets one.
var clock := Callable()
var options: LaunchOptions
## Why the last session ended; empty before the first ended.
var last_reason: StringName = &""

var _schema := WireSchema.game(OS.is_debug_build())
var _host: HostNode
var _client: ClientSession
var _session_node: SessionNode
var _player: PlayerController
var _level: Node
var _level_kind := PhaseSpec.Level.NONE
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
	ui.lobby.set_mode(mode)
	ui.menu.host_requested.connect(func(port: int) -> void: host(port))
	ui.menu.join_requested.connect(join)
	ui.menu.quit_requested.connect(quit)
	ui.connecting.cancel_requested.connect(leave)
	ui.lobby.ready_toggled.connect(set_ready)
	ui.lobby.setting_changed.connect(change_setting)
	ui.end.back_requested.connect(return_to_lobby)
	ui.esc.resume_requested.connect(ui.close_esc)
	ui.esc.leave_requested.connect(leave)
	ui.esc.quit_requested.connect(quit)
	var args := OS.get_cmdline_user_args() if read_command_line else launch_args
	options = LaunchOptions.parse(args, true)
	if not options.problem.is_empty():
		print("session: %s" % options.problem)
		ui.menu.set_reason(options.problem)
	elif options.hosting:
		host(options.port, options.bind)
	elif options.joining:
		join(options.address, options.port)


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
		_show_menu(EndReasons.CANNOT_HOST, why)
		return false
	if options != null and not options.replay:
		node.skip_replay()
	node.name = "HostNode"
	_host = node
	_host.ended.connect(_on_host_ended)
	add_child(_host)
	_start_client(_host.own_client)
	print("%s %s on %s:%d" % [HOSTING, mode.resource_path.get_file(), bind, port])
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
	ui.open_esc(hosting())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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


func _process(_delta: float) -> void:
	_check_runner()
	var now := screen()
	if now != _screen:
		_screen = now
		# A mouse captured in the round would stay captured on the end screen's button.
		if GameFlow.frees_pointer(now):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_screen(now)
	if _client != null:
		ui.refresh(_client.model, mode, _client.model.snapshot_tick, hosting())
	if _player != null:
		_player.set_physics_process(not GameFlow.frozen(now))
		_player.reads_device_input = not GameFlow.frozen(now) and not ui.esc_open()
		if not _player.reads_device_input:
			# Nothing reads the keys now: W held when Esc opened must not keep walking.
			_player.move_input = Vector2.ZERO
			_player.sprint_held = false
			_player.jump_requested = false


func _input(event: InputEvent) -> void:
	if _client == null or not event.is_action_pressed(&"ui_cancel"):
		return
	if ui.esc_open():
		ui.close_esc()
	else:
		open_esc()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if hosting():
		open_esc()
		ui.esc.ask_quit()
	else:
		quit()


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
	_session_node.name = "SessionNode"
	_session_node.clock = clock
	add_child(_session_node)
	_avatars.model = _client.model


func _on_welcomed(own_peer: int) -> void:
	var member: ClientModel.Member = _client.model.roster.get(own_peer)
	print("session: welcomed as %s [%d]" % [member.name if member != null else "?", own_peer])
	_sync_level()
	_player = PLAYER.instantiate() as PlayerController
	_world.add_child(_player)
	_player.global_position = _client.model.spots.get(own_peer, Vector3.ZERO)


func _on_corrected(position: Vector3, velocity: Vector3) -> void:
	if _player != null:
		_player.global_position = position
		_player.velocity = velocity


## The map LoadMatch asked for: instanced now, before the session sends LoadAck.
func _on_map_loaded(_path: String, scene: PackedScene) -> void:
	_set_level(scene.instantiate(), PhaseSpec.Level.MAP)


func _on_event(event_name: StringName, _fields: Dictionary) -> void:
	if event_name == &"PhaseChanged":
		_sync_level()


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
	_avatars.clear()
	_clear_level()
	if _player != null:
		_player.queue_free()
		_player = null
	_show_menu(reason)
	_ending = false


func _show_menu(reason: StringName, detail := "") -> void:
	ui.close_esc()
	var why := EndReasons.words(reason) + (": " + detail if not detail.is_empty() else "")
	ui.menu.set_reason("The last session ended: %s." % why)
	ui.show_screen(GameFlow.Screen.MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
