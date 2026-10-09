class_name MainMenu
extends Control
## The main menu (prime-game-ui's s2 handoff at ui-0.4.0, #493; ARCHITECTURE §4.7.38), node for
## node as drawn: the dim Backdrop, then Column (the logo, the own name, and Body: the Items and
## the open panel to their right), the Settings panel, a root of its own, and the Version.
## - Items: Host (a game with a code), Join, Join by address (Direct), Tutorial, Settings, Quit.
##   Join, Direct and Settings are one ButtonGroup with allow_unpress: pressing one opens its
##   panel, pressing it again, Back or Esc (GameUi's `menu_panel` overlay, #488) closes it and
##   gives the focus back to the item. Focus starts on Host.
## - CodePanel: the code field (only the code alphabet, upper case, at most 6), Join once it holds
##   a whole code, Enter = Join. DirectPanel: the host's address[:port], Join once it parses
##   (JoinTarget), Host on the port typed or the default, the default port's line.
## - SettingsPanel holds the settings (`settings_page`): the SettingsPage of #491, the scene the
##   Esc menu's Settings tab has too, opened on Sound and voice; focus starts on its sub-page chip.
## - The name row binds to UserSettings.player_name (bind_name): kept between sessions, cleaned by
##   PlayerNames; an empty field keeps the name there was.
## Every text is a deck key; the version, the port line and the data texts (the logo, the name,
## the code, the address) are set from code with `auto_translate_mode` DISABLED, the keyed ones
## rebuilt on NOTIFICATION_TRANSLATION_CHANGED. The game connects the signals.

signal code_join_requested(code: String)
signal code_host_requested
signal host_requested(port: int)
signal join_requested(address: String, port: int)
signal quit_requested
## Tutorial: Game starts the solo tutorial on it (#601); the item stays disabled until #492.
signal tutorial_requested

## The panel open to the right of the items (or, Settings, in its own root).
enum Open { NONE, CODE, DIRECT, SETTINGS }

## The working title, a text from data (the handoff's Logo).
const LOGO := "prime-game"
## The places and widths of the handoff (px at the 1920x1080 base, #287).
const COLUMN_PLACE := Vector2(136, 256)
const ITEMS_WIDTH := 592.0
const GAP_WIDTH := 64.0
const PANEL_WIDTH := 784.0
const SETTINGS_RECT := Rect2(856, 96, 960, 888)
const VERSION_INSET := 40.0
## The items' icon: the pack's white pointer.svg (own work), #520's imported copy at the pack's
## svg_scale 1 (24 px, as the handoff's notes give), through ToyIcons; tinted by ToyMenuItem.
const POINTER := &"pointer"

## The panel open now.
var open := Open.NONE
## The port a Direct address without one takes, and Host by code hosts on (the launch options').
var default_port := LaunchOptions.DEFAULT_PORT

var backdrop := Panel.new()
var column := VBoxContainer.new()
var logo := Label.new()
var name_row := HBoxContainer.new()
var name_edit := LineEdit.new()
var body := HBoxContainer.new()
var items := VBoxContainer.new()
var host_item: Button
var join_item: Button
var direct_item: Button
var tutorial_item: Button
var settings_item: Button
var quit_item: Button
var item_group := ButtonGroup.new()
## The empty spacer between the items and an open panel (shown with any panel in Body).
var gap := Control.new()
var code_panel: ToyRaised
var code_edit := LineEdit.new()
var code_join: ToyRaised
var code_back := Button.new()
var direct_panel: ToyRaised
var address_edit := LineEdit.new()
var port_label := Label.new()
var direct_join: ToyRaised
var direct_host: ToyRaised
var direct_back := Button.new()
var settings_panel: ToyRaised
## What the Settings panel holds: the Settings scene the Esc menu has too (#491).
var settings_page := SettingsPage.new()
## Its Sound and voice (#301); the game feeds it.
var voice: VoicePanel = settings_page.voice
var version_label := Label.new()

## The settings the name row binds to (bind_name); null shows and keeps nothing.
var _settings: UserSettings
## What a full code field turned away (text_change_rejected), taken in once the insert is done.
var _rejected := ""


func _init() -> void:
	name = "MainMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.name = "Backdrop"
	backdrop.theme_type_variation = &"ToyBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	backdrop.grow_vertical = Control.GROW_DIRECTION_BOTH
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_build_column()
	_build_settings_panel()
	version_label.name = "Version"
	version_label.theme_type_variation = &"ToyTextMutedOnDark"
	version_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	version_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_place(version_label, Vector2(-VERSION_INSET, -VERSION_INSET), Control.GROW_DIRECTION_BEGIN)
	add_child(version_label)
	retext()
	_show(Open.NONE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		retext()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_focus.call_deferred()


## The name row shows and keeps `settings`' player_name (#550): each change is cleaned and saved;
## a field left empty shows the name kept.
func bind_name(settings: UserSettings) -> void:
	_settings = settings
	name_edit.text = settings.player_name


## Opens `which` as its item would: the code field emptied (`fresh`) and focused, the address
## focused, Settings on its first control. A failure's Back keeps the panel and what was typed.
func open_panel(which: Open, fresh := true) -> void:
	if which == Open.CODE and fresh:
		code_edit.text = ""
	_show(which)
	_focus.call_deferred()


## Closes the open panel; the focus goes back to its item.
func close_panel() -> void:
	var item := _item_of(open)
	_show(Open.NONE)
	if item != null and is_visible_in_tree():
		item.grab_focus()


## The Direct panel with the address focused (a failure's Join directly), the code kept.
func open_direct() -> void:
	open_panel(Open.DIRECT)


func settings_open() -> bool:
	return open == Open.SETTINGS


## Whether a panel is open, the code, Direct or Settings one: the `menu_panel` overlay Esc closes
## (GameUi, #488 rule 2).
func panel_open() -> bool:
	return open != Open.NONE


## The state as the handoff names it: main, code, code-ready, direct or settings.
func state() -> StringName:
	match open:
		Open.CODE:
			return &"code-ready" if SignalCodec.is_code(code_edit.text) else &"code"
		Open.DIRECT:
			return &"direct"
		Open.SETTINGS:
			return &"settings"
	return &"main"


## `typed` as the code field keeps it: upper case, only the code alphabet (no spaces, dashes, 0,
## O, 1, I or L), at most SignalCodec.CODE_LENGTH characters.
static func code_text(typed: String) -> String:
	var kept := ""
	for character: String in typed.to_upper():
		if SignalCodec.CODE_ALPHABET.contains(character):
			kept += character
	return kept.left(SignalCodec.CODE_LENGTH)


## The port Direct's Host hosts on: the one typed after the address, else `fallback`; -1 when
## the typed port is not one (Host is off then, not quietly on `fallback`).
static func typed_port(typed: String, fallback: int) -> int:
	var target := JoinTarget.of_direct(typed, fallback)
	return -1 if target.port_problem else target.port


## Every text set from code again, in the language now.
func retext() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	version_label.text = _word("menu.version").format({"version": version})
	# Until project.godot names the version, nothing is shown (no made-up number).
	version_label.visible = not version.is_empty()
	port_label.text = _word("join.port").format({"port": default_port})


## The port line follows `port` (the launch options' default).
func set_default_port(port: int) -> void:
	default_port = port
	retext()


## The buttons as the fields allow: Join a whole code or an address that parses, Host a port
## that parses or none.
func refresh_buttons() -> void:
	(code_join.face as Button).disabled = not SignalCodec.is_code(code_edit.text)
	var target := JoinTarget.of_direct(address_edit.text, default_port)
	(direct_join.face as Button).disabled = not target.problem.is_empty()
	(direct_host.face as Button).disabled = target.port_problem


func _show(which: Open) -> void:
	open = which
	for item: Button in [join_item, direct_item, settings_item]:
		item.set_pressed_no_signal(item == _item_of(which))
	code_panel.visible = which == Open.CODE
	direct_panel.visible = which == Open.DIRECT
	gap.visible = code_panel.visible or direct_panel.visible
	settings_panel.visible = which == Open.SETTINGS
	refresh_buttons()


func _item_of(which: Open) -> Button:
	match which:
		Open.CODE:
			return join_item
		Open.DIRECT:
			return direct_item
		Open.SETTINGS:
			return settings_item
	return null


## Host with no panel; the code or the address field, or the settings' first control, with one.
func _focus() -> void:
	if not is_visible_in_tree():
		return
	match open:
		Open.CODE:
			code_edit.grab_focus()
			code_edit.caret_column = code_edit.text.length()
		Open.DIRECT:
			address_edit.grab_focus()
			address_edit.caret_column = address_edit.text.length()
		Open.SETTINGS:
			settings_page.first_focus().grab_focus()
			# follow_focus scrolls to the focused row before the panel's first sort, with the
			# sizes before it (seen at large text: the first row cut off): the top it is.
			_scroll_to_top.call_deferred()
		_:
			host_item.grab_focus()


func _scroll_to_top() -> void:
	settings_page.scroll.scroll_vertical = 0


## An item of the group pressed or released; pressing another releases this one first (its
## toggled(false) comes while the other already counts as pressed), which closes nothing.
func _on_item_toggled(on: bool, which: Open) -> void:
	if on:
		open_panel(which)
	elif open == which and item_group.get_pressed_button() == null:
		close_panel()


func _build_column() -> void:
	column.name = "Column"
	column.theme_type_variation = &"ToyColumnTwentyFour"
	column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_place(column, COLUMN_PLACE, Control.GROW_DIRECTION_END)
	add_child(column)
	logo.name = "Logo"
	logo.theme_type_variation = &"ToyLogo"
	logo.text = LOGO
	logo.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(logo)
	name_row.name = "NameRow"
	name_row.theme_type_variation = &"ToyRowTwelve"
	name_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_row.custom_minimum_size = Vector2(ITEMS_WIDTH, 0)
	column.add_child(name_row)
	var name_label := UiParts.styled_label("player.name", &"ToyTextMutedOnDark")
	name_label.name = "NameLabel"
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(name_label)
	_field(name_edit, "Name", PlayerNames.MAX_CHARS)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.focus_exited.connect(_show_kept_name)
	name_row.add_child(name_edit)
	body.name = "Body"
	body.theme_type_variation = &"ToyRowThirtyTwo"
	column.add_child(body)
	items.name = "Items"
	items.theme_type_variation = &"ToyColumnFour"
	items.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	items.custom_minimum_size = Vector2(ITEMS_WIDTH, 0)
	body.add_child(items)
	item_group.allow_unpress = true
	host_item = _item("Host", "menu.host", Open.NONE)
	host_item.pressed.connect(func() -> void: code_host_requested.emit())
	join_item = _item("Join", "menu.join", Open.CODE)
	direct_item = _item("Direct", "menu.direct", Open.DIRECT)
	tutorial_item = _item("Tutorial", "menu.tutorial", Open.NONE)
	tutorial_item.pressed.connect(func() -> void: tutorial_requested.emit())
	# Game starts the tutorial on it (#601); off until its screens and lessons are in (#492, 2A).
	tutorial_item.disabled = true
	settings_item = _item("Settings", "menu.settings", Open.SETTINGS)
	quit_item = _item("Quit", "menu.quit", Open.NONE)
	quit_item.pressed.connect(func() -> void: quit_requested.emit())
	gap.name = "Gap"
	gap.custom_minimum_size = Vector2(GAP_WIDTH, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	_build_code_panel()
	_build_direct_panel()


## A menu item: a ToyMenuItem Button with the pointer icon, left-aligned; a toggle in the item
## group when it opens a panel (`opens`).
func _item(item_name: String, key: String, opens: Open) -> Button:
	var made: Button
	if opens == Open.NONE:
		made = Button.new()
		made.text = key
		made.theme_type_variation = &"ToyMenuItem"
		ToyPress.attach(made)
	else:
		made = UiParts.toggle(key, Callable(), &"ToyMenuItem")
		made.button_group = item_group
		made.toggled.connect(_on_item_toggled.bind(opens))
	made.name = item_name
	made.icon = ToyIcons.texture(POINTER)
	made.alignment = HORIZONTAL_ALIGNMENT_LEFT
	items.add_child(made)
	return made


func _build_code_panel() -> void:
	var v := _panel_column()
	code_panel = _panel("CodePanel", v)
	var field := _field_column()
	v.add_child(field)
	field.add_child(_light_label("CodeLabel", "common.code"))
	_field(code_edit, "Code", SignalCodec.CODE_LENGTH)
	code_edit.text_changed.connect(_on_code_changed)
	code_edit.text_change_rejected.connect(_on_code_rejected)
	code_edit.text_submitted.connect(func(_text: String) -> void: _join_code())
	field.add_child(code_edit)
	var buttons := _buttons_row()
	v.add_child(buttons)
	code_join = _raised_button("Join", "join.connect", &"ToyButtonPrimary", _join_code)
	code_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(code_join)
	_ghost(code_back, buttons)


func _build_direct_panel() -> void:
	var v := _panel_column()
	direct_panel = _panel("DirectPanel", v)
	var field := _field_column()
	v.add_child(field)
	field.add_child(_light_label("AddressLabel", "join.address"))
	_field(address_edit, "Address", 0)
	address_edit.text_changed.connect(func(_text: String) -> void: refresh_buttons())
	address_edit.text_submitted.connect(func(_text: String) -> void: _join_direct())
	field.add_child(address_edit)
	port_label.name = "Port"
	port_label.theme_type_variation = &"ToyTextMutedOnLight"
	port_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	field.add_child(port_label)
	var buttons := _buttons_row()
	v.add_child(buttons)
	direct_join = _raised_button("Join", "join.connect", &"ToyButtonPrimary", _join_direct)
	direct_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(direct_join)
	direct_host = _raised_button("Host", "menu.host", &"ToyButtonSecondary", _host_direct)
	buttons.add_child(direct_host)
	_ghost(direct_back, buttons)


## The Settings panel, a root of its own: a raised ToyPanelMenu at SETTINGS_RECT holding
## settings_page.
func _build_settings_panel() -> void:
	var face := PanelContainer.new()
	face.name = "SettingsPanel"
	face.theme_type_variation = &"ToyPanelMenu"
	settings_panel = UiParts.raised(face, ToyHints.DARK)
	settings_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	settings_panel.offset_left = SETTINGS_RECT.position.x
	settings_panel.offset_top = SETTINGS_RECT.position.y
	settings_panel.offset_right = SETTINGS_RECT.end.x
	settings_panel.offset_bottom = SETTINGS_RECT.end.y
	settings_panel.grow_horizontal = Control.GROW_DIRECTION_END
	settings_panel.grow_vertical = Control.GROW_DIRECTION_END
	add_child(settings_panel)
	face.add_child(settings_page)


## A raised ToyPanelMenu named `face_name` holding `inside`, in Body after the gap.
func _panel(face_name: String, inside: Control) -> ToyRaised:
	var face := PanelContainer.new()
	face.name = face_name
	face.theme_type_variation = &"ToyPanelMenu"
	face.add_child(inside)
	var made := UiParts.raised(face, ToyHints.DARK)
	made.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	made.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	body.add_child(made)
	return made


static func _panel_column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "V"
	v.theme_type_variation = &"ToyColumnSixteen"
	return v


static func _field_column() -> VBoxContainer:
	var field := VBoxContainer.new()
	field.name = "Field"
	field.theme_type_variation = &"ToyColumnEight"
	return field


static func _buttons_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.theme_type_variation = &"ToyRowSixteen"
	return row


static func _light_label(label_name: String, key: String) -> Label:
	var label := UiParts.styled_label(key, &"ToyTextMutedOnLight")
	label.name = label_name
	return label


## A ToyField LineEdit for data: no right-click menu (its words are Godot's English), not
## translated, at most `most` characters (0: no limit).
static func _field(edit: LineEdit, edit_name: String, most: int) -> void:
	edit.name = edit_name
	edit.theme_type_variation = &"ToyField"
	edit.context_menu_enabled = false
	edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	edit.max_length = most


## A raised Toy button on a panel (the light context) named `face_name`, with no minimum size of
## its own (the handoff gives none).
static func _raised_button(
	face_name: String, key: String, variation: StringName, pressed: Callable
) -> ToyRaised:
	var made := UiParts.button(key, pressed, variation, ToyHints.LIGHT)
	made.face.name = face_name
	made.name = "%sRaised" % face_name
	made.custom_minimum_size = Vector2.ZERO
	return made


## Back: a flat ghost button that closes the panel.
func _ghost(back: Button, row: HBoxContainer) -> void:
	back.name = "Back"
	back.text = "common.back"
	back.theme_type_variation = &"ToyButtonGhostOnLight"
	back.pressed.connect(close_panel)
	ToyPress.attach(back)
	row.add_child(back)


func _join_code() -> void:
	if not (code_join.face as Button).disabled:
		code_join_requested.emit(code_edit.text)


func _join_direct() -> void:
	if not (direct_join.face as Button).disabled:
		join_requested.emit(address_edit.text.strip_edges(), default_port)


func _host_direct() -> void:
	var port := typed_port(address_edit.text, default_port)
	if port > 0:
		host_requested.emit(port)


func _on_code_changed(typed: String) -> void:
	var kept := code_text(typed)
	if kept != typed:
		var caret := code_text(typed.left(code_edit.caret_column)).length()
		code_edit.text = kept
		code_edit.caret_column = caret
	refresh_buttons()


## A paste longer than the field's room: its rest is taken in after the insert, so a pasted
## "K7M-2QX" keeps all six letters once the dash is dropped.
func _on_code_rejected(rest: String) -> void:
	_rejected += rest
	_take_rejected.call_deferred()


## Only what fits the room the field has left: a key typed into a full field is refused, as a
## full field refuses it, and never pushes the last character out.
func _take_rejected() -> void:
	var room := SignalCodec.CODE_LENGTH - code_text(code_edit.text).length()
	var taken := code_text(_rejected).left(maxi(room, 0))
	_rejected = ""
	if taken.is_empty():
		return
	var caret := code_edit.caret_column
	var whole := code_edit.text.left(caret) + taken + code_edit.text.substr(caret)
	var before := code_text(code_edit.text.left(caret) + taken)
	code_edit.text = code_text(whole)
	code_edit.caret_column = mini(before.length(), code_edit.text.length())
	refresh_buttons()


func _on_name_changed(typed: String) -> void:
	if _settings == null:
		return
	var kept := _settings.player_name
	_settings.player_name = typed
	if _settings.player_name != kept:
		_settings.write()


func _show_kept_name() -> void:
	if _settings != null and name_edit.text != _settings.player_name:
		name_edit.text = _settings.player_name


## Anchored offsets: `at` on both edges, growing `grow` both ways.
static func _place(control: Control, at: Vector2, grow: Control.GrowDirection) -> void:
	control.offset_left = at.x
	control.offset_right = at.x
	control.offset_top = at.y
	control.offset_bottom = at.y
	control.grow_horizontal = grow
	control.grow_vertical = grow


static func _word(key: String) -> String:
	return String(TranslationServer.translate(key))
