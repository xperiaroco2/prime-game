class_name EscMenu
extends Control
## Esc's menu (ARCHITECTURE §4.7, #169): the suit menu as the left side panel, built node for node
## from prime-game-ui's handoff s05 at ui-2.5.4 (#1571, the engineer's side panel of 2026-10-22):
## no dim and no pause, the world visible beside it. `Menu` (full rect, the mouse passes) holds:
## - `Side` (ToyPanelMenu, the left edge, 36 px in, 520 wide, full height): `V` > `Head` (in the
##   lobby: the room's code with Copy; hidden with no code and in a round), `Entries` (Resume, then
##   one ToyMenuItem per page: Guide, Lobby, Settings), `Gap`, `Rule` (the hairline) and `Bottom`
##   (Leave, Quit).
## - `Page` (ToyPanelMenu, 24 px right of the panel, 1120 wide): the open entry's page, one at a
##   time: GuidePanel (#254), LobbyPanel (Ready and the match settings: the plainest stand-in until
##   the ship's match console, s04, #1285) or SettingsPage; hidden while none is open.
## The host's question is the confirm dialog over the menu: ConfirmDim and Confirm, the menu behind
## unreachable by focus (focus_behavior_recursive) and Cancel focused; Esc closes only the dialog
## (GameUi's `esc_dialog` overlay, #488). What it shows and does is EscMenuState's; this draws it.

signal resume_requested
signal leave_requested
signal quit_requested
## The ship's Host: a game with a code (#1285).
signal host_requested
## The ship's Tutorial.
signal tutorial_requested

## Each page's entry: its node name and deck key, in the panel's order.
const TABS: Dictionary[EscMenuState.Tab, Array] = {
	EscMenuState.Tab.FIND: ["Find", "esc.tab.find"],
	EscMenuState.Tab.GUIDE: ["Guide", "esc.tab.guide"],
	EscMenuState.Tab.LOBBY: ["Lobby", "esc.tab.lobby"],
	EscMenuState.Tab.SETTINGS: ["Settings", "esc.tab.settings"],
}
## Places in px at the 1920x1080 base (the handoff's; layout, not style): the panel's offsets
## (left, top, right, bottom on the left_wide preset), the page's left and top and width, the
## dialog's and its texts' widths.
const SIDE_OFFSETS := Vector4(36, 36, 556, -36)
const PAGE_AT := Vector2(580, 36)
const PAGE_WIDTH := 1120.0
const DIALOG_WIDTH := Vector2(1080, 0)
const DIALOG_TEXT_WIDTH := Vector2(900, 0)
const LOCK_SIZE := Vector2(20, 20)
const LOCK := preload("res://assets/ui/toy_pack/icons/lock.svg")
const HOST_ONLY_KEY := "esc.lobby.host_only"
## How long Copy reads "Copied" (s05's head, as the Lobby page's).
const COPIED_SECONDS := 2.0
## The head's code while the code service has not made the room (s05).
const CODE_WAITING := "…"

var state := EscMenuState.new()
## The full-rect root and the side panel.
var menu := Control.new()
var side := PanelContainer.new()
## The panel's head: the room's code and Copy.
var head := PanelContainer.new()
var code_label := UiParts.styled_label("", &"ToyTextOnLight")
var copy_button := Button.new()
var tab_buttons: Dictionary[EscMenuState.Tab, Button] = {}
var resume_button := Button.new()
## The ship's Host and Tutorial (s05 `ship`), between Find and Guide.
var host_button := Button.new()
var tutorial_button := Button.new()
var leave_button := Button.new()
var quit_button := Button.new()
## The open entry's page tile.
var page_tile := PanelContainer.new()
## Over the Lobby page: the host's note, or the line that only the host changes the settings (the
## console's HostNote and lock line, s04, while the page stands in for it).
var host_row := HBoxContainer.new()
var host_note := UiParts.styled_label("esc.lobby.you_host", &"ToyTextMutedOnLight")
var host_only := HBoxContainer.new()
var host_only_label := UiParts.styled_label("", &"ToyTextMutedOnLight")
var find := FindPage.new()
var guide := GuidePanel.new(ToyHints.LIGHT)
var lobby := LobbyPanel.new()
var settings := SettingsPage.new()
## The Settings page's Sound and voice and Controls (the game feeds them).
var voice: VoicePanel = settings.voice
var controls: ControlsPanel = settings.controls
## The confirm dialog: its dim and its panel.
var confirm_dim := Panel.new()
var confirm_box := PanelContainer.new()
var confirm_title := UiParts.styled_label("", &"ToyTitleOnLight")
var confirm_body := UiParts.styled_label("esc.game.leave_host_note", &"ToyTextMutedOnLight")
var confirm_button := Button.new()
var cancel_button := Button.new()

## The room's code Copy copies ("" for none), and what the head shows: the code, "…" while the
## code service has not made the room ("" hides the head: no code, a Direct game, the service gone).
var _code := ""
var _head_text := ""
var _copied_timer: SceneTreeTimer
## The last model the menu was given: the host's name of the host-only line.
var _model: ClientModel


func _init() -> void:
	name = "EscMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.name = "Menu"
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A click on the world beside the panel reaches nothing and closes nothing (Esc and Resume do).
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu)
	_build_side()
	_build_page()
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
	_hide_lists()


## An open dropdown list is a window of its own, not part of the menu's drawing: closing the menu
## closes it too, whatever closes the menu (a new screen, #726, or Resume).
func _hide_lists() -> void:
	for node: Node in find_children("*", "OptionButton", true, false):
		(node as OptionButton).get_popup().hide()


## Opens the menu at the host's question to quit (the window's close button); the tutorial quits
## at once.
func ask_quit(screen: GameFlow.Screen, model: ClientModel) -> void:
	_model = model
	var action := state.ask_quit(screen, model)
	_sync()
	_focus()
	_act(action)


func is_open() -> bool:
	return state.is_open


## Follows the game while open; `host_tick` is the newest host tick known (-1: none yet). `mode`
## is unused, kept for the callers' signature (the Role tab went with #1571).
func refresh(
	screen: GameFlow.Screen,
	model: ClientModel,
	host_tick: int,
	hosting: bool,
	_mode: GameMode = null,
) -> void:
	if not state.is_open:
		return
	_model = model
	var before := state.selected
	state.follow(screen, model, hosting)
	if state.selected == EscMenuState.Tab.LOBBY and model != null:
		lobby.refresh(model, host_tick, state.may_change_settings, state.in_round)
	if model != null:
		# The Guide's task cards follow the picked or the match's map (DE16).
		guide.set_map(model.map)
	_sync()
	if state.selected != before:
		_focus()


## The room's code for the head (s05 `lobby`: the code and Copy) and the Lobby page: `line` the
## page's words for it (JoinProgress.code_text), `code` the code itself ("" for none).
func show_code(line: String, code: String) -> void:
	var gone := line == JoinProgress.CODE_GONE
	var waiting := line == JoinProgress.CODE_WAITING
	_code = "" if gone or waiting else code
	_head_text = CODE_WAITING if waiting else _code
	code_label.text = _head_text
	copy_button.visible = not _code.is_empty()
	lobby.show_code(line, code)
	_sync()


## Closes the open page, the panel staying (s05: Esc with a page open closes the page); its
## entry takes the focus back. Find's address entry closes first (its Back).
func close_page() -> void:
	if state.selected == EscMenuState.Tab.FIND and find.direct_open():
		find.show_direct(false)
		return
	var open := state.selected
	if not tab_buttons.has(open):
		return
	state.press(open)
	_sync()
	if is_inside_tree():
		tab_buttons[open].grab_focus.call_deferred(true)


## Whether an entry's page is open beside the panel.
func page_open() -> bool:
	return page() != null


## A press on `tab`'s entry: its page opens beside the panel, or closes on a second press.
func press(tab: EscMenuState.Tab) -> void:
	state.press(tab)
	_sync()


## Resume (and Esc on the menu): the menu closes.
func resume() -> void:
	var action := state.resume()
	_sync()
	_act(action)


## Leave on the panel.
func press_leave() -> void:
	var action := state.press_leave()
	_sync()
	_act(action)
	if state.asking():
		cancel_button.grab_focus.call_deferred()


## Quit on the panel.
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


## No to the host's question: the entry that asked takes the focus back.
func cancel() -> void:
	var asked := state.question
	state.cancel()
	_sync()
	if is_inside_tree() and asked != EscMenuState.Action.NONE:
		(leave_button if asked == EscMenuState.Action.LEAVE else quit_button).grab_focus()


## The page that shows now; null while closed or with no page open.
func page() -> Control:
	if not state.is_open:
		return null
	return _pages().get(state.selected)


func _pages() -> Dictionary[EscMenuState.Tab, Control]:
	return {
		EscMenuState.Tab.FIND: find,
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


## Draws the state: the entries that exist, the open one pressed, its page alone, the head and the
## dialog.
func _sync() -> void:
	visible = state.is_open
	for tab: EscMenuState.Tab in tab_buttons:
		var button := tab_buttons[tab]
		button.visible = state.has_tab(tab)
		button.set_pressed_no_signal(state.selected == tab)
	var shown := page()
	var pages := _pages()
	for tab: EscMenuState.Tab in pages:
		pages[tab].visible = pages[tab] == shown
	page_tile.visible = shown != null
	var lobby_page := state.selected == EscMenuState.Tab.LOBBY
	host_note.visible = lobby_page and state.may_change_settings
	host_only.visible = lobby_page and state.in_lobby and not state.hosting
	host_row.visible = host_note.visible or host_only.visible
	_retext()
	# The head: the room's code in the lobby (none in a round, the tutorial, the own ship or a
	# Direct game).
	var private := state.tutorial or state.ship
	head.visible = state.in_lobby and not private and not _head_text.is_empty()
	leave_button.text = "esc.game.leave_tutorial" if state.tutorial else "esc.game.leave"
	# The ship with no session: nothing to resume or leave; its own Host and Tutorial.
	resume_button.visible = not state.ship
	leave_button.visible = not state.ship
	host_button.visible = state.ship
	tutorial_button.visible = state.ship
	# Not in the tutorial: leave it first (s05 `tutorial`); the window's close still quits.
	quit_button.visible = not state.tutorial
	var asking := state.asking()
	confirm_dim.visible = asking
	confirm_box.visible = asking
	menu.focus_behavior_recursive = (
		Control.FOCUS_BEHAVIOR_DISABLED if asking else Control.FOCUS_BEHAVIOR_INHERITED
	)
	var quitting := state.question == EscMenuState.Action.QUIT
	confirm_title.text = "esc.game.quit_confirm" if quitting else "esc.game.leave_confirm"
	confirm_button.text = "esc.game.quit" if quitting else "esc.game.leave"


## The focus on opening: Cancel under the question, else Resume with its ring hidden until an
## arrow or the d-pad moves it (s05: the mouse's view draws no ring).
func _focus() -> void:
	if not is_inside_tree() or not state.is_open:
		return
	if state.asking():
		cancel_button.grab_focus.call_deferred()
	elif resume_button.visible:
		resume_button.grab_focus.call_deferred(true)
	else:
		tab_buttons[EscMenuState.Tab.FIND].grab_focus.call_deferred(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and host_only_label != null:
		_retext()


## The host-only line: the deck's words with the host's name (data).
func _retext() -> void:
	var host := _model.host_name() if _model != null else ""
	host_only_label.text = tr(HOST_ONLY_KEY).format({"name": host})


func _build_side() -> void:
	side.name = "Side"
	side.theme_type_variation = &"ToyPanelMenu"
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_left = SIDE_OFFSETS.x
	side.offset_top = SIDE_OFFSETS.y
	side.offset_right = SIDE_OFFSETS.z
	side.offset_bottom = SIDE_OFFSETS.w
	side.grow_horizontal = Control.GROW_DIRECTION_END
	side.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.add_child(side)
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnSixteen"
	side.add_child(column)
	column.add_child(_build_head())
	var entries := VBoxContainer.new()
	entries.name = "Entries"
	entries.theme_type_variation = &"ToyColumnFour"
	column.add_child(entries)
	_item(resume_button, "Resume", "esc.game.resume", resume)
	entries.add_child(resume_button)
	for tab: EscMenuState.Tab in TABS:
		var button := Button.new()
		_item(button, str(TABS[tab][0]), str(TABS[tab][1]), press.bind(tab))
		button.toggle_mode = true
		tab_buttons[tab] = button
		entries.add_child(button)
		if tab == EscMenuState.Tab.FIND:
			_item(host_button, "Host", "menu.host", host_requested.emit)
			entries.add_child(host_button)
			_item(tutorial_button, "Tutorial", "menu.tutorial", tutorial_requested.emit)
			entries.add_child(tutorial_button)
	var gap := Control.new()
	gap.name = "Gap"
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	var rule := PanelContainer.new()
	rule.name = "Rule"
	rule.theme_type_variation = &"ToySettingRow"
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var bottom := VBoxContainer.new()
	bottom.name = "Bottom"
	bottom.theme_type_variation = &"ToyColumnFour"
	column.add_child(bottom)
	_item(leave_button, "Leave", "esc.game.leave", press_leave)
	bottom.add_child(leave_button)
	_item(quit_button, "Quit", "esc.game.quit", press_quit)
	bottom.add_child(quit_button)


## The head (s05 `lobby`): `common.code` in small capitals over the code and Copy.
func _build_head() -> PanelContainer:
	head.name = "Head"
	head.theme_type_variation = &"ToySettingRow"
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnEight"
	head.add_child(column)
	var label := UiParts.styled_label("common.code", &"ToyKicker")
	label.name = "Label"
	label.uppercase = true
	column.add_child(label)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.theme_type_variation = &"ToyRowTwelve"
	column.add_child(row)
	code_label.name = "Value"
	code_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(code_label)
	copy_button.name = "Copy"
	copy_button.text = "esc.lobby.copy"
	copy_button.theme_type_variation = &"ToyButtonSecondary"
	copy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy_button.pressed.connect(_copy)
	ToyPress.attach(copy_button)
	row.add_child(copy_button)
	return head


func _copy() -> void:
	DisplayServer.clipboard_set(_code)
	copy_button.text = "esc.lobby.copied"
	if is_inside_tree():
		var timer := get_tree().create_timer(COPIED_SECONDS)
		_copied_timer = timer
		timer.timeout.connect(_end_copied.bind(timer))


## Takes the "Copied" text back, unless a later press started a timer of its own.
func _end_copied(timer: SceneTreeTimer) -> void:
	if timer == _copied_timer:
		copy_button.text = "esc.lobby.copy"


func _build_page() -> void:
	page_tile.name = "Page"
	page_tile.theme_type_variation = &"ToyPanelMenu"
	page_tile.set_anchors_preset(Control.PRESET_TOP_LEFT)
	page_tile.offset_left = PAGE_AT.x
	page_tile.offset_top = PAGE_AT.y
	page_tile.offset_right = PAGE_AT.x
	page_tile.offset_bottom = PAGE_AT.y
	page_tile.grow_horizontal = Control.GROW_DIRECTION_END
	page_tile.grow_vertical = Control.GROW_DIRECTION_END
	page_tile.custom_minimum_size = Vector2(PAGE_WIDTH, 0)
	menu.add_child(page_tile)
	var pages := VBoxContainer.new()
	pages.name = "V"
	pages.theme_type_variation = &"ToyColumnSixteen"
	page_tile.add_child(pages)
	host_row.name = "HostRow"
	host_row.theme_type_variation = &"ToyRowSixteen"
	pages.add_child(host_row)
	host_note.name = "HostNote"
	host_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host_row.add_child(host_note)
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
	host_row.add_child(host_only)
	for each: Control in [find, guide, lobby, settings]:
		pages.add_child(each)


func _build_confirm() -> void:
	confirm_dim.name = "ConfirmDim"
	confirm_dim.theme_type_variation = &"ToyBackdrop"
	confirm_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(confirm_dim)
	confirm_box.name = "Confirm"
	confirm_box.theme_type_variation = &"ToyPanelDialog"
	confirm_box.set_anchors_preset(Control.PRESET_CENTER)
	confirm_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	confirm_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	confirm_box.custom_minimum_size = DIALOG_WIDTH
	add_child(confirm_box)
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnThirtyTwo"
	confirm_box.add_child(column)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.theme_type_variation = &"ToyColumnSixteen"
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
	buttons.theme_type_variation = &"ToyRowTwentyFour"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	confirm_button.name = "ConfirmButton"
	confirm_button.text = "esc.game.leave"
	confirm_button.theme_type_variation = &"ToyButtonDanger"
	confirm_button.pressed.connect(confirm)
	ToyPress.attach(confirm_button)
	buttons.add_child(confirm_button)
	cancel_button.name = "Cancel"
	cancel_button.text = "common.cancel"
	cancel_button.theme_type_variation = &"ToyButtonGhostOnLight"
	cancel_button.pressed.connect(cancel)
	ToyPress.attach(cancel_button)
	buttons.add_child(cancel_button)


## A panel entry: a ToyMenuItem named `node_name`, its deck key `key`, left-aligned.
static func _item(button: Button, node_name: String, key: String, pressed: Callable) -> void:
	button.name = node_name
	button.text = key
	button.theme_type_variation = &"ToyMenuItem"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(pressed)
	ToyPress.attach(button)
