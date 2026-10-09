class_name Game
extends Node
## The game's one persistent root, client/app/game.tscn (ARCHITECTURE §4.7, the M4 ADR's E18 to
## E21): the menu's choices, the sessions, the level swap under World, leaving and quitting, and
## why each session ended. It never calls SceneTree.change_scene_to_*, which would free this root
## and the HostNode with it, and there is no autoload.
##
## Hosting: HostNode.host() on an EnetTransport (Direct), or on a WebRtcTransport that opens a room
## with a code at the signalling service (the M6 design §2.3; --signal=lan serves a LanSignalling
## here), then the own ClientSession on its own_client. Joining: a JoinTarget (a code or an
## address) hands over its transport, and the connecting screen shows the step, a code join's code
## and the time since Join; a code join ends early when the service's `found` names another
## version (JoinProgress). A failed join or session shows its failure there (EndReasons'
## failure_state, #494) until Back, Try again (the same join, or the host again) or Join directly;
## the player's own leaving goes straight to the menu, whose fields keep the code and address. The
## lobby shows the room's code to whoever knows it: the host from its transport, a joiner the code
## it typed (the M6 design §3). Everything shown comes from the own ClientModel
## and the client's own copy of the mode: the host's player reads nothing of the host's session
## (E18; client/app/ names server/ only through the HostNode façade, a source test holds it).
## The command line after -- (LaunchOptions: --host [--local] [--code], --join=, --port=,
## --signal=, the runner's stop and alive files) skips the menu.
##
## Movement on the network (M4-7): the local PlayerController takes the mode's PlayerRules and
## claims to the session; every snapshot goes into a SnapshotBuffer, from which Avatars draws the
## others and the countdown and the clock read the estimated host tick. A debug build has the
## debug overlay (F3), with the own connection's kind and round trip (#431), fed by OverlayFeed.
##
## Life (M4-9): the own controller follows the own life fold (_sync_life); `Bodies` (BodyViews)
## draws the bodies and `Life` (LifeView) the cameras of the downed and the dead, the countdowns,
## the life inputs and the lift music; the Ui's life panel shows its words in the round.
##
## Items (M4-8): `Items` (ItemWorld) draws the items, the circles and the destination marker, sends
## the item keys and plays the world sounds; the Ui's HUD and task screen show the round.
##
## Voice (M5-5): AudioBuses makes the Voice, Effects and Music buses at start; `Voices`
## (VoiceViews) plays the voices this client hears on the speakers' avatars through `voice_codec`,
## heard from LifeView's Ears; a debug build's overlay lists them by index of first arrival.
##
## Speaking (M5-6): `VoiceSender` sends the own microphone through the gate into the own session;
## `VoiceControl` applies this window's UserSettings (the microphone, the mode, the threshold,
## RNNoise, the volumes, the "opening" mark) and the Esc menu's Voice tab changes them, as does the
## main menu's Voice page before any session (#301: the meter runs, nothing is sent); the lobby
## hints at the tab until a microphone is picked; F3 shows the own gate, peak, age and encode time.

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
## The end whose failure shows now (Screen.FAILURE); empty while none does.
var failure: StringName = &""
## Whether the local player reads the keyboard and mouse when a screen lets it. Tests turn it off
## and drive the player's wish fields themselves (headless runs have no input).
var device_input := true
## The mouse pointer the game captures and frees: Input's unless a test sets one (headless keeps no
## mouse mode).
var pointer := MousePointer.new()
## The window Alt+Enter turns fullscreen and back: the real one unless a test sets one (headless
## keeps no window mode).
var window := GameWindow.new()
## The voice codec: TwoVoIP's (unavailable without the addon, then no voice plays) unless a test
## sets one before _ready.
var voice_codec: VoiceCodec
## The player's settings on this machine: this window's file (UserSettings.for_this_window()),
## or in memory with `read_command_line` off, unless a test sets one before _ready.
var settings: UserSettings
## The player's controls (#211): the player's file (Controls.for_this_player()), applied to the
## InputMap at the start, or the project's defaults in memory, untouched, with `read_command_line`
## off, unless a test sets one before _ready. The Esc menu's Controls tab changes them.
var controls: Controls
## What the player has seen and done of each task type, for the loading screen's how-to card
## (#254): the player's file under user:// (HowtoProgress.for_this_player()), or in memory with
## `read_command_line` off, unless a test sets one; GameHowto wires the cards to it.
var howto: HowtoProgress

var _schema := WireSchema.game(OS.is_debug_build())
var _host: HostNode
## The host's room while hosting with a code; null otherwise.
var _room: CodeRoom
## What this client joined, and the transport it joins with; null for a host or no session.
var _target: JoinTarget
var _join_transport: NetTransport
## When the join started (Time.get_ticks_msec), for the connecting screen's time since Join.
var _join_started_ms := 0
## Starts the last join or host again the same way: a failure's Try again.
var _retry := Callable()
## This game's content hash, for the version check against `found`.
var _own_content := 0
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
var _voices := VoiceViews.new()
var _sender := VoiceSender.new()
var _voice_control: VoiceControl
## A Voice panel (the Esc menu's tab or the main menu's page) showed last frame: the device list
## is read again when one opens.
var _voice_panel_shown := false
## The keys were typing and the talk key is not yet let go (#488): the microphone stays shut.
var _talk_blocked := false
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
	ui.plates.avatars = _avatars
	ui.plates.hider = _life.hider()
	ui.menu.host_requested.connect(func(port: int) -> void: host(port))
	ui.menu.join_requested.connect(join)
	ui.menu.code_host_requested.connect(func() -> void: host_with_code(ui.menu.port()))
	ui.menu.code_join_requested.connect(join_code)
	ui.menu.quit_requested.connect(quit)
	ui.connecting.cancel_requested.connect(leave)
	ui.connecting.back_requested.connect(back_to_menu)
	ui.connecting.retry_requested.connect(retry)
	ui.connecting.direct_requested.connect(open_direct)
	ui.esc.lobby.ready_toggled.connect(set_ready)
	ui.esc.lobby.setting_changed.connect(change_setting)
	ui.esc.lobby.lobby_name_changed.connect(change_lobby_name)
	ui.esc.lobby.map_changed.connect(change_map)
	ui.esc.resume_requested.connect(close_esc)
	ui.esc.leave_requested.connect(leave)
	ui.esc.quit_requested.connect(quit)
	ui.map_opened.connect(_on_map_opened)
	ui.map_closed.connect(_on_map_closed)
	GameHowto.setup(self)
	_world.add_child(_bodies)
	_world.add_child(_life)
	_world.add_child(_items)
	_ready_settings()
	_ready_voice()
	_ready_controls()
	if OS.is_debug_build():
		_overlay = DebugOverlay.new()
		_overlay.name = "DebugOverlay"
		ui.add_child(_overlay)
	var args := OS.get_cmdline_user_args() if read_command_line else launch_args
	options = LaunchOptions.parse(args, true)
	if not options.problem.is_empty():
		print("session: %s" % options.problem)
		ui.menu.set_reason(options.problem)
	elif options.hosting and options.by_code:
		host_with_code(options.port, options.bind)
	elif options.hosting:
		host(options.port, options.bind)
	elif options.joining:
		_fill_menu(options.target)
		join_target(options.target)
	else:
		ui.menu.port_box.value = options.port


## The tree outlives this root in tests: give it back the quit it had. The microphone closes
## cleanly, which also clears an "opening" mark that has not settled yet.
func _exit_tree() -> void:
	get_tree().auto_accept_quit = true
	_sender.close()


## Hosts a session on `port`, listening on `bind` (every interface unless "127.0.0.1"); false,
## with the reason on the menu, when it could not start.
func host(port: int, bind := LaunchOptions.EVERY_INTERFACE) -> bool:
	if _client != null:
		return false
	_retry = host.bind(port, bind)
	var transport := _new_transport()
	var enet := transport as EnetTransport
	if enet != null:
		enet.bind_address = bind
	return _host_on(transport, port, bind)


## Hosts a session whose room has a code, through the signalling service of the launch options
## (JoinTarget.SERVICE_URL by default); with --signal=lan this game serves it on `port` (TCP),
## listening on `bind`. False, with the reason on the menu, when it could not start.
func host_with_code(port: int, bind := LaunchOptions.EVERY_INTERFACE) -> bool:
	if _client != null:
		return false
	_retry = host_with_code.bind(port, bind)
	var service := options.signal_url if options != null else JoinTarget.SERVICE_URL
	if service.is_empty():
		_cannot_host(
			"no code service is set (--signal=): use Host Direct under Direct (LAN or VPN)"
		)
		return false
	var lan_code := options.room if options != null else ""
	var room := CodeRoom.open(_schema.kind_table(), mode, service, port, bind, lan_code)
	if not room.problem.is_empty():
		_cannot_host(room.problem)
		return false
	_room = room
	if _host_on(room.transport, port, bind):
		return true
	_drop_room()
	return false


func _host_on(transport: NetTransport, port: int, bind: String) -> bool:
	var node := HostNode.host(transport, mode, port, clock)
	if not node.is_running():
		var why := "; ".join(node.errors)
		node.free()
		_cannot_host(why)
		return false
	if options != null and not options.replay:
		node.skip_replay()
	node.name = "HostNode"
	_host = node
	_host.ended.connect(_on_host_ended)
	add_child(_host)
	ui.connecting.show_join("", JoinProgress.Step.CONNECTING)
	_start_client(_host.own_client)
	print("%s %s on %s:%d" % [LaunchOptions.HOSTING, mode.resource_path.get_file(), bind, port])
	return true


## Joins the host at `address` (a host name or address, ":port" allowed), on `port` otherwise.
func join(address: String, port: int) -> void:
	join_target(JoinTarget.of_direct(address, port))


## Joins the room with the code the player typed.
func join_code(code: String) -> void:
	var service := options.signal_url if options != null else JoinTarget.SERVICE_URL
	join_target(JoinTarget.of_code(code, service))


## Joins `target`; a problem with what was typed stays on the menu.
func join_target(target: JoinTarget) -> void:
	if _client != null:
		return
	if not target.problem.is_empty():
		ui.menu.set_reason(target.problem)
		return
	_retry = join_target.bind(target)
	_own_content = ClientSession.content_of(mode)
	var transport := (
		_new_transport()
		if make_transport.is_valid()
		else target.transport(_schema.kind_table(), WireSchema.VERSION, _own_content)
	)
	_start_client(transport)
	_target = target
	_join_transport = transport
	_join_started_ms = Time.get_ticks_msec()
	ui.connecting.show_join(
		target.code if target.is_code() else "", JoinProgress.step(target.is_code(), -1, false)
	)
	print("session: joining %s" % target.label())
	if transport.join(target.join_address(), target.port) != OK:
		_end_session(
			(
				NetTransport.JOIN_SERVICE_UNREACHABLE
				if target.is_code()
				else ClientSession.CONNECT_FAILED
			)
		)


func set_ready(on: bool) -> void:
	if _client != null:
		_client.send_intent(Intents.SET_READY, {"ready": on})


## The host changes one setting: a whole number, or the ids of a set (banned task types).
func change_setting(id: StringName, value: Variant) -> void:
	if _client != null:
		_client.send_intent(Intents.CHANGE_SETTINGS, {"settings": {id: value}})


## The host names the lobby (#214): "" asks for the default again. Cleaned as the host will, so a
## pasted invisible character never makes the send fail.
func change_lobby_name(text: String) -> void:
	if _client != null:
		_client.send_intent(
			Intents.CHANGE_SETTINGS, {"settings": {}, "lobby_name": LobbyName.clean(text)}
		)


## The host picks the match's map: one of the mode's maps, which the host checks (#627).
func change_map(map: String) -> void:
	if _client != null:
		_client.send_intent(Intents.CHANGE_SETTINGS, {"settings": {}, "map": map})


## The host's ReturnToLobby: everyone back in the lobby before End's own return. No screen offers it
## since #212 (End returns by itself); the tests use it.
func return_to_lobby() -> void:
	if _client != null:
		_client.send_intent(Intents.RETURN_TO_LOBBY)


## Leaves the session: a client tells nobody and goes; the host ends it for everyone.
func leave() -> void:
	if _host != null:
		_end_session(EndReasons.CLOSED)
	elif _client != null:
		_client.leave()


## A failure's Back (or Esc): the main menu, its fields as they were (the code or address kept).
func back_to_menu() -> void:
	failure = &""
	ui.show_screen(screen())


## A failure's Try again: the last join to the same target, or the host started again the same
## way (host-failed).
func retry() -> void:
	var again := _retry
	back_to_menu()
	if again.is_valid():
		again.call()


## A failure's Join directly: the main menu's Direct fields, the code kept in its own. #493's Toy
## menu opens its Direct panel here.
func open_direct() -> void:
	back_to_menu()
	ui.menu.address_edit.grab_focus()


## Ends any session, then the process.
func quit() -> void:
	leave()
	get_tree().quit()


## Esc: the Esc menu over the current screen, the mouse freed; the player stands still under it.
## The menu takes the live screen(), not the one _process drew last (#204).
func open_esc() -> void:
	ui.open_esc(hosting(), _welcomed_model(), screen())
	pointer.capture(false)


## Esc again with no question open on it (its Resume), or Resume: the menu closes; in the lobby,
## Loading and the round the mouse is captured again.
func close_esc() -> void:
	ui.close_esc()
	if GameFlow.pointer_on(screen()) != GameFlow.Pointer.FREE:
		pointer.capture(true)


## The map opened (#253): the mouse is free for its «?»; the player keeps walking.
func _on_map_opened() -> void:
	pointer.capture(false)
	_apply_player_flags(screen())


## The map closed by its key or Esc: the round's mouse is captured again, as after the Esc menu.
## Not under the Esc menu (it closes the map as it opens), not off the round (the next screen's
## mouse is _point_for's), and only while the window has the focus.
func _on_map_closed() -> void:
	if screen() == GameFlow.Screen.ROUND and not ui.esc_open() and pointer.focused():
		pointer.capture(true)
	_apply_player_flags(screen())


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


## The host's room with a code; null without one.
func room() -> CodeRoom:
	return _room


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


## The voices this client plays (M5-5).
func voices() -> VoiceViews:
	return _voices


## The own voice's sender (M5-6).
func sender() -> VoiceSender:
	return _sender


## The voice settings applied (M5-6).
func voice_control() -> VoiceControl:
	return _voice_control


func _process(_delta: float) -> void:
	_check_runner()
	if _room != null:
		_room.poll()
	var now := screen()
	if now != _screen:
		_screen = now
		_point_for(now)
	ui.show_screen(now)
	if _client != null:
		_refresh_join()
		ui.refresh(_client.model, mode, _avatars.host_tick(), hosting())
		if now == GameFlow.Screen.LOADING:
			ui.connecting.set_load_fraction(_client.load_progress())
		if now == GameFlow.Screen.ROUND:
			ui.life.show_hud(_life.hud(_avatars.host_tick()))
		GameHowto.follow(self, now)
		var tick := _avatars.host_tick()
		ui.refresh_round(_client.model, mode, tick, _hud_local(tick))
	OverlayFeed.refresh(_overlay, _client, _host, _avatars, _sender, _voices)
	_refresh_voice()
	_apply_player_flags(now)


func _input(event: InputEvent) -> void:
	# Alt+Enter on every screen, before Enter reaches a focused button (#517).
	if event.is_action_pressed(&"toggle_fullscreen"):
		window.toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if _overlay != null and event.is_action_pressed(&"debug_overlay"):
		_overlay.visible = not _overlay.visible
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	# Esc on the connecting screen is its Cancel, on a failure its Back (#494).
	var now := screen()
	if now == GameFlow.Screen.FAILURE or now == GameFlow.Screen.CONNECTING:
		if now == GameFlow.Screen.FAILURE:
			back_to_menu()
		else:
			leave()
		get_viewport().set_input_as_handled()
		return
	# Then the open overlay on top, only that one (#488 rule 2): a card, the map, the host's
	# question, the Esc menu (its Resume), the main menu's Voice page (#301). A key capture in
	# Settings > Controls took its Esc in its own _input already.
	if ui.overlays.close_top() != &"":
		get_viewport().set_input_as_handled()
		return
	# None open: the Esc menu, over a session only.
	if _client == null:
		return
	open_esc()
	get_viewport().set_input_as_handled()


## The Ready key, while the player walks in the lobby, and the map key (#253), which opens and
## closes the map in the round on any life, or closes a card over it (#488); neither under the Esc
## menu (gameplay input).
func _unhandled_input(event: InputEvent) -> void:
	if ui.esc_open():
		return
	if event.is_action_pressed(&"ready") and screen() == GameFlow.Screen.LOBBY:
		toggle_ready()
		get_viewport().set_input_as_handled()
	elif (
		device_input
		and event.is_action_pressed(&"map")
		and screen() == GameFlow.Screen.ROUND
		and _client != null
		and ui.press_map_key()
	):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if hosting():
		open_esc()
		ui.esc.ask_quit(screen(), _welcomed_model())
	else:
		quit()


## The local player's physics step and input flags for `now`: it steps only on a screen that is not
## frozen and while it has a body (the dead stand still until their Respawned, M4-9), and the keys
## count only there with no Esc menu. Game._process applies them every frame (the Esc menu), and
## _on_event as soon as the session folds an event in its physics step (#241): under load several
## physics steps run before the next _process, and the player must neither step nor claim after
## the phase turns frozen (Loading, Pregame, End), nor wait for _process to walk again.
func _apply_player_flags(now: GameFlow.Screen) -> void:
	if _player == null:
		return
	_player.set_physics_process(not GameFlow.frozen(now) and not _player_dead())
	var listening := not GameFlow.frozen(now) and not ui.esc_open()
	_player.reads_device_input = device_input and listening
	# The map frees the mouse for its «?» while the player still walks, jumps, picks up and talks
	# (the designer's answer on #253): the controller only stops looking and recapturing.
	_player.mouse_free = ui.map_is_open()
	_life.reads_device_input = device_input
	_life.listening = listening and now == GameFlow.Screen.ROUND
	_items.interactions.reads_device_input = device_input
	_items.interactions.listening = listening and now == GameFlow.Screen.ROUND
	if not listening:
		# Nothing reads the keys now: W held when Esc opened must not keep walking.
		_player.move_input = Vector2.ZERO
		_player.sprint_held = false
		_player.jump_requested = false


## The mouse for the screen just shown (GameFlow.pointer_on): a mouse captured in the round would
## stay captured on the end screen's button; the lobby and the round capture it (#517), but never
## from under the Esc menu, and only while the window has the focus (MousePointer.focused): a
## window in the background a click captures later.
func _point_for(now: GameFlow.Screen) -> void:
	match GameFlow.pointer_on(now):
		GameFlow.Pointer.FREE:
			pointer.capture(false)
		GameFlow.Pointer.CAPTURE:
			if not ui.esc_open() and pointer.focused():
				pointer.capture(true)


func _player_dead() -> bool:
	return _player.life == ClientModel.Life.DEAD or _player.life == ClientModel.Life.LEFT


## The own ClientModel once welcomed; null before and without a session.
func _welcomed_model() -> ClientModel:
	return _client.model if _client != null and _client.is_welcomed() else null


## What the HUD knows besides the model: the predicted stamina and the item under the crosshair
## (ItemWorld), whom a dead player watches (LifeView, #168), the own raise's progress at the
## estimated host tick `tick` and whether anyone may hear the own player (#489).
func _hud_local(tick: float) -> HudText.Local:
	var local := _items.hud_local()
	local.watching = _life.target()
	local.raising = _life.raise_shown(tick)
	local.mic = _sender.live()
	if _player != null and not _player_dead():
		local.placed = true
		local.position = _player.global_position
		var look := _player.look_vector()
		local.heading = atan2(look.x, -look.z)
	return local


func _session_state() -> GameFlow.Session:
	if _client == null:
		return GameFlow.Session.NONE if failure.is_empty() else GameFlow.Session.FAILED
	return GameFlow.Session.WELCOMED if _client.is_welcomed() else GameFlow.Session.CONNECTING


func _new_transport() -> NetTransport:
	if make_transport.is_valid():
		return make_transport.call() as NetTransport
	return EnetTransport.new(_schema.kind_table())


func _start_client(transport: NetTransport) -> void:
	_ending = false
	failure = &""
	_client = ClientSession.new(transport, mode, _schema, settings.player_name)
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
	_setup_voice()


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
	ui.set_map_data(MapData.from_level(_level, mode))


## Every event, in the session's physics step: the level of a new phase, the own life, and the
## player's flags for the screen the model is on now (a phase, the winner and the own death all
## change them, #241).
func _on_event(event_name: StringName, _fields: Dictionary) -> void:
	if event_name == &"PhaseChanged":
		_sync_level()
	_sync_life()
	_apply_player_flags(screen())


## The own player's body follows its own life fold (M4-9): it crawls while downed (a KnockedDown
## naming it), has no body while dead (Died; _apply_player_flags stops the physics step, so it
## neither walks nor claims until its Respawned), and walks again once living (Revived, Respawned,
## a new match, the lobby). Only a change switches the body, since switching stops it. A raise
## naming it holds it still (`held`).
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
	ui.set_map_data(MapData.new())


func _on_host_ended(reason: StringName) -> void:
	_end_session(reason)


## Every end comes here: the sessions, the level and the views go, and the menu says why (with
## `detail` after the reason's words); a failure shows on the connecting screen first.
func _end_session(reason: StringName, detail := "") -> void:
	if _ending or _client == null:
		return
	_ending = true
	last_reason = reason
	if detail.is_empty():
		detail = _found_detail(reason)
	var versions := _found_versions(reason)
	print("session: ended: %s%s" % [EndReasons.text(reason), ": " + detail if detail else ""])
	if _host != null:
		# Leaving the tree closes the session: every client sees host_lost.
		remove_child(_host)
		_host.queue_free()
		_host = null
	if not _client.is_ended():
		_client.leave()
	_drop_room()
	_target = null
	_join_transport = null
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
	_voices.reset()
	_sender.reset()
	_clear_level()
	if _player != null:
		_player.queue_free()
		_player = null
	_show_end(reason, detail, versions)
	_ending = false


## Both versions in words when a code join ended on the service's `found` (the transport's
## version check, before any ICE); "" for any other end, a Rejected Hello's included.
func _found_detail(reason: StringName) -> String:
	var webrtc := _join_transport as WebRtcTransport
	if webrtc == null:
		return ""
	var found := webrtc.found_protocol
	var own := WireSchema.VERSION
	if JoinProgress.found_mismatch(found, webrtc.found_content, own, _own_content) != reason:
		return ""
	return JoinProgress.found_detail(reason, found, webrtc.found_content, own, _own_content)


## The host's and this game's version for the connecting screen's failure, when a code join ended
## on the service's `found`; empty otherwise (a Rejected Hello names no version).
func _found_versions(reason: StringName) -> PackedStringArray:
	var webrtc := _join_transport as WebRtcTransport
	if webrtc == null:
		return PackedStringArray()
	return JoinProgress.found_versions(
		reason, webrtc.found_protocol, webrtc.found_content, WireSchema.VERSION, _own_content
	)


## A join under way: the connecting screen's step and the time since Join. Then the room's code to
## whoever knows it: the host from its room (waiting for the service, then the code, or a line
## saying none is coming), a code joiner the code it typed, a Direct joiner none. Once welcomed,
## the title names the lobby (#214: the host's answer carries its name).
func _refresh_join() -> void:
	var webrtc := _join_transport as WebRtcTransport
	if _client.is_welcomed():
		ui.connecting.set_lobby(_client.model.lobby_name, _client.model.host_name())
	if _target != null and not _client.is_welcomed():
		var found := webrtc.found_protocol if webrtc != null else -1
		var connected := _join_transport.own_id() != 0
		ui.connecting.set_step(JoinProgress.step(_target.is_code(), found, connected))
		ui.connecting.set_elapsed(floori((Time.get_ticks_msec() - _join_started_ms) / 1000.0))
	var code := ""
	if _room != null:
		code = _room.code()
	elif _target != null and _target.is_code():
		code = _target.code
	var line := JoinProgress.code_text(code, _room != null and _room.gone(), _room != null)
	ui.lobby_hud.show_code(line)
	ui.esc.lobby.show_code(line, code)


## This window's settings, and their interface language applied (#208): the player's choice, or
## on a first launch the system's when it is Ukrainian and English otherwise. A Game with no command
## line (a test, a playcheck window) ignores the machine's language: it speaks English unless its
## settings say otherwise, so a run reads the same on every machine.
func _ready_settings() -> void:
	if settings == null:
		# A Game with no command line (a test, a playcheck window) keeps its settings in memory: the
		# player's file in user:// would set the process's buses and take an opening mark.
		settings = UserSettings.for_this_window() if read_command_line else UserSettings.new()
	Languages.apply(settings, OS.get_locale_language() if read_command_line else Languages.ENGLISH)


## The buses (D15), the voices' node under World, and the own voice: the sender, this window's
## settings applied, and both Voice panels (the Esc menu's tab, the main menu's page, #301) wired
## to them.
func _ready_voice() -> void:
	AudioBuses.ensure()
	if voice_codec == null:
		voice_codec = TwoVoipCodec.new()
	_world.add_child(_voices)
	_sender.codec = voice_codec
	add_child(_sender)
	_voice_control = VoiceControl.new(settings, _sender)
	for panel: VoicePanel in [ui.esc.voice, ui.menu.voice]:
		panel.device_picked.connect(_voice_control.pick_device)
		panel.mode_picked.connect(_voice_control.set_mode)
		panel.threshold_changed.connect(_voice_control.set_threshold)
		panel.denoise_toggled.connect(_voice_control.set_denoise)
		panel.volume_changed.connect(_voice_control.set_volume)
		panel.tone_toggled.connect(_voice_control.set_tone)
		panel.mute_toggled.connect(_voice_control.set_muted)
	_voice_control.start()


## The player's controls applied (a test's or a playcheck window's stay the project's: the player's
## file in user:// would rebind the process's keys), and the Controls tab wired to them.
func _ready_controls() -> void:
	if controls == null:
		controls = Controls.for_this_player() if read_command_line else Controls.new()
		if read_command_line:
			controls.apply()
	ui.esc.controls.setup(controls)


## The voices follow the new session's ClientSession, model and avatars; the own voice speaks
## into it.
func _setup_voice() -> void:
	_voices.setup(_client, mode, _avatars, voice_codec)
	_sender.setup(_client, mode)


## Each frame: the talk key counts, under the Esc menu too (#488 rule 4), but never while the
## keys are typing, nor after it, until the talk key has been let go once (a V that ended a typing
## or bound a key is still held, and must not key the microphone); an open Voice panel (the Esc
## menu's tab, or the main menu's page with no session, #301) shows the settings and the
## microphone's level (the device list read again as it opens); the lobby's hint.
func _refresh_voice() -> void:
	_sender.reads_device_input = device_input
	var typing := _typing()
	if typing:
		_talk_blocked = true
	elif not Input.is_action_pressed(VoiceSender.TALK_ACTION):
		_talk_blocked = false
	_sender.listening = not typing and not _talk_blocked
	var panel := shown_voice_panel()
	if panel != null and not _voice_panel_shown:
		_voice_control.refresh_devices()
	_voice_panel_shown = panel != null
	if panel != null:
		panel.show_facts(_voice_control.facts())
	ui.lobby_hud.show_voice_hint(_voice_control.lobby_hint())


## A text field has the focus (the Lobby tab's name, #214) or Settings > Controls captures a key:
## the keys are letters or a binding then, and V must not key the microphone.
func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or ui.esc.controls.is_capturing()


## The Voice panel on screen now: the Esc menu's Voice tab, the main menu's Voice page, or null.
func shown_voice_panel() -> VoicePanel:
	if ui.esc_open():
		return ui.esc.voice if ui.esc.state.selected == EscMenuState.Tab.VOICE else null
	if ui.screen == GameFlow.Screen.MENU and ui.menu.voice_open():
		return ui.menu.voice
	return null


func _cannot_host(why: String) -> void:
	print("session: cannot host: %s" % why)
	last_reason = EndReasons.CANNOT_HOST
	_show_end(EndReasons.CANNOT_HOST, why)


## The code host's room and its own signalling go with its session.
func _drop_room() -> void:
	if _room != null:
		_room.stop()
	_room = null


## After an end: the menu's line says why, and the end's failure, if it has one, shows first.
func _show_end(reason: StringName, detail := "", versions := PackedStringArray()) -> void:
	ui.close_esc()
	ui.menu.close_voice()
	var why := EndReasons.words(reason) + (": " + detail if not detail.is_empty() else "")
	ui.menu.set_reason("The last session ended: %s." % why)
	var shown := ui.connecting.show_failure(EndReasons.failure_state(reason), versions)
	failure = reason if shown else &""
	ui.show_screen(screen())
	pointer.capture(false)


## The menu's field of a join from the command line, so Back finds it there as if typed.
func _fill_menu(target: JoinTarget) -> void:
	if target.is_code():
		ui.menu.code_edit.text = target.code
	elif target.problem.is_empty():
		ui.menu.address_edit.text = target.address
		ui.menu.port_box.value = target.port


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
