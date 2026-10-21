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
## the player's own leaving goes straight to the menu, whose panels keep the code and address. The
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
## Life (M4-9): the own controller follows the own life fold (GamePlayer.sync_life); `Bodies`
## (BodyViews) draws the bodies and `Life` (LifeView) the cameras of the downed and the dead, the
## countdowns, the life inputs and the lift music; the Ui's LifeScreen draws its state in the round.
##
## Wiring out of this file (lint's 1000 lines): GameSettings (the settings, the own voice, the
## controls and both Settings pages), GamePlayer (the local player's flags, mouse, life and HUD
## facts), GameJoin (the join under way), GameLevel (the level swap), GameTalk, GameHowto.
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
## main menu's Settings panel before any session (#301: the meter runs, nothing is sent); the lobby
## hints at the tab until a microphone is picked; F3 shows the own gate, peak, age and encode time.

const MODE_PATH := "res://content/modes/base_mode.tres"
const PLAYER := preload("res://client/player/player.tscn")
const STOP_CHECK_MS := 200

## The client's own copy of the game mode; MODE_PATH unless a test sets one before _ready, and the
## tutorial's while one runs (GameTutorial).
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
## Whether the avatars wear the animated character (CharacterSet.load_default(), #522): tests turn
## it off, so a run with the LFS art and one without (CI) draw the same greybox capsules.
var load_character := true
var options: LaunchOptions
## Why the last session ended; empty before the first ended.
var last_reason: StringName = &""
## The last end's words with their detail, or what was wrong with a target typed or given on the
## command line, as the console prints them; no screen draws them since #493 (a failure shows on
## the connecting screen, and the menu's fields admit no unparsed target).
var last_words := ""
## The end whose failure shows now (Screen.FAILURE); empty while none does.
var failure: StringName = &""
## Whether the local player reads the keyboard and mouse when a screen lets it. Tests turn it off
## and drive the player's wish fields themselves (headless runs have no input).
var device_input := true
## The mouse pointer the game captures and frees: Input's, or a test's (headless keeps no mode).
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
## The solo tutorial session (#601): Game.start_tutorial, the first launch's own start.
var tutorial := GameTutorial.new()

var _schema := WireSchema.game(OS.is_debug_build())
var _host: HostNode
## The host's room while hosting with a code; null otherwise.
var _room: CodeRoom
## Starts the last join or host again the same way: a failure's Try again.
var _retry := Callable()
## The join under way: its target, transport, start and content hash (GameJoin).
var _join := GameJoin.new()
## The character the avatars wear (null: the greybox capsules), loaded once, at the first session.
var _character: CharacterSet
var _character_loaded := false
var _client: ClientSession
var _session_node: SessionNode
var _buffer: SnapshotBuffer
## Debug builds only (invariant 8): F3 shows it.
var _overlay: DebugOverlay
var _player: PlayerController
## The level under World and its kind (GameLevel).
var _levels := GameLevel.new()
var _bodies := BodyViews.new()
var _life := LifeView.new()
var _items := ItemWorld.new()
var _voices := VoiceViews.new()
var _sender := VoiceSender.new()
var _voice_control: VoiceControl
## The per-frame voice wiring: the talk key and the Voice panel on screen (GameTalk).
var _talk := GameTalk.new()
var _ending := false
var _last_stop_check_ms := 0
var _quitting := false
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
	ui.menu.code_host_requested.connect(func() -> void: host_with_code(ui.menu.default_port))
	ui.menu.code_join_requested.connect(join_code)
	ui.menu.quit_requested.connect(quit)
	ui.connecting.cancel_requested.connect(leave)
	ui.connecting.back_requested.connect(back_to_menu)
	ui.connecting.retry_requested.connect(retry)
	ui.connecting.direct_requested.connect(open_direct)
	ui.esc.lobby.ready_toggled.connect(set_ready)
	ui.esc.lobby.setting_changed.connect(change_setting)
	ui.esc.lobby.settings_changed.connect(change_settings)
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
	_levels.setup(_world, _items, ui)
	# The left button's use and shot need the mouse captured, as the game's pointer has it (#1114).
	_items.interactions.mouse_captured = func() -> bool: return pointer.captured()
	_life.mouse_captured = func() -> bool: return pointer.captured()
	GameSettings.ready_settings(self)
	ui.menu.bind_name(settings)
	_voice_control = GameSettings.start_voice(self, _world)
	GameSettings.ready_controls(self)
	if OS.is_debug_build():
		_overlay = DebugOverlay.new()
		_overlay.name = "DebugOverlay"
		ui.above.add_child(_overlay)
	var args := OS.get_cmdline_user_args() if read_command_line else launch_args
	options = LaunchOptions.parse(args, true)
	ui.menu.set_default_port(options.port)
	if not options.problem.is_empty():
		print("session: %s" % options.problem)
		last_words = options.problem
		if options.joining and options.target != null:
			GameJoin.fill_menu(self, options.target, options.address)
	elif options.hosting and options.by_code:
		host_with_code(options.port, options.bind)
	elif options.hosting:
		host(options.port, options.bind)
	elif options.joining:
		GameJoin.fill_menu(self, options.target)
		join_target(options.target)
	tutorial.setup(self)


## The tree outlives this root in tests: give it back the quit it had. The microphone closes
## cleanly, which also clears an "opening" mark that has not settled yet.
func _exit_tree() -> void:
	get_tree().auto_accept_quit = true
	_sender.close()


## Hosts a session on `port`, listening on `bind` (every interface unless "127.0.0.1"); false,
## with host-failed shown (its reason in last_words), when it could not start.
func host(port: int, bind := LaunchOptions.EVERY_INTERFACE) -> bool:
	if _client != null:
		return false
	_retry = host.bind(port, bind)
	var transport := _new_transport()
	var enet := transport as EnetTransport
	if enet != null:
		enet.bind_address = bind
	return host_on(transport, port, bind)


## Hosts a session whose room has a code, through the signalling service of the launch options
## (JoinTarget.SERVICE_URL by default); with --signal=lan this game serves it on `port` (TCP),
## listening on `bind`. False, with host-failed shown (its reason in last_words), when it could
## not start.
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
	if host_on(room.transport, port, bind):
		return true
	_drop_room()
	return false


## Hosts on `transport` (a socket's, a code room's or the tutorial's private hub) and joins it.
func host_on(transport: NetTransport, port: int, bind: String) -> bool:
	var node := HostNode.host(transport, mode, port, clock)
	if not node.is_running():
		var why := "; ".join(node.errors)
		node.free()
		_cannot_host(why)
		return false
	if tutorial.running or (options != null and not options.replay):
		node.skip_replay()
	node.name = "HostNode"
	_host = node
	_host.ended.connect(_on_host_ended)
	add_child(_host)
	ui.connecting.show_join("", JoinProgress.Step.CONNECTING)
	_start_client(_host.own_client)
	print("%s %s on %s:%d" % [LaunchOptions.HOSTING, mode.resource_path.get_file(), bind, port])
	return true


## The solo tutorial (GameTutorial, #601), its invite on a first launch; false while a session runs
## or when it could not start, and then Try again starts it again.
func start_tutorial(invite := false) -> bool:
	if _client == null:
		_retry = start_tutorial.bind(false)
	return tutorial.start(self, invite)


## Joins the host at `address` (a host name or address, ":port" allowed), on `port` otherwise.
func join(address: String, port: int) -> void:
	join_target(JoinTarget.of_direct(address, port))


## Joins the room with the code the player typed.
func join_code(code: String) -> void:
	var service := options.signal_url if options != null else JoinTarget.SERVICE_URL
	join_target(JoinTarget.of_code(code, service))


## Joins `target`; a problem with it is printed and kept in last_words, and no screen shows it:
## the menu's fields admit none (Join stays off), and a --join= that does not parse waits in the
## Direct field (_fill_menu).
func join_target(target: JoinTarget) -> void:
	if _client != null:
		return
	if not target.problem.is_empty():
		print("session: %s" % target.problem)
		last_words = target.problem
		return
	GameJoin.remember(self, target)
	_retry = join_target.bind(target)
	_join.own_content = ClientSession.content_of(mode)
	var transport := (
		_new_transport()
		if make_transport.is_valid()
		else target.transport(_schema.kind_table(), WireSchema.VERSION, _join.own_content)
	)
	_start_client(transport, settings.return_key(target.return_target()))
	_join.target = target
	_join.transport = transport
	_join.started_ms = Time.get_ticks_msec()
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
	change_settings({id: value})


## The host changes several settings in one ChangeSettings (a preset card, #491): the host checks
## them together, so it never refuses a preset half-applied.
func change_settings(values: Dictionary) -> void:
	if _client != null:
		_client.send_intent(Intents.CHANGE_SETTINGS, {"settings": values})


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


## A failure's Join directly: the main menu's Direct panel, the address focused, the code kept in
## its own field (#493).
func open_direct() -> void:
	back_to_menu()
	ui.menu.open_direct()


## Ends any session, then the process once every sound has stopped (SoundStopper, #891).
func quit() -> void:
	if not _quitting:
		_quitting = true
		await SoundStopper.quit(get_tree(), leave)


## Esc: the Esc menu over the current screen, the mouse freed; the player stands still under it.
## The menu takes the live screen(), not the one _process drew last (#204).
func open_esc() -> void:
	ui.open_esc(hosting(), _welcomed_model(), screen())
	pointer.capture(false)
	tutorial.esc_opened()


## Esc again with no question open on it (its Resume), or Resume: the menu closes; in the lobby,
## Loading and the round the mouse is captured again.
func close_esc() -> void:
	ui.close_esc()
	if GameFlow.pointer_on(screen()) != GameFlow.Pointer.FREE:
		pointer.capture(true)
	# Last: after lesson 8 the tutorial leaves here (D32 (b)).
	tutorial.esc_closed()


## The map opened (#253): the mouse is free for its «?»; the player keeps walking.
func _on_map_opened() -> void:
	pointer.capture(false)
	GamePlayer.apply_flags(self, screen())


## The map closed by its key or Esc: the round's mouse is captured again, as after the Esc menu.
## Not under the Esc menu (it closes the map as it opens), not off the round (the next screen's
## mouse is _point_for's), and only while the window has the focus.
func _on_map_closed() -> void:
	if screen() == GameFlow.Screen.ROUND and not ui.esc_open() and pointer.focused():
		pointer.capture(true)
	GamePlayer.apply_flags(self, screen())


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


## A networked host: the solo tutorial hosts for nobody else (no question on Leave, #601).
func hosting() -> bool:
	return _host != null and not tutorial.running


func screen() -> GameFlow.Screen:
	return GameFlow.screen(_session_state(), _client.model if _client != null else null)


func level_kind() -> PhaseSpec.Level:
	return _levels.kind


## The level under World; null when none plays.
func level() -> Node:
	return _levels.node


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


func _process(delta: float) -> void:
	_check_runner()
	if _room != null:
		_room.poll()
	var now := screen()
	if now != _screen:
		_screen = now
		# A new screen closes the Esc menu opened over another, its question too (#726).
		GamePlayer.point_for(self, now, ui.close_esc_left(now))
	ui.show_screen(now)
	if _client != null:
		_join.refresh(self)
		ui.refresh(_client.model, mode, _avatars.host_tick(), hosting())
		if now == GameFlow.Screen.LOADING:
			ui.connecting.set_load_fraction(_client.load_progress())
		if now == GameFlow.Screen.ROUND:
			ui.life.show_hud(_life.hud(_avatars.host_tick()))
		GameHowto.follow(self, now)
		var tick := _avatars.host_tick()
		ui.refresh_round(_client.model, mode, tick, GamePlayer.hud_local(self, tick))
	OverlayFeed.refresh(_overlay, _client, _host, _avatars, _sender, _voices)
	_talk.refresh(self)
	GamePlayer.apply_flags(self, now)
	tutorial.process(self, delta)


func _input(event: InputEvent) -> void:
	# Alt+Enter on every screen, before Enter reaches a focused button (#517).
	if event.is_action_pressed(&"toggle_fullscreen"):
		GameSettings.toggle_window(self)
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
	# question, the Esc menu (its Resume), the main menu's open panel (#493). A key capture in
	# Settings > Controls took its Esc in its own _input already. Then the photo camera's
	# viewfinder, which closes before the Esc menu opens (#786).
	if ui.overlays.close_top() != &"" or _items.viewfinder.leave():
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


## The own ClientModel once welcomed; null before and without a session.
func _welcomed_model() -> ClientModel:
	return _client.model if _client != null and _client.is_welcomed() else null


func _session_state() -> GameFlow.Session:
	if _client == null:
		return GameFlow.Session.NONE if failure.is_empty() else GameFlow.Session.FAILED
	return GameFlow.Session.WELCOMED if _client.is_welcomed() else GameFlow.Session.CONNECTING


func _new_transport() -> NetTransport:
	if make_transport.is_valid():
		return make_transport.call() as NetTransport
	return EnetTransport.new(_schema.kind_table())


## Starts the session over `transport`, its Hello sending `key` (#638): the return key of a join's
## target; none (the host's own client) makes ClientSession a random one of this session alone.
func _start_client(transport: NetTransport, key := "") -> void:
	_ending = false
	failure = &""
	_client = ClientSession.new(transport, mode, _schema, settings.player_name, key)
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
	_avatars.mode = mode
	_avatars.character = _character_set()
	_bodies.setup(_client.model, mode.player_rules, _avatars)
	_bodies.character = _avatars.character
	_life.setup(_client, mode, _avatars)
	_items.setup(_client, mode, _avatars)
	_life.items = _items.items
	_life.view_camera = _items.viewfinder.live_camera
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
	GamePlayer.place(
		_player, _client.model.spots.get(own_peer, Vector3.ZERO) as Vector3, Vector3.ZERO
	)


func _on_snapshot(tick: int, avatars: Dictionary) -> void:
	_buffer.add(tick, avatars, _avatars.now_usec())


func _on_corrected(position: Vector3, velocity: Vector3) -> void:
	if _player != null:
		GamePlayer.place(_player, position, velocity)


## The map LoadMatch asked for: instanced now, before the session sends LoadAck.
func _on_map_loaded(_path: String, scene: PackedScene) -> void:
	_levels.swap(scene.instantiate(), PhaseSpec.Level.MAP)
	ui.set_map_data(MapData.from_level(_levels.node, mode))


## Every event, in the session's physics step: the level of a new phase, the own life, and the
## player's flags for the screen the model is on now (a phase, the winner and the own death all
## change them, #241).
func _on_event(event_name: StringName, _fields: Dictionary) -> void:
	if event_name == &"PhaseChanged":
		_sync_level()
	GamePlayer.sync_life(self)
	GamePlayer.apply_flags(self, screen())


## The level of the current phase (GameLevel.sync): the lobby, loaded at once when a lobby phase
## starts; a map phase drops the lobby and waits for map_loaded.
func _sync_level() -> void:
	_levels.sync(GameFlow.level(_session_state(), _client.model), mode.lobby_level)


func _on_host_ended(reason: StringName) -> void:
	_end_session(reason)


## Every end comes here: the sessions, the level and the views go, and last_words keeps why (with
## `detail` after the reason's words); a failure shows on the connecting screen first.
func _end_session(reason: StringName, detail := "") -> void:
	if _ending or _client == null:
		return
	_ending = true
	last_reason = reason
	if detail.is_empty():
		detail = JoinProgress.detail_of(reason, _join.transport, _join.own_content)
	var versions := JoinProgress.versions_of(reason, _join.transport, _join.own_content)
	print("session: ended: %s%s" % [EndReasons.text(reason), ": " + detail if detail else ""])
	if _host != null:
		# Leaving the tree closes the session: every client sees host_lost.
		remove_child(_host)
		_host.queue_free()
		_host = null
	if not _client.is_ended():
		_client.leave()
	_drop_room()
	_join.target = null
	_join.transport = null
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
	_levels.clear()
	if _player != null:
		_player.queue_free()
		_player = null
	tutorial.end(self)
	_show_end(reason, detail, versions)
	_ending = false


## The character the avatars wear: the shipped one, loaded at the first call, unless
## `load_character` is off or the build has none (an LFS pointer, CI's stand-in); else null.
func _character_set() -> CharacterSet:
	if load_character and not _character_loaded:
		_character_loaded = true
		_character = CharacterSet.load_default()
	return _character if load_character else null


## The voices follow the new session's ClientSession, model and avatars; the own voice speaks
## into it.
func _setup_voice() -> void:
	_voices.setup(_client, mode, _avatars, voice_codec)
	_sender.setup(_client, mode)


## Settings' Sound and voice on screen now: the Esc menu's, the main menu's, or null.
func shown_voice_panel() -> VoicePanel:
	return GameSettings.shown_voice(self)


func _cannot_host(why: String) -> void:
	print("session: cannot host: %s" % why)
	last_reason = EndReasons.CANNOT_HOST
	_show_end(EndReasons.CANNOT_HOST, why)


## The code host's room and its own signalling go with its session.
func _drop_room() -> void:
	if _room != null:
		_room.stop()
	_room = null


## After an end: its words kept (last_words), and its failure, if it has one, shows first.
func _show_end(reason: StringName, detail := "", versions := PackedStringArray()) -> void:
	ui.close_esc()
	if ui.menu.settings_open():
		ui.menu.close_panel()
	last_words = EndReasons.words(reason) + (": " + detail if not detail.is_empty() else "")
	var shown := ui.connecting.show_failure(EndReasons.failure_state(reason), versions)
	failure = reason if shown else &""
	ui.show_screen(screen())
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
