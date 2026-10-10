class_name EscMenu
extends Control
## Esc's menu (ARCHITECTURE §4.7, #169), in the Toy style of #491: built node for node from
## prime-game-ui's handoff s05 at ui-0.4.0 (the differences are listed in #491's PR). Dim (the
## running game dimmed), then Menu, a raised 1600x880 ToyPanelMenu: Tabs on the left (ToyTab
## toggles in one ButtonGroup) and Page on the right, the title row (the selected tab's name; the
## host's note or a player's host-only line on the Lobby tab) above one page per tab:
## - Game (Actions): Resume, Leave (the host's coral, asking first), Quit.
## - Role (RolePage, the round only): the own role, its goal, a dissident's team (RoleFacts).
## - Guide (GuidePanel, #254): every how-to card.
## - Lobby (LobbyPanel, the lobby screen only): the roster, Ready and the match settings.
## - Settings (SettingsPage, #491): Sound and voice, Controls, Display, Accessibility, Language.
## The host's question is the confirm dialog over the menu: ConfirmDim and Confirm, the menu behind
## unreachable by focus (focus_behavior_recursive) and Cancel focused; Esc closes only the dialog
## (GameUi's `esc_dialog` overlay, #488). What it shows and does is EscMenuState's; this draws it.

signal resume_requested
signal leave_requested
signal quit_requested

## Each tab's button: its node name and deck key.
const TABS: Dictionary[EscMenuState.Tab, Array] = {
	EscMenuState.Tab.GAME: ["Game", "esc.tab.game"],
	EscMenuState.Tab.ROLE: ["Role", "esc.tab.role"],
	EscMenuState.Tab.GUIDE: ["Guide", "esc.tab.guide"],
	EscMenuState.Tab.LOBBY: ["Lobby", "esc.tab.lobby"],
	EscMenuState.Tab.SETTINGS: ["Settings", "esc.tab.settings"],
}
## Sizes in px at the 1920x1080 base (the handoff's; layout, not style).
const MENU_SIZE := Vector2(1600, 880)
const TABS_WIDTH := Vector2(288, 0)
const ACTIONS_WIDTH := Vector2(760, 0)
const DIALOG_WIDTH := Vector2(720, 0)
const DIALOG_TEXT_WIDTH := Vector2(600, 0)
const LOCK_SIZE := Vector2(20, 20)
const LOCK := preload("res://assets/ui/toy_pack/icons/lock.svg")
const HOST_ONLY_KEY := "esc.lobby.host_only"

var state := EscMenuState.new()
## The raised Menu (its ToyRaised wrapper) and its face.
var menu: ToyRaised
var tab_buttons: Dictionary[EscMenuState.Tab, Button] = {}
var title_label := UiParts.styled_label("", &"ToyTitleOnLight")
var host_note := UiParts.styled_label("esc.lobby.you_host", &"ToyTextMutedOnLight")
var host_only := HBoxContainer.new()
var host_only_label := UiParts.styled_label("", &"ToyTextMutedOnLight")
## The Game page.
var actions := VBoxContainer.new()
var resume_button: Button
var leave_button: Button
var quit_button := Button.new()
var role := RolePage.new()
var guide := GuidePanel.new(ToyHints.LIGHT)
var lobby := LobbyPanel.new()
var settings := SettingsPage.new()
## The Settings page's Sound and voice and Controls (the game feeds them).
var voice: VoicePanel = settings.voice
var controls: ControlsPanel = settings.controls
## The confirm dialog: its dim and its raised panel (the wrapper).
var confirm_dim := Panel.new()
var confirm_box: ToyRaised
var confirm_title := UiParts.styled_label("", &"ToyTitleOnLight")
var confirm_body := UiParts.styled_label("esc.game.leave_host_note", &"ToyTextMutedOnLight")
var confirm_button: Button
var cancel_button := Button.new()

## The last model the menu was given: the host's name of the host-only line.
var _model: ClientModel


func _init() -> void:
	name = "EscMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiParts.backdrop(self, &"ToyBackdropDeep").name = "Dim"
	var face := PanelContainer.new()
	face.name = "Menu"
	face.theme_type_variation = &"ToyPanelMenu"
	menu = UiParts.raised(face, ToyHints.DARK)
	_center(menu, MENU_SIZE)
	add_child(menu)
	var body := HBoxContainer.new()
	body.name = "H"
	body.theme_type_variation = &"ToyRowTwentyFour"
	face.add_child(body)
	body.add_child(_build_tabs())
	body.add_child(_build_page())
	_build_confirm()
	_sync()


## Opens the menu on `screen`; `model` is the own ClientModel once welcomed (null before).
func open(screen: GameFlow.Screen, model: ClientModel, hosting: bool) -> void:
	_model = model
	state.open(screen, model, hosting)
	_sync()
	_focus()


func close() -> void:
	state.close()
	_sync()


## Opens the menu on Game at the host's question to quit (the window's close button); the
## tutorial quits at once.
func ask_quit(screen: GameFlow.Screen, model: ClientModel) -> void:
	_model = model
	var action := state.ask_quit(screen, model)
	_sync()
	_focus()
	_act(action)


func is_open() -> bool:
	return state.is_open


## Follows the game while open; `host_tick` is the newest host tick known (-1: none yet); `mode`
## names the own role on the Role page.
func refresh(
	screen: GameFlow.Screen,
	model: ClientModel,
	host_tick: int,
	hosting: bool,
	mode: GameMode = null,
) -> void:
	if not state.is_open:
		return
	_model = model
	var before := state.selected
	state.follow(screen, model, hosting)
	if state.selected == EscMenuState.Tab.LOBBY and model != null:
		lobby.refresh(model, host_tick, state.may_change_settings, state.in_round)
	if state.selected == EscMenuState.Tab.ROLE:
		role.show_facts(RoleFacts.of(model, mode))
	_sync()
	if state.selected != before:
		_focus()


## A press on `tab`'s button.
func press(tab: EscMenuState.Tab) -> void:
	state.press(tab)
	_sync()


## Resume (and Esc on the menu): the menu closes.
func resume() -> void:
	var action := state.resume()
	_sync()
	_act(action)


## Leave on the Game page.
func press_leave() -> void:
	var action := state.press_leave()
	_sync()
	_act(action)
	if state.asking():
		cancel_button.grab_focus.call_deferred()


## Quit on the Game page.
func press_quit() -> void:
	var action := state.press_quit()
	_sync()
	_act(action)
	if state.asking():
		cancel_button.grab_focus.call_deferred()


## Yes to the host's question.
func confirm() -> void:
	var action := state.confirm()
	_sync()
	_act(action)


## No to the host's question: the button that asked takes the focus back.
func cancel() -> void:
	var asked := state.question
	state.cancel()
	_sync()
	if is_inside_tree() and asked != EscMenuState.Action.NONE:
		(leave_button if asked == EscMenuState.Action.LEAVE else quit_button).grab_focus()


## The page that shows now; null while closed.
func page() -> Control:
	if not state.is_open:
		return null
	return _pages()[state.selected]


func _pages() -> Dictionary[EscMenuState.Tab, Control]:
	return {
		EscMenuState.Tab.GAME: actions,
		EscMenuState.Tab.ROLE: role,
		EscMenuState.Tab.GUIDE: guide,
		EscMenuState.Tab.LOBBY: lobby,
		EscMenuState.Tab.SETTINGS: settings,
	}


func _act(action: EscMenuState.Action) -> void:
	match action:
		EscMenuState.Action.RESUME:
			resume_requested.emit()
		EscMenuState.Action.LEAVE:
			leave_requested.emit()
		EscMenuState.Action.QUIT:
			quit_requested.emit()


## Draws the state: the tabs that exist, the selected one pressed, its page alone, the title row,
## the Game page's looks and the dialog.
func _sync() -> void:
	visible = state.is_open
	for tab: EscMenuState.Tab in tab_buttons:
		var button := tab_buttons[tab]
		button.visible = state.has_tab(tab)
		SettingRows.set_pressed(button, state.selected == tab)
	var shown := page()
	var pages := _pages()
	for tab: EscMenuState.Tab in pages:
		pages[tab].visible = pages[tab] == shown
	title_label.text = str(TABS[state.selected][1])
	var lobby_tab := state.selected == EscMenuState.Tab.LOBBY and state.in_lobby
	host_note.visible = lobby_tab and state.may_change_settings
	host_only.visible = lobby_tab and not state.hosting
	_retext()
	var host_leave := state.hosting and not state.tutorial
	leave_button.theme_type_variation = &"ToyButtonDanger" if host_leave else &"ToyButtonSecondary"
	leave_button.text = "esc.game.leave_tutorial" if state.tutorial else "esc.game.leave"
	var asking := state.asking()
	confirm_dim.visible = asking
	confirm_box.visible = asking
	menu.focus_behavior_recursive = (
		Control.FOCUS_BEHAVIOR_DISABLED if asking else Control.FOCUS_BEHAVIOR_INHERITED
	)
	var quitting := state.question == EscMenuState.Action.QUIT
	confirm_title.text = "esc.game.quit_confirm" if quitting else "esc.game.leave_confirm"
	confirm_button.text = "esc.game.quit" if quitting else "esc.game.leave"


## The focus on opening: Cancel under the question, Resume on Game, else the selected tab.
func _focus() -> void:
	if not is_inside_tree() or not state.is_open:
		return
	if state.asking():
		cancel_button.grab_focus.call_deferred()
	elif state.selected == EscMenuState.Tab.GAME:
		resume_button.grab_focus.call_deferred()
	else:
		tab_buttons[state.selected].grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and host_only_label != null:
		_retext()


## The host-only line: the deck's words with the host's name (data).
func _retext() -> void:
	var host := _model.host_name() if _model != null else ""
	host_only_label.text = tr(HOST_ONLY_KEY).format({"name": host})


func _build_tabs() -> VBoxContainer:
	var tabs := VBoxContainer.new()
	tabs.name = "Tabs"
	tabs.theme_type_variation = &"ToyColumnEight"
	tabs.custom_minimum_size = TABS_WIDTH
	var group := ButtonGroup.new()
	for tab: EscMenuState.Tab in TABS:
		var button := UiParts.toggle(str(TABS[tab][1]), press.bind(tab), &"ToyTab")
		button.name = str(TABS[tab][0])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.button_group = group
		tab_buttons[tab] = button
		tabs.add_child(button)
	return tabs


func _build_page() -> VBoxContainer:
	var page_box := VBoxContainer.new()
	page_box.name = "Page"
	page_box.theme_type_variation = &"ToyColumnSixteen"
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.theme_type_variation = &"ToyRowSixteen"
	page_box.add_child(title_row)
	title_label.name = "Title"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	host_note.name = "HostNote"
	host_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(host_note)
	host_only.name = "HostOnly"
	host_only.theme_type_variation = &"ToyRowEight"
	host_only.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lock := TextureRect.new()
	lock.name = "Lock"
	lock.texture = LOCK
	lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock.custom_minimum_size = LOCK_SIZE
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock.theme_changed.connect(
		func() -> void:
			lock.self_modulate = lock.get_theme_color(&"font_color", &"ToyTextMutedOnLight")
	)
	host_only.add_child(lock)
	host_only_label.name = "Text"
	host_only_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	host_only.add_child(host_only_label)
	title_row.add_child(host_only)
	page_box.add_child(_build_actions())
	page_box.add_child(role)
	guide.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_box.add_child(guide)
	lobby.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_box.add_child(lobby)
	page_box.add_child(settings)
	return page_box


func _build_actions() -> VBoxContainer:
	actions.name = "Actions"
	actions.theme_type_variation = &"ToyColumnSixteen"
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	actions.custom_minimum_size = ACTIONS_WIDTH
	var resume_raised := UiParts.button(
		"esc.game.resume", resume, &"ToyButtonPrimary", ToyHints.LIGHT
	)
	resume_raised.name = "ResumeRaised"
	resume_button = resume_raised.face as Button
	resume_button.name = "Resume"
	actions.add_child(resume_raised)
	var leave_raised := UiParts.button(
		"esc.game.leave", press_leave, &"ToyButtonDanger", ToyHints.LIGHT
	)
	leave_raised.name = "LeaveRaised"
	leave_button = leave_raised.face as Button
	leave_button.name = "Leave"
	actions.add_child(leave_raised)
	_ghost(quit_button, "Quit", "esc.game.quit", press_quit)
	actions.add_child(quit_button)
	return actions


func _build_confirm() -> void:
	confirm_dim.name = "ConfirmDim"
	confirm_dim.theme_type_variation = &"ToyBackdrop"
	confirm_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(confirm_dim)
	var face := PanelContainer.new()
	face.name = "Confirm"
	face.theme_type_variation = &"ToyPanelDialog"
	confirm_box = UiParts.raised(face, ToyHints.DARK)
	_center(confirm_box, DIALOG_WIDTH)
	add_child(confirm_box)
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnThirtyTwo"
	face.add_child(column)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.theme_type_variation = &"ToyColumnTwelve"
	column.add_child(text)
	for label: Label in [confirm_title, confirm_body]:
		label.custom_minimum_size = DIALOG_TEXT_WIDTH
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(label)
	confirm_title.name = "Title"
	confirm_body.name = "Body"
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.theme_type_variation = &"ToyRowSixteen"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	var confirm_raised := UiParts.button(
		"esc.game.leave", confirm, &"ToyButtonDanger", ToyHints.LIGHT
	)
	confirm_raised.name = "ConfirmButtonRaised"
	confirm_button = confirm_raised.face as Button
	confirm_button.name = "ConfirmButton"
	buttons.add_child(confirm_raised)
	_ghost(cancel_button, "Cancel", "common.cancel", cancel)
	buttons.add_child(cancel_button)


## A flat ghost button on the light panel.
static func _ghost(button: Button, node_name: String, key: String, pressed: Callable) -> void:
	button.name = node_name
	button.text = key
	button.theme_type_variation = &"ToyButtonGhostOnLight"
	button.pressed.connect(pressed)
	ToyPress.attach(button)


## `control` centred on the screen, at least `at_least` big (its size grows both ways).
static func _center(control: Control, at_least: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_CENTER)
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH
	control.custom_minimum_size = at_least
