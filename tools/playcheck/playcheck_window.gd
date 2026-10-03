extends SceneTree
## One window of `tools\run.cmd playcheck` (#186; docs/AGENT_WORKFLOW.md §11): the game,
## client/app/game.tscn, with the command line `host` and `join` give it, in a real window that
## the runner puts off-screen (never headless or minimized: Godot then draws nothing), running
## this window's steps from the runner's plan (tools/playcheck/playcheck_steps.gd).
##   godot --position -30000,-30000 --resolution 1280x720 --audio-driver Dummy
##       -s res://tools/playcheck/playcheck_window.gd
##       -- --plan=<plan.json> --window=<n> <LaunchOptions' arguments: --host --local or --join=...>
##
## It reads the game only through its own client (Game.client(): the ClientSession and its
## ClientModel), its screen, Esc menu and pointer, and what its Ui and current camera draw (the
## fields of `wait text` and `wait shown`, #275), as any window does; never HostSession, the match
## or core/ (invariant 2), on the host's window too. It never captures the real mouse: the game gets
## a pointer that remembers what it asked for, playcheck presses keys only (a click would capture
## the mouse; `button` focuses a Button and presses ui_accept's key), and a mouse mode set anyway
## is set back and fails the run.
##
## It writes its peer id to <peers>/peer-<n> once welcomed (the bots read it to name it); window 1
## reads the others' to send the setup (ForceRole names a peer). Prints PLAYCHECK at step <n> (line
## <l>: <text>) as each step starts, PLAYCHECK shot <png> per screenshot, then PLAYCHECK done
## window <n>, or PLAYCHECK fail step <n> (...): <why> (after saving failed-window-<n>.png) and
## exits 1. Done, it keeps running until the runner's stop file (Game's own check) ends it.

const Steps := preload("res://tools/playcheck/playcheck_steps.gd")
const GAME_SCENE := "res://client/app/game.tscn"
const PREFIX := "PLAYCHECK "
const PLAN_ARG := "--plan="
const WINDOW_ARG := "--window="


## The game's pointer in a playcheck window: it remembers what the game asked for and never
## touches Input.mouse_mode, so the human's mouse stays free.
class RememberedPointer:
	extends MousePointer
	var on := false

	func capture(value: bool) -> void:
		on = value

	func captured() -> bool:
		return on


## The View of playcheck_steps.gd over this window's Game.
class GameView:
	extends Steps.View
	var game: Game
	var peers_dir := ""
	var window := 0
	var received: Array[Array] = []
	var _peer_of: Dictionary[int, int] = {}

	func on_event(event_name: StringName, fields: Dictionary) -> void:
		received.append([event_name, fields])

	func model() -> ClientModel:
		var client := game.client() if is_instance_valid(game) else null
		return client.model if client != null and client.is_welcomed() else null

	func welcomed() -> bool:
		return model() != null

	## The game's session ended (its host closed, a refused join): it shows its menu with why.
	func unwelcomed() -> String:
		if is_instance_valid(game) and game.client() == null and not game.last_reason.is_empty():
			return "no session: it ended (%s)" % EndReasons.text(game.last_reason)
		return "no Welcome yet"

	func phase() -> String:
		return String(model().phase)

	func screen() -> String:
		return str(GameFlow.Screen.keys()[game.screen()]).to_lower()

	func own_peer() -> int:
		return model().own_peer if welcomed() else 0

	func peer_of(player: int) -> int:
		if player == window:
			return own_peer()
		if not _peer_of.has(player):
			var path := peers_dir.path_join("peer-%d" % player)
			var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
			if text.is_valid_int():
				_peer_of[player] = text.to_int()
		return _peer_of.get(player, 0)

	func roster_size() -> int:
		return model().roster.size()

	func life_of(peer: int) -> String:
		return str(ClientModel.Life.keys()[model().life_of(peer)]).to_lower()

	func ready_of(peer: int) -> bool:
		var member: ClientModel.Member = model().roster.get(peer)
		return member != null and member.ready

	func esc_open() -> bool:
		return game.ui.esc_open()

	func pointer_captured() -> bool:
		return game.pointer.captured()

	func events() -> Array[Array]:
		return received

	func field_text(field: String) -> String:
		return str(_field(field)[0])

	func field_shown(field: String) -> bool:
		var shown: bool = _field(field)[1]
		return shown

	## [text, shown] of a field, read from this window's Ui and current camera only; the keys here
	## and in _labels() are tools/runner/playcheck.py's FIELDS (its test holds them equal).
	func _field(field: String) -> Array:
		var ui := game.ui
		var labels := _labels()
		var found: Array = ["", false]
		if labels.has(field):
			found = [labels[field].text, labels[field].is_visible_in_tree()]
		match field:
			"life.bar":
				found = [ui.life.bar_label.text, ui.life.bar.is_visible_in_tree()]
			"end.back":
				found = [ui.end.back_button.text, ui.end.back_button.is_visible_in_tree()]
			"esc.tabs":
				var names := PackedStringArray()
				for button: Button in ui.esc.tab_buttons.values():
					if button.is_visible_in_tree():
						names.append(button.text)
				found = [", ".join(names), ui.esc.is_visible_in_tree()]
			"hand.item":
				var hand := _hand()
				var kind := hand.shown_kind() if hand != null else &""
				found = [kind, hand != null and hand.is_visible_in_tree() and not kind.is_empty()]
		return found

	## The fields that are one Label each: its text, shown while it is visible in the tree.
	func _labels() -> Dictionary[String, Label]:
		var ui := game.ui
		return {
			"hud.role": ui.hud.role_label,
			"hud.teammates": ui.hud.teammates_label,
			"hud.clock": ui.hud.clock_label,
			"hud.progress": ui.hud.progress_label,
			"hud.health": ui.hud.health_label,
			"hud.stamina": ui.hud.stamina_label,
			"hud.hand": ui.hud.hand_label,
			"hud.belt": ui.hud.belt_label,
			"hud.spectating": ui.hud.spectating_label,
			"hud.destination": ui.hud.destination_label,
			"hud.hint": ui.hud.hint_label,
			"hud.crosshair": ui.hud.crosshair,
			"life.title": ui.life.title_label,
			"life.lines": ui.life.lines_label,
			"lobby.hint": ui.lobby_hud.hint_label,
			"lobby.roster": ui.lobby_hud.roster_label,
			"lobby.countdown": ui.lobby_hud.countdown_label,
			"end.winner": ui.end.winner_label,
		}

	## The FirstPersonHand under the current camera: the own player's, or the spectated target's
	## (LifeView's spectate camera).
	func _hand() -> FirstPersonHand:
		var camera := game.get_viewport().get_camera_3d()
		if camera == null:
			return null
		for child: Node in camera.get_children():
			if child is FirstPersonHand:
				return child as FirstPersonHand
		return null


var _game: Game
var _view := GameView.new()
var _steps: Steps
var _window := 0
var _out := ""
var _held: Array[StringName] = []
var _wrote_peer := false
var _ended := false


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		_quit_failed(
			"running headless; playcheck needs a real window (Godot draws nothing headless)"
		)
		return
	var plan_path := ""
	var game_args := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(PLAN_ARG):
			plan_path = arg.trim_prefix(PLAN_ARG)
		elif arg.begins_with(WINDOW_ARG):
			_window = arg.trim_prefix(WINDOW_ARG).to_int()
		else:
			game_args.append(arg)
	var plan := _read_plan(plan_path)
	if plan.is_empty():
		return
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.read_command_line = false
	_game.launch_args = game_args
	_game.pointer = RememberedPointer.new()
	_view.game = _game
	_view.window = _window
	_view.peers_dir = str(plan.get("peers", ""))
	root.add_child(_game)
	_run()


func _read_plan(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var plan: Dictionary = parsed if parsed is Dictionary else {}
	var all_steps: Dictionary = plan.get("steps", {})
	if plan.is_empty() or not all_steps.has(str(_window)):
		_quit_failed("no plan for window %d in '%s'" % [_window, path])
		return {}
	var own: Array[Dictionary] = []
	for step: Variant in all_steps[str(_window)] as Array:
		own.append(step as Dictionary)
	_out = str(plan.get("out", ""))
	_steps = Steps.new(own, _view)
	_steps.on_step = _print_step
	print("%swindow %d: %d steps" % [PREFIX, _window, own.size()])
	return plan


func _run() -> void:
	# The root enters the tree after _initialize: the game's _ready, which hosts or joins, comes then.
	if not _game.is_node_ready():
		await _game.ready
	var client := _game.client()
	if client == null:
		_quit_failed("the game started no session (its menu says why: see the session: lines)")
		return
	client.event_received.connect(_view.on_event)
	while _steps.status == Steps.Status.RUNNING:
		await process_frame
		if not is_instance_valid(_game) or _game.is_queued_for_deletion():
			return
		_guard_mouse()
		_write_peer()
		for action: StringName in _held:
			# A focus change releases every pressed action; a hold lasts until its release step.
			Input.action_press(action)
		var step := _steps.advance(Time.get_ticks_msec())
		if not step.is_empty():
			await _act(step)
	if _steps.status == Steps.Status.FAILED:
		await _fail_with_shot()
		return
	print("%sdone window %d" % [PREFIX, _window])


func _act(step: Dictionary) -> void:
	var action := StringName(str(step.get("action", "")))
	match str(step.get("do", "")):
		"press":
			await _press(action)
		"hold":
			if _has_action(action):
				Input.action_press(action)
				_held.append(action)
		"release":
			_held.erase(action)
			Input.action_release(action)
		"button":
			await _button(str(step.get("label", "")))
		"shot":
			await _shot(str(step.get("path", "")))
		"setup":
			_setup(step)
		_:
			_steps.fail("unknown step '%s'" % step.get("do", ""))


## The action's key pressed, then released the next frame, through Input.parse_input_event as a
## real key reaches _input, _unhandled_input and the action states.
func _press(action: StringName) -> void:
	if not _has_action(action):
		return
	var key: InputEventKey = null
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			key = event as InputEventKey
			break
	if key == null:
		_steps.fail(
			"%s has no key: playcheck presses keys only (a click would capture the mouse)" % action
		)
		return
	var down := key.duplicate() as InputEventKey
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await process_frame
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


## The one visible, enabled Button of the Ui whose text is `text` takes the focus and gets
## ui_accept's key as `press` gives it: no mouse event, so nothing captures the mouse.
func _button(text: String) -> void:
	var buttons := Steps.visible_buttons(_game.ui)
	var why := Steps.button_problem(buttons, text)
	if not why.is_empty():
		_steps.fail(why)
		return
	var target := Steps.buttons_named(buttons, text)[0]
	target.grab_focus()
	# A Button with focus_mode FOCUS_NONE keeps the focus where it was (a warning only), so
	# ui_accept would press whatever control has it.
	if not target.has_focus():
		_steps.fail("button '%s' cannot take the focus (its focus_mode)" % text)
		return
	await _press(&"ui_accept")


func _has_action(action: StringName) -> bool:
	if InputMap.has_action(action):
		return true
	_steps.fail("no input action '%s' in the project" % action)
	return false


## The viewport after this frame is drawn, as a PNG (as tools/shot/shot.gd saves it).
func _shot(path: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_steps.fail("the viewport gave an empty image")
		return false
	var error := image.save_png(path)
	if error != OK:
		_steps.fail("cannot save %s: %s" % [path, error_string(error)])
		return false
	print("%sshot %s %dx%d" % [PREFIX, path, image.get_width(), image.get_height()])
	return true


## Window 1, once every player is in its roster: the forced roles, the clock and the settings,
## sent through its own client as the bots' host bot sends them (NetPlay._send_setup).
func _setup(step: Dictionary) -> void:
	var client := _game.client()
	var roles: Dictionary = step.get("roles", {})
	for player: Variant in roles:
		var peer := _view.peer_of(Steps.number(player))
		if client.force_role(peer, str(roles[player])) < 0:
			_steps.fail("could not send ForceRole for player %s" % player)
	var clock := Steps.number(step.get("clock", 0))
	if clock > 0 and client.force_clock(_view.own_peer(), clock) < 0:
		_steps.fail("could not send ForceClock")
	var settings: Dictionary = step.get("settings", {})
	for id: Variant in settings:
		_game.change_setting(StringName(str(id)), Steps.number(settings[id]))


func _write_peer() -> void:
	if _wrote_peer or not _view.welcomed():
		return
	_wrote_peer = true
	var dir := _view.peers_dir
	var part := dir.path_join("peer-%d.part" % _window)
	var file := FileAccess.open(part, FileAccess.WRITE)
	if file == null:
		_steps.fail("cannot write %s" % part)
		return
	file.store_string(str(_view.own_peer()))
	file.close()
	# Readers never see a half-written id: the file appears whole.
	if DirAccess.rename_absolute(part, dir.path_join("peer-%d" % _window)) != OK:
		_steps.fail("cannot rename %s" % part)


func _guard_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_steps.fail("something set the real mouse mode; playcheck never captures the mouse")


func _print_step(at: int, _step: Dictionary) -> void:
	print("%sat %s" % [PREFIX, _steps.describe(at)])


## Saves what the window shows as failed-window-<n>.png, prints the failure and exits 1.
func _fail_with_shot() -> void:
	for action: StringName in _held:
		Input.action_release(action)
	_held.clear()
	var why := _steps.failure
	var path := _out.path_join("failed-window-%d.png" % _window)
	if not _out.is_empty() and await _shot(path):
		why += " (its screen: %s)" % path
	_quit_failed(why)


func _quit_failed(why: String) -> void:
	if _ended:
		return
	_ended = true
	print("%sfail %s" % [PREFIX, why])
	if is_instance_valid(_game) and _game.is_node_ready():
		# Ends the session first, as the game's own Quit does: freed with the tree, a running
		# host would end it from its _exit_tree, while the tree is removing children.
		_game.leave()
	quit(1)
