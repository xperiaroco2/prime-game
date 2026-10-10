class_name GameUi
extends CanvasLayer
## The `Ui` layer of the game (ARCHITECTURE §4.7): one screen at a time as GameFlow says, and Esc's
## menu over it; in the lobby the lobby HUD (the keys' hint, the roster), whose Ready and settings
## are in the Esc menu's Lobby tab (#169); in the round the HUD, and the map and tasks screen while
## it is open (#253: the game toggles it on the `map` action; one place holds whether it is open,
## and the Esc menu and every screen but the round close it); under them, in the lobby and the
## round, the name plates over the others' heads (#257). It shows what the own ClientModel and the
## client's own mode hold; the game connects the screens' signals.
##
## Every screen is styled only through one shared Theme, THEME (the M4 manager's decision of
## 2026-10-01 on #144 and #145; client/CLAUDE.md): a CanvasLayer holds no theme, so each Control
## child of this layer gets it, also one added later (the debug overlay, a later screen). Large
## text swaps it for THEME_LARGE, the same theme with larger text (#289; Settings > Accessibility,
## #491, calls set_large_text).
##
## Esc closes the open overlay on top, one per press (#488, `overlays`, §4.7.35): the main
## menu's open panel, the map, a card over the map, the Esc menu and its question to the host
## register here; the how-to card over the map (#254, `howto_card`: UiOverlays.CARD, the map key
## closing it too).

## The map and tasks screen opened (the game frees the mouse; the tutorial's `map_opened`).
signal map_opened
## It closed: by the key, Esc, the Esc menu or the end of the round.
signal map_closed
## The map loading started (the connecting screen shows its players and a tip): the game may put a
## how-to card there instead (show_loading_card, #254).
signal loading_started

const THEME := preload("res://client/ui/theme/game_theme.tres")
const THEME_LARGE := preload("res://client/ui/theme/game_theme_large.tres")
## The screens the connecting screen draws (s3).
const BLACK_SCREENS: Array[GameFlow.Screen] = [
	GameFlow.Screen.CONNECTING, GameFlow.Screen.FAILURE, GameFlow.Screen.LOADING
]

## The name plates over the others' heads (#257), under every screen: the lobby and the round.
var plates := NamePlates.new()
var menu := MainMenu.new()
## The black screen of a join, its failure and the map loading (#494): Connecting, Failure and
## Loading show it, each its own part.
var connecting := ConnectingScreen.new()
## Walking in the lobby: the keys' hint, the roster and the countdown, nothing to click.
var lobby_hud := LobbyHud.new()
## The silent seconds before the round: black, the own role, its goal and a dissident's team
## (#213, #496); over the HUD, so its black fades out over the round's first moment.
var pregame := PregameScreen.new()
var hud := Hud.new()
var map := MapScreen.new()
var end := EndScreen.new()
var esc := EscMenu.new()
## The downed, dead and respawn plates over the HUD in the round (M4-9; the Toy s09, #497).
var life := LifeScreen.new()
var screen := GameFlow.Screen.MENU
## What Esc closes, the topmost first (#488): Game._input asks it before it opens the Esc menu.
var overlays := UiOverlays.new()
## Whether the screens have the large-text theme (set_large_text).
var large_text := false

var _map_open := false
## Whether the own player is living, from the last refresh_round: the crosshair is for the living
## (the downed and the dead pick nothing up).
var _alive := true
## The last round's refresh, so the map has its rows on the frame it opens.
var _model: ClientModel
var _mode: GameMode
var _host_tick := 0.0
var _local := HudText.Local.new()


func _init() -> void:
	name = "Ui"
	child_entered_tree.connect(_style)
	for each: Control in [plates, menu, connecting, lobby_hud, hud, life, map, pregame, end, esc]:
		_style(each)
		add_child(each)
	show_screen(GameFlow.Screen.MENU)
	close_esc()
	overlays.add(&"menu_panel", UiOverlays.MENU_PANEL, _menu_panel_open, menu.close_panel)
	overlays.add(&"map", UiOverlays.MAP, map_is_open, close_map)
	# The how-to card over the map (#254): Esc and the map key close it before the map.
	overlays.add(&"howto_card", UiOverlays.CARD, map.howto_open, map.close_howto, true)
	# Esc on the menu is its Resume: the game closes it and captures the mouse again.
	overlays.add(&"esc_menu", UiOverlays.ESC_MENU, esc_open, esc.resume)
	# The host's question over the menu (#491's confirm dialog): Esc is its Cancel, the menu stays.
	overlays.add(&"esc_dialog", UiOverlays.ESC_DIALOG, esc.state.asking, esc.cancel)


## The screen of `which`; the round shows the HUD. Loading's start draws its tip (once per
## loading); the connecting and failure parts are the game's to set (show_join, show_failure).
func show_screen(which: GameFlow.Screen) -> void:
	var loading_now := which == GameFlow.Screen.LOADING and screen != which
	if loading_now:
		connecting.show_loading()
	_show_pregame(which)
	screen = which
	plates.visible = which == GameFlow.Screen.LOBBY or which == GameFlow.Screen.ROUND
	menu.visible = which == GameFlow.Screen.MENU
	connecting.visible = which in BLACK_SCREENS
	lobby_hud.visible = which == GameFlow.Screen.LOBBY
	hud.visible = which == GameFlow.Screen.ROUND
	end.visible = which == GameFlow.Screen.END
	life.visible = which == GameFlow.Screen.ROUND
	if which != GameFlow.Screen.ROUND:
		close_map()
	_show_map()
	if loading_now:
		loading_started.emit()


## The pregame's intro shows in the pregame; at the round's start its black fades out over the
## HUD and hides itself (#496); any other screen hides it at once. Runs before `screen` changes.
func _show_pregame(which: GameFlow.Screen) -> void:
	if which == GameFlow.Screen.PREGAME:
		pregame.reveal()
	elif which == GameFlow.Screen.ROUND and screen == GameFlow.Screen.PREGAME:
		pregame.lift()
	elif which != GameFlow.Screen.ROUND:
		pregame.stop()


## The loading screen shows `type`'s how-to card instead of the players and the tip (load-card,
## #254); false when the type has no card.
func show_loading_card(type: StringName) -> bool:
	var card := HowtoCards.of_task(type)
	if card == null:
		return false
	connecting.show_card(HowtoCardView.raised(card, HowtoCardView.LOADING_ART, ToyHints.DARK))
	return true


## Opens the map and tasks screen, in the round with no Esc menu only.
func open_map() -> void:
	if _map_open or screen != GameFlow.Screen.ROUND or esc_open():
		return
	_map_open = true
	_show_map()
	map_opened.emit()


func close_map() -> void:
	if not _map_open:
		return
	_map_open = false
	_show_map()
	map_closed.emit()


## The map key: opens the map, or closes it when open.
func toggle_map() -> void:
	if _map_open:
		close_map()
	else:
		open_map()


func map_is_open() -> bool:
	return _map_open


## The map key (#488 rule 3): closes a card over the map (an overlay the key closes), else opens
## or closes the map; ignored under the Esc menu. Returns whether the key was used.
func press_map_key() -> bool:
	if esc_open():
		return false
	if not overlays.close_top_for_map_key():
		toggle_map()
	return true


## The level's rooms and zones for the map (the game reads them when a map level loads).
func set_map_data(data: MapData) -> void:
	map.set_data(data)


## Refreshes the visible screen and an open Esc menu from `model`; `host_tick` is the newest host
## tick known.
func refresh(model: ClientModel, mode: GameMode, host_tick: int, hosting: bool) -> void:
	esc.refresh(screen, model, host_tick, hosting, mode)
	match screen:
		GameFlow.Screen.LOBBY:
			lobby_hud.refresh(model, host_tick)
		GameFlow.Screen.LOADING:
			connecting.refresh_loading(model)
		GameFlow.Screen.PREGAME:
			pregame.refresh(model, mode)
		GameFlow.Screen.END:
			end.refresh(model, mode, host_tick)


## Refreshes the round's HUD and the map while open; `local` is what the game knows besides the
## model.
func refresh_round(
	model: ClientModel, mode: GameMode, host_tick: float, local: HudText.Local
) -> void:
	if screen != GameFlow.Screen.ROUND:
		return
	_model = model
	_mode = mode
	_host_tick = host_tick
	_local = local
	_alive = model.is_alive(model.own_peer)
	hud.aiming = not map.visible and _alive
	hud.show_hud(HudText.of(model, mode, host_tick, local))
	if map.visible:
		map.refresh(model, mode, host_tick, local)


## Opens the Esc menu over `screen_now`, by default the screen drawn last; `model` is the own
## ClientModel once welcomed. The game passes its live screen: an Esc in the frame the Welcome
## arrives comes before its _process draws the lobby, and opens on the Lobby tab still (#204).
func open_esc(
	hosting: bool, model: ClientModel = null, screen_now: GameFlow.Screen = screen
) -> void:
	esc.open(screen_now, model, hosting)
	# Never both: the map closes under the menu, after it opened, so whoever hears map_closed sees
	# the menu open and leaves the mouse free.
	close_map()


func close_esc() -> void:
	esc.close()


func esc_open() -> bool:
	return esc.is_open()


## The tutorial runs (GameTutorial.start and end call it, #601): the Esc menu shows only Game,
## Guide and Settings, and its Leave, its Quit and the window's close button act at once.
func set_tutorial(on: bool) -> void:
	esc.state.tutorial = on


## The main menu's open panel (code, Direct or Settings, #493), only while the main menu shows (its
## panel stays set under a session).
func _menu_panel_open() -> bool:
	return screen == GameFlow.Screen.MENU and menu.panel_open()


## The map shows while open in the round; it hides the crosshair. The first frame it shows has
## its rows.
func _show_map() -> void:
	var was_shown := map.visible
	map.visible = _map_open and screen == GameFlow.Screen.ROUND
	hud.aiming = not map.visible and _alive
	hud.role_hidden = map.visible
	if map.visible and not was_shown and _model != null:
		map.refresh(_model, _mode, _host_tick, _local)


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
