class_name EscMenuState
extends RefCounted
## Esc's menu as data (ARCHITECTURE §4.7, #169; the suit menu's side panel of prime-game-ui's
## handoff s05 at ui-2.5.4, #1571): whether it is open, which pages its entries open in which
## screen, the open page, the host's question, and who may change the match settings on its Lobby
## page. Pure, so the menu and its unit test read the same rules; EscMenu draws it.
##
## The pages: GAME is none open (the panel alone: Resume, Leave, Quit are its own entries), Guide
## (#254), Lobby (on the lobby screen, the lobby and the countdown: Ready and the match settings,
## the plainest stand-in until the ship's match console, s04, #1285), Settings. No Role page: the
## HUD shows the role (s05 at ui-2.3.0). The tutorial shows Guide and Settings. Character waits for
## the mirror (#1394, the engineer 2026-10-28). Opening shows the page chosen last on this kind of
## screen (the lobby screen or any other), else none.
## A player's Leave and Quit act at once, and so do the tutorial's; the host's ask first, since
## they end the session for every player: confirm() answers the question, cancel() drops it.

## The pages; GAME is none open. ROLE is never shown since #1571; it keeps the numbers the
## previews' `esc_tab` (client/dev/esc_*_preview.tscn) store.
enum Tab { GAME, ROLE, GUIDE, LOBBY, SETTINGS }
## What a press or a confirmation asks the game to do.
enum Action { NONE, RESUME, LEAVE, QUIT }

var is_open := false
var selected := Tab.GAME
## The screen the menu opened over and has followed since; another screen closes it (#726).
var over_screen := GameFlow.Screen.MENU
## The own player hosts: Leave and Quit end the session for everyone and ask first.
var hosting := false
## The lobby screen (the lobby and the countdown phases): the Lobby entry and the code's head.
var in_lobby := false
## The round: the panel's Resume, Guide, Settings, Leave and Quit (s05 `round`).
var in_round := false
## The tutorial's menu (#601 sets it): Guide and Settings, no Quit; Leave goes back to the main
## menu.
var tutorial := false
## The own player may change the match settings: the host, in a phase that accepts the host's
## ChangeSettings (the lobby, not the countdown); for everyone else they are read-only.
var may_change_settings := false
## The host's open question: Action.LEAVE or Action.QUIT; Action.NONE when none is open.
var question := Action.NONE

## The tab chosen last, and whether it was on the lobby screen; -1 before any.
var _remembered := -1
var _remembered_in_lobby := false


## Opens the menu on `screen`; `model` is the own ClientModel once welcomed (null before).
func open(screen: GameFlow.Screen, model: ClientModel, hosting_now: bool) -> void:
	is_open = true
	question = Action.NONE
	follow(screen, model, hosting_now)
	selected = default_tab()
	if _remembered >= 0 and _remembered_in_lobby == in_lobby and has_tab(_remembered as Tab):
		selected = _remembered as Tab


func close() -> void:
	is_open = false
	question = Action.NONE


## The host's window close button: the menu on Game with the question to quit. The tutorial's
## solo session asks nothing: Action.QUIT at once, as its Quit.
func ask_quit(screen: GameFlow.Screen, model: ClientModel) -> Action:
	open(screen, model, true)
	selected = Tab.GAME
	if tutorial:
		return Action.QUIT
	question = Action.QUIT
	return Action.NONE


## Follows the game while open: a tab that went away (the round started) gives way to the default.
func follow(screen: GameFlow.Screen, model: ClientModel, hosting_now: bool) -> void:
	hosting = hosting_now
	over_screen = screen
	in_lobby = screen == GameFlow.Screen.LOBBY
	in_round = screen == GameFlow.Screen.ROUND
	may_change_settings = in_lobby and hosting and settings_by_host(model)
	if not has_tab(selected):
		selected = default_tab()


## The pages the entries open, top to bottom (GAME: none open, always allowed).
func tabs() -> Array[Tab]:
	if tutorial:
		return [Tab.GAME, Tab.GUIDE, Tab.SETTINGS]
	var shown: Array[Tab] = [Tab.GAME, Tab.GUIDE]
	if in_lobby:
		shown.append(Tab.LOBBY)
	shown.append(Tab.SETTINGS)
	return shown


func has_tab(tab: Tab) -> bool:
	return tabs().has(tab)


## Nothing open: the panel alone (s05's `lobby` and `round`).
func default_tab() -> Tab:
	return Tab.GAME


## A press on `tab`'s entry: its page opens (a second press closes it again) and is remembered
## for the next opening on this kind of screen.
func press(tab: Tab) -> void:
	if not is_open or not has_tab(tab) or asking():
		return
	selected = Tab.GAME if selected == tab else tab
	_remembered = selected
	_remembered_in_lobby = in_lobby


## Resume: the menu closes.
func resume() -> Action:
	if not is_open:
		return Action.NONE
	close()
	return Action.RESUME


## Leave on the panel: the host asks first; a player and the tutorial leave at once.
func press_leave() -> Action:
	return _ask_or_act(Action.LEAVE)


## Quit on the panel: the host asks first; a player and the tutorial quit at once.
func press_quit() -> Action:
	return _ask_or_act(Action.QUIT)


## Whether the host's question waits for confirm() or cancel().
func asking() -> bool:
	return is_open and question != Action.NONE


## Yes to the host's question: the action it asked about.
func confirm() -> Action:
	if not asking():
		return Action.NONE
	var action := question
	question = Action.NONE
	return action


## No to the host's question: the panel again.
func cancel() -> void:
	question = Action.NONE


## Whether the current phase of `model` accepts the host's ChangeSettings.
static func settings_by_host(model: ClientModel) -> bool:
	if model == null:
		return false
	var spec := model.phase_spec()
	return spec != null and (spec.senders_of(Intents.CHANGE_SETTINGS) & AcceptSpec.From.HOST) != 0


func _ask_or_act(action: Action) -> Action:
	if not is_open or asking():
		return Action.NONE
	if hosting and not tutorial:
		question = action
		return Action.NONE
	return action
