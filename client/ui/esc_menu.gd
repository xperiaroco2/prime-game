class_name EscMenu
extends Control
## Esc's menu (ARCHITECTURE §4.7, #169): the tabs on the left (Resume; Lobby in the lobby and the
## countdown; Voice; Leave; Quit) and the selected tab's page on the right. The Lobby tab is
## LobbyPanel: the roster, Ready and the match settings (the host's to change, read-only for
## everyone else). The Voice tab is VoicePanel (M5-6), which the game feeds and listens to.
## On the host, Leave and Quit end the session for every player, so their tabs ask first; closing
## the window asks the same. What it shows and does is EscMenuState's; this draws it.

signal resume_requested
signal leave_requested
signal quit_requested

const TAB_NAMES: Dictionary[EscMenuState.Tab, String] = {
	EscMenuState.Tab.RESUME: "Resume",
	EscMenuState.Tab.LOBBY: "Lobby",
	EscMenuState.Tab.VOICE: "Voice",
	EscMenuState.Tab.LEAVE: "Leave",
	EscMenuState.Tab.QUIT: "Quit",
}
const RESUME_TEXT := "Back to the game: Esc or Resume."
const HOST_WARNING := "You host this session: leaving ends it for every player."
## The pages' room on the right (layout, not style): the Lobby tab scrolls inside it.
const PAGE_SIZE := Vector2(460, 440)

var state := EscMenuState.new()
var lobby := LobbyPanel.new()
var voice := VoicePanel.new()
var tab_buttons: Dictionary[EscMenuState.Tab, Button] = {}
var resume_page := VBoxContainer.new()
var confirm_box := VBoxContainer.new()
var warning_label := Label.new()
var confirm_label := Label.new()


func _init() -> void:
	name = "EscMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiParts.backdrop(self, &"EscShade")
	var column := UiParts.centered_column(self, "Menu")
	var body := HBoxContainer.new()
	body.theme_type_variation = &"EscBody"
	column.add_child(body)
	var tabs := VBoxContainer.new()
	tabs.theme_type_variation = &"EscTabs"
	body.add_child(tabs)
	for tab: EscMenuState.Tab in TAB_NAMES:
		var button := UiParts.button(TAB_NAMES[tab], press.bind(tab))
		button.theme_type_variation = &"EscTab"
		button.toggle_mode = true
		button.name = TAB_NAMES[tab]
		tab_buttons[tab] = button
		tabs.add_child(button)
	body.add_child(VSeparator.new())
	var pages := ScrollContainer.new()
	pages.custom_minimum_size = PAGE_SIZE
	pages.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(pages)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(stack)
	resume_page.theme_type_variation = &"EscPage"
	resume_page.add_child(_text(RESUME_TEXT))
	stack.add_child(resume_page)
	lobby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(lobby)
	voice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(voice)
	confirm_box.theme_type_variation = &"EscPage"
	warning_label.text = HOST_WARNING
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_box.add_child(warning_label)
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_box.add_child(confirm_label)
	var row := HBoxContainer.new()
	row.add_child(UiParts.button("Yes", confirm))
	row.add_child(UiParts.button("No", cancel))
	confirm_box.add_child(row)
	stack.add_child(confirm_box)
	_sync()


## Opens the menu on `screen`; `model` is the own ClientModel once welcomed (null before).
func open(screen: GameFlow.Screen, model: ClientModel, hosting: bool) -> void:
	state.open(screen, model, hosting)
	_sync()


func close() -> void:
	state.close()
	_sync()


## Opens the menu at the host's question to quit (the window's close button).
func ask_quit(screen: GameFlow.Screen, model: ClientModel) -> void:
	state.ask_quit(screen, model)
	_sync()


func is_open() -> bool:
	return state.is_open


## Follows the game while open; `host_tick` is the newest host tick known (-1: none yet).
func refresh(screen: GameFlow.Screen, model: ClientModel, host_tick: int, hosting: bool) -> void:
	if not state.is_open:
		return
	state.follow(screen, model, hosting)
	if state.selected == EscMenuState.Tab.LOBBY and model != null:
		lobby.refresh(model, host_tick, state.may_change_settings)
	_sync()


## A press on `tab`'s button.
func press(tab: EscMenuState.Tab) -> void:
	var action := state.press(tab)
	_sync()
	_act(action)


## Yes to the host's question.
func confirm() -> void:
	var action := state.confirm()
	_sync()
	_act(action)


## No to the host's question.
func cancel() -> void:
	state.cancel()
	_sync()


## The page that shows now; null while closed.
func page() -> Control:
	if not state.is_open:
		return null
	match state.selected:
		EscMenuState.Tab.LOBBY:
			return lobby
		EscMenuState.Tab.VOICE:
			return voice
		EscMenuState.Tab.LEAVE, EscMenuState.Tab.QUIT:
			return confirm_box
	return resume_page


func _act(action: EscMenuState.Action) -> void:
	match action:
		EscMenuState.Action.RESUME:
			resume_requested.emit()
		EscMenuState.Action.LEAVE:
			leave_requested.emit()
		EscMenuState.Action.QUIT:
			quit_requested.emit()


## Draws the state: the tabs that exist, the selected one pressed, its page alone.
func _sync() -> void:
	visible = state.is_open
	for tab: EscMenuState.Tab in tab_buttons:
		var button := tab_buttons[tab]
		button.visible = state.has_tab(tab)
		button.set_pressed_no_signal(state.selected == tab)
	var shown := page()
	for each: Control in [resume_page, lobby, voice, confirm_box]:
		each.visible = each == shown
	if state.asking():
		var what := TAB_NAMES[state.selected]
		confirm_label.text = "%s, and end the session for every player?" % what


static func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
