class_name EscMenuState
extends RefCounted
## Esc's menu as data (ARCHITECTURE §4.7, #169; the Toy menu of #491, prime-game-ui handoff s05 at
## ui-0.4.0): whether it is open, which tabs it has in which screen, the selected tab, the host's
## question, and who may change the match settings in its Lobby tab. Pure, so the menu and its
## unit test read the same rules; EscMenu draws it.
##
## The tabs, top to bottom: Game (Resume, Leave, Quit), Role (in the round only), Guide (#254),
## Lobby (on the lobby screen only: the lobby and the countdown), Settings. The tutorial shows only
## Game, Guide and Settings. The Character tab waits for #73. Opening selects the tab chosen last
## on this kind of screen (the lobby screen or any other), else the default: Lobby in the lobby,
## Game everywhere else.
## A player's Leave and Quit act at once, and so do the tutorial's; the host's ask first, since
## they end the session for every player: confirm() answers the question, cancel() drops it.

## The tabs in their order on the menu.
enum Tab { GAME, ROLE, GUIDE, LOBBY, SETTINGS }
## What a press or a confirmation asks the game to do.
enum Action { NONE, RESUME, LEAVE, QUIT }

var is_open := false
var selected := Tab.GAME
## The own player hosts: Leave and Quit end the session for everyone and ask first.
var hosting := false
## The Lobby tab exists: the lobby screen (the lobby and the countdown phases).
var in_lobby := false
## The Role tab exists: the round.
var in_round := false
## The tutorial's menu (#601 sets it): Game, Guide and Settings; Leave goes back to the main menu.
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


## Opens the menu on Game with the host's question to quit (the window's close button).
func ask_quit(screen: GameFlow.Screen, model: ClientModel) -> void:
	open(screen, model, true)
	selected = Tab.GAME
	question = Action.QUIT


## Follows the game while open: a tab that went away (the round started) gives way to the default.
func follow(screen: GameFlow.Screen, model: ClientModel, hosting_now: bool) -> void:
	hosting = hosting_now
	in_lobby = screen == GameFlow.Screen.LOBBY
	in_round = screen == GameFlow.Screen.ROUND
	may_change_settings = in_lobby and hosting and settings_by_host(model)
	if not has_tab(selected):
		selected = default_tab()


## The tabs in their order, top to bottom.
func tabs() -> Array[Tab]:
	if tutorial:
		return [Tab.GAME, Tab.GUIDE, Tab.SETTINGS]
	var shown: Array[Tab] = [Tab.GAME]
	if in_round:
		shown.append(Tab.ROLE)
	shown.append(Tab.GUIDE)
	if in_lobby:
		shown.append(Tab.LOBBY)
	shown.append(Tab.SETTINGS)
	return shown


func has_tab(tab: Tab) -> bool:
	return tabs().has(tab)


func default_tab() -> Tab:
	return Tab.LOBBY if in_lobby and not tutorial else Tab.GAME


## A press on `tab`: it is selected and remembered for the next opening on this kind of screen.
func press(tab: Tab) -> void:
	if not is_open or not has_tab(tab) or asking():
		return
	selected = tab
	_remembered = tab
	_remembered_in_lobby = in_lobby


## Resume: the menu closes.
func resume() -> Action:
	if not is_open:
		return Action.NONE
	close()
	return Action.RESUME


## Leave on the Game page: the host asks first; a player and the tutorial leave at once.
func press_leave() -> Action:
	return _ask_or_act(Action.LEAVE)


## Quit on the Game page: the host asks first; a player and the tutorial quit at once.
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


## No to the host's question: the Game page again.
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
