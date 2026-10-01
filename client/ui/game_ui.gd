class_name GameUi
extends CanvasLayer
## The `Ui` layer of the game (ARCHITECTURE §4.7): one screen at a time as GameFlow says, and Esc's
## menu over it. It shows what the own ClientModel and the client's own mode hold; the game
## connects the screens' signals.

var menu := MainMenu.new()
var connecting := ConnectingScreen.new()
var lobby := LobbyPanel.new()
var loading := LoadingScreen.new()
var end := EndScreen.new()
var esc := EscMenu.new()
var screen := GameFlow.Screen.MENU


func _init() -> void:
	name = "Ui"
	for each: Control in [menu, connecting, lobby, loading, end, esc]:
		add_child(each)
	show_screen(GameFlow.Screen.MENU)
	close_esc()


## The screen of `which`; the round shows none until M4-8's HUD.
func show_screen(which: GameFlow.Screen) -> void:
	screen = which
	menu.visible = which == GameFlow.Screen.MENU
	connecting.visible = which == GameFlow.Screen.CONNECTING
	lobby.visible = which == GameFlow.Screen.LOBBY
	loading.visible = which == GameFlow.Screen.LOADING
	end.visible = which == GameFlow.Screen.END


## Refreshes the visible screen from `model`; `host_tick` is the newest host tick known.
func refresh(model: ClientModel, mode: GameMode, host_tick: int, hosting: bool) -> void:
	match screen:
		GameFlow.Screen.LOBBY:
			lobby.refresh(model, host_tick)
		GameFlow.Screen.LOADING:
			loading.refresh(model)
		GameFlow.Screen.END:
			end.refresh(model, mode, hosting)


func open_esc(hosting: bool) -> void:
	esc.open(hosting)
	esc.visible = true


func close_esc() -> void:
	esc.visible = false


func esc_open() -> bool:
	return esc.visible
