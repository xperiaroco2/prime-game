class_name GameUi
extends CanvasLayer
## The `Ui` layer of the game (ARCHITECTURE §4.7): one screen at a time as GameFlow says, and Esc's
## menu over it; in the round the HUD, and the task screen while Tab (`task_screen`) is held. It
## shows what the own ClientModel and the client's own mode hold; the game connects the screens'
## signals.
##
## Every screen is styled only through one shared Theme, THEME (the M4 manager's decision of
## 2026-10-01 on #144 and #145; client/CLAUDE.md): a CanvasLayer holds no theme, so each Control
## child of this layer gets it, also one added later (the debug overlay, a later screen).

const THEME := preload("res://client/ui/theme/game_theme.tres")

var menu := MainMenu.new()
var connecting := ConnectingScreen.new()
var lobby := LobbyPanel.new()
var loading := LoadingScreen.new()
var hud := Hud.new()
var tasks := TaskScreen.new()
var end := EndScreen.new()
var esc := EscMenu.new()
## The own player's life in the round (M4-9).
var life := LifePanel.new()
var screen := GameFlow.Screen.MENU
## Read the task screen's key. Tests and previews turn it off and call show_tasks() themselves.
var reads_device_input := true

var _tasks_held := false


func _init() -> void:
	name = "Ui"
	child_entered_tree.connect(_style)
	for each: Control in [menu, connecting, lobby, loading, hud, life, tasks, end, esc]:
		_style(each)
		add_child(each)
	show_screen(GameFlow.Screen.MENU)
	close_esc()


func _process(_delta: float) -> void:
	if reads_device_input:
		show_tasks(Input.is_action_pressed(&"task_screen"))


## The screen of `which`; the round shows the HUD.
func show_screen(which: GameFlow.Screen) -> void:
	screen = which
	menu.visible = which == GameFlow.Screen.MENU
	connecting.visible = which == GameFlow.Screen.CONNECTING
	lobby.visible = which == GameFlow.Screen.LOBBY
	loading.visible = which == GameFlow.Screen.LOADING
	hud.visible = which == GameFlow.Screen.ROUND
	end.visible = which == GameFlow.Screen.END
	life.visible = which == GameFlow.Screen.ROUND
	show_tasks(_tasks_held)


## The task screen while `held` (Tab) in the round.
func show_tasks(held: bool) -> void:
	_tasks_held = held
	tasks.visible = held and screen == GameFlow.Screen.ROUND


## Refreshes the visible screen from `model`; `host_tick` is the newest host tick known.
func refresh(model: ClientModel, mode: GameMode, host_tick: int, hosting: bool) -> void:
	match screen:
		GameFlow.Screen.LOBBY:
			lobby.refresh(model, host_tick)
		GameFlow.Screen.LOADING:
			loading.refresh(model)
		GameFlow.Screen.END:
			end.refresh(model, mode, hosting)


## Refreshes the round's HUD and task screen; `local` is what the game knows besides the model.
func refresh_round(
	model: ClientModel, mode: GameMode, host_tick: float, local: HudText.Local
) -> void:
	if screen != GameFlow.Screen.ROUND:
		return
	hud.show_hud(HudText.of(model, mode, host_tick, local))
	if tasks.visible:
		tasks.refresh(model, mode)


func open_esc(hosting: bool) -> void:
	esc.open(hosting)
	esc.visible = true


func close_esc() -> void:
	esc.visible = false


func esc_open() -> bool:
	return esc.visible


## Gives a Control child the shared theme, unless it brought one of its own.
func _style(child: Node) -> void:
	var control := child as Control
	if control != null and control.theme == null:
		control.theme = THEME
