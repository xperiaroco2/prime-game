class_name EscMenuState
extends RefCounted
## Esc's menu as data (ARCHITECTURE §4.7, #169): whether it is open, which tabs it has in which
## screen, the selected tab, and who may change the match settings in its Lobby tab. Pure, so the
## menu and its unit test read the same rules; EscMenu draws it.
##
## The tabs: Resume, Lobby (on the lobby screen only: the lobby and the countdown), Leave and Quit.
## Resume closes the menu. A client's Leave and Quit act at once; the host's ask first, since they
## end the session for every player, so the host's Leave or Quit tab shows the question and
## confirm() answers it. Opening selects the Lobby tab where there is one, else Resume.

enum Tab { RESUME, LOBBY, LEAVE, QUIT }
## What a press or a confirmation asks the game to do.
enum Action { NONE, RESUME, LEAVE, QUIT }

var is_open := false
var selected := Tab.RESUME
## The own player hosts: Leave and Quit end the session for everyone and ask first.
var hosting := false
## The Lobby tab exists: the lobby screen (the lobby and the countdown phases).
var in_lobby := false
## The own player may change the match settings: the host, in a phase that accepts the host's
## ChangeSettings (the lobby, not the countdown); for everyone else they are read-only.
var may_change_settings := false


## Opens the menu on `screen`; `model` is the own ClientModel once welcomed (null before).
func open(screen: GameFlow.Screen, model: ClientModel, hosting_now: bool) -> void:
	is_open = true
	follow(screen, model, hosting_now)
	selected = default_tab()


func close() -> void:
	is_open = false


## Opens the menu at the host's question to quit (the window's close button).
func ask_quit(screen: GameFlow.Screen, model: ClientModel) -> void:
	open(screen, model, true)
	selected = Tab.QUIT


## Follows the game while open: a tab that went away (the round started) gives way to the default.
func follow(screen: GameFlow.Screen, model: ClientModel, hosting_now: bool) -> void:
	hosting = hosting_now
	in_lobby = screen == GameFlow.Screen.LOBBY
	may_change_settings = in_lobby and hosting and settings_by_host(model)
	if not has_tab(selected):
		selected = default_tab()


## The tabs in their order, top to bottom.
func tabs() -> Array[Tab]:
	var shown: Array[Tab] = [Tab.RESUME]
	if in_lobby:
		shown.append(Tab.LOBBY)
	shown.append_array([Tab.LEAVE, Tab.QUIT])
	return shown


func has_tab(tab: Tab) -> bool:
	return tabs().has(tab)


func default_tab() -> Tab:
	return Tab.LOBBY if in_lobby else Tab.RESUME


## A press on `tab`: Resume closes the menu; a client's Leave and Quit act at once; anything else
## selects the tab (the host's Leave and Quit show their question).
func press(tab: Tab) -> Action:
	if not is_open or not has_tab(tab):
		return Action.NONE
	match tab:
		Tab.RESUME:
			close()
			return Action.RESUME
		Tab.LEAVE, Tab.QUIT:
			if not hosting:
				return Action.LEAVE if tab == Tab.LEAVE else Action.QUIT
	selected = tab
	return Action.NONE


## Whether the selected tab is a question waiting for confirm() or cancel().
func asking() -> bool:
	return is_open and hosting and (selected == Tab.LEAVE or selected == Tab.QUIT)


## Yes to the host's question: the action it asked about.
func confirm() -> Action:
	if not asking():
		return Action.NONE
	var action := Action.LEAVE if selected == Tab.LEAVE else Action.QUIT
	selected = default_tab()
	return action


## No to the host's question: back to the default tab.
func cancel() -> void:
	if asking():
		selected = default_tab()


## Whether the current phase of `model` accepts the host's ChangeSettings.
static func settings_by_host(model: ClientModel) -> bool:
	if model == null:
		return false
	var spec := model.phase_spec()
	return spec != null and (spec.senders_of(Intents.CHANGE_SETTINGS) & AcceptSpec.From.HOST) != 0
