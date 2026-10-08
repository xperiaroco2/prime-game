class_name GameUi
extends CanvasLayer
## The `Ui` layer of the game (ARCHITECTURE §4.7): one screen at a time as GameFlow says, and Esc's
## menu over it; in the lobby the lobby HUD (the keys' hint, the roster), whose Ready and settings
## are in the Esc menu's Lobby tab (#169); in the round the HUD, and the task screen while Tab
## (`task_screen`) is held. It shows what the own ClientModel and the client's own mode hold; the
## game connects the screens' signals.
##
## Every screen is styled only through one shared Theme, THEME (the M4 manager's decision of
## 2026-10-01 on #144 and #145; client/CLAUDE.md): a CanvasLayer holds no theme, so each Control
## child of this layer gets it, also one added later (the debug overlay, a later screen). Large
## text swaps it for THEME_LARGE, the same theme with larger text (#289; Settings > Accessibility,
## #491, calls set_large_text).

const THEME := preload("res://client/ui/theme/game_theme.tres")
const THEME_LARGE := preload("res://client/ui/theme/game_theme_large.tres")

var menu := MainMenu.new()
var connecting := ConnectingScreen.new()
## Walking in the lobby: the keys' hint, the roster and the countdown, nothing to click.
var lobby_hud := LobbyHud.new()
var loading := LoadingScreen.new()
var hud := Hud.new()
var tasks := TaskScreen.new()
var end := EndScreen.new()
var esc := EscMenu.new()
## The own player's life in the round (M4-9).
var life := LifePanel.new()
var screen := GameFlow.Screen.MENU
## Read the task screen's key (the game sets it from its own `device_input`). Tests and previews
## turn it off and call show_tasks() themselves. Under the Esc menu the key does nothing.
var reads_device_input := true
## Whether the screens have the large-text theme (set_large_text).
var large_text := false

var _tasks_held := false
## Whether the own player is living, from the last refresh_round: the crosshair is for the living
## (the downed and the dead pick nothing up).
var _alive := true
## The last round's model and mode, so the task screen has its rows on the frame Tab shows it.
var _model: ClientModel
var _mode: GameMode


func _init() -> void:
	name = "Ui"
	child_entered_tree.connect(_style)
	for each: Control in [menu, connecting, lobby_hud, loading, hud, life, tasks, end, esc]:
		_style(each)
		add_child(each)
	show_screen(GameFlow.Screen.MENU)
	close_esc()


func _process(_delta: float) -> void:
	if reads_device_input:
		show_tasks(not esc_open() and Input.is_action_pressed(&"task_screen"))


## The screen of `which`; the round shows the HUD.
func show_screen(which: GameFlow.Screen) -> void:
	screen = which
	menu.visible = which == GameFlow.Screen.MENU
	connecting.visible = which == GameFlow.Screen.CONNECTING
	lobby_hud.visible = which == GameFlow.Screen.LOBBY
	loading.visible = which == GameFlow.Screen.LOADING
	hud.visible = which == GameFlow.Screen.ROUND
	end.visible = which == GameFlow.Screen.END
	life.visible = which == GameFlow.Screen.ROUND
	show_tasks(_tasks_held)


## The task screen while `held` (Tab) in the round; the crosshair while it is not, for the living.
func show_tasks(held: bool) -> void:
	var was_shown := tasks.visible
	_tasks_held = held
	tasks.visible = held and screen == GameFlow.Screen.ROUND
	hud.aiming = not tasks.visible and _alive
	if tasks.visible and not was_shown and _model != null:
		tasks.refresh(_model, _mode)


## Refreshes the visible screen and an open Esc menu from `model`; `host_tick` is the newest host
## tick known.
func refresh(model: ClientModel, mode: GameMode, host_tick: int, hosting: bool) -> void:
	esc.refresh(screen, model, host_tick, hosting)
	match screen:
		GameFlow.Screen.LOBBY:
			lobby_hud.refresh(model, host_tick)
		GameFlow.Screen.LOADING:
			loading.refresh(model)
		GameFlow.Screen.END:
			end.refresh(model, mode, host_tick)


## Refreshes the round's HUD and task screen; `local` is what the game knows besides the model.
func refresh_round(
	model: ClientModel, mode: GameMode, host_tick: float, local: HudText.Local
) -> void:
	if screen != GameFlow.Screen.ROUND:
		return
	_model = model
	_mode = mode
	_alive = model.is_alive(model.own_peer)
	hud.aiming = not tasks.visible and _alive
	hud.show_hud(HudText.of(model, mode, host_tick, local))
	if tasks.visible:
		tasks.refresh(model, mode)


## Opens the Esc menu over `screen_now`, by default the screen drawn last; `model` is the own
## ClientModel once welcomed. The game passes its live screen: an Esc in the frame the Welcome
## arrives comes before its _process draws the lobby, and opens on the Lobby tab still (#204).
func open_esc(
	hosting: bool, model: ClientModel = null, screen_now: GameFlow.Screen = screen
) -> void:
	esc.open(screen_now, model, hosting)


func close_esc() -> void:
	esc.close()


func esc_open() -> bool:
	return esc.is_open()


## Swaps every screen's theme to the large-text one while `on`, and back: live, a screen that
## brought its own theme keeps it, and a screen added later gets the theme of the moment.
func set_large_text(on: bool) -> void:
	large_text = on
	for child: Node in get_children():
		var control := child as Control
		if control != null and (control.theme == THEME or control.theme == THEME_LARGE):
			control.theme = shared_theme()


## The shared theme the screens have now: THEME, or THEME_LARGE under large text.
func shared_theme() -> Theme:
	return THEME_LARGE if large_text else THEME


## Gives a Control child the shared theme, unless it brought one of its own.
func _style(child: Node) -> void:
	var control := child as Control
	if control != null and control.theme == null:
		control.theme = shared_theme()
