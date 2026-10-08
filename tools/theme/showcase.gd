extends Control
## The Godot showcase of the Toy look (#289), to compare with the UI pack's HTML showcase: every
## live variation of the generated theme in every state Godot can force, on its night (dark) or
## cream (light) stage at the 1920x1080 base. A row's cells: normal; hover (the variation's
## `hover` StyleBox and font colour through a small per-cell theme, and ToyPress's hover offset);
## held (the `pressed` look and `press_held`); disabled (the base unplugged); focus (the `focus`
## StyleBox drawn over the face, as Godot draws it for keyboard focus); selected and selected +
## hover for a toggle pair; and a live cell (real ToyPress and ToyToggle). The font (Comfortaa) and
## the icons (slider knobs, the dropdown arrow, radios, chevrons) are placeholders until #520.
##   tools\run.cmd shot tools/theme/showcase.tscn --size 1920x1080      page 0 (showcase_<n>.tscn)
##   tools\run.cmd run tools/theme/showcase_interactive.tscn --seconds 3600   a window, for a human
## A dev tool, not a screen, so it lives under tools/ (prime-game-ui spec §19.6).

const DARK := ToyHints.DARK
const LIGHT := ToyHints.LIGHT
## Each page: its title and its sections; a section is [title, context, entries]. An entry is a
## variation name, or "<name>:wide" for the wide size, or "<name>@<fraction>" for a bar.
const PAGES: Array[Dictionary] = [
	{
		"title": "Buttons, menu items, tabs, chips",
		"sections":
		[
			["Buttons", DARK, ["ToyButtonPrimary", "ToyButtonSecondary", "ToyButtonDanger"]],
			[
				"Ghost, menu item, chip",
				DARK,
				["ToyButtonGhostOnDark", "ToyMenuItem", "ToyChipToggleOnDark"]
			],
			["Buttons", LIGHT, ["ToyButtonPrimary", "ToyButtonSecondary", "ToyButtonDanger"]],
			[
				"Ghost, tab, chip",
				LIGHT,
				["ToyButtonGhostOnLight", "ToyTab", "ToyChipToggleOnLight"]
			],
		],
	},
	{
		"title": "Keys, stepper, preset card, swatches, slots, bars",
		"sections":
		[
			["Slots", DARK, ["ToySlot", "ToySlotActive", "ToySlot:wide"]],
			[
				"Bars",
				DARK,
				[
					"ToyBarStamina@1",
					"ToyBarStamina@0.9",
					"ToyBarStamina@0.5",
					"ToyBarStamina@0.18",
					"ToyBarStamina@0.03",
					"ToyBarHealth@1",
					"ToyBarHealth@0.8",
					"ToyBarHealth@0.5",
					"ToyBarHealth@0.22",
					"ToyBarHealth@0.05",
					"ToyBarHealth@0",
					"ToyBarProgress@0.62",
					"ToyBarProgress@0.7",
					"ToyBarLabel",
				],
			],
			["Health ramp", DARK, ["ramp"]],
			[
				"Keys and stepper",
				LIGHT,
				["ToyKeyButton", "ToyKeyButton:wide", "ToyKeyRoundButton", "ToyStepper"]
			],
			["Preset card", LIGHT, ["ToyPresetCard"]],
			["Swatches", LIGHT, ["ToySwatchRing", "ToySwatchSelected", "ToySwatchFocus"]],
		],
	},
	{
		"title": "Plates, chips, radio, keys, surfaces, fields, dropdown, slider",
		"sections":
		[
			["Plates", DARK, ["ToyPlate", "ToyPlateNight", "ToyPlateAlert", "ToyNamePlate"]],
			[
				"Chips, key, mic",
				DARK,
				["ToyChipPlate", "ToyChipLineOnDark", "ToyKeyOnDark", "ToyMic"]
			],
			[
				"Surfaces",
				DARK,
				[
					"ToyBackdrop",
					"ToyBackdropDeep",
					"ToyBackdropNight",
					"ToySpinner",
					"ToyCrosshair"
				],
			],
			["Chips", LIGHT, ["ToyChipAlert", "ToyChipLight", "ToyChipLineOnLight"]],
			["Radio", LIGHT, ["ToyRadio"]],
			["Keys", LIGHT, ["ToyKeyOnLight", "ToyKeyQuiet", "ToyKeyRound", "ToyKeyRoundQuiet"]],
			["Slider bar", LIGHT, ["ToyBarSlider@0.7", "ToyBarSlider@0.55", "ToyBarSlider@0.4"]],
			["Field", LIGHT, ["ToyField"]],
			["Dropdown", LIGHT, ["ToyDropdown"]],
			["Slider", LIGHT, ["ToySlider"]],
			[
				"Text",
				LIGHT,
				["ToyTitleOnLight", "ToyTextOnLight", "ToyTextMutedOnLight", "ToyDisplayOnLight"],
			],
		],
	},
	{
		"title": "Title, text, quiet card, panels, how-to, map, setting row, spacing",
		"sections":
		[
			["Title plate", DARK, ["ToyTitlePlate"]],
			[
				"Text",
				DARK,
				[
					"ToyLogo",
					"ToyTitleOnDark",
					"ToyTextOnDark",
					"ToyTextMutedOnDark",
					"ToyTimer",
					"ToyHudCaption"
				],
			],
			["Quiet preset card", LIGHT, ["ToyPresetCardQuiet"]],
			["Panels", LIGHT, ["ToyPanelMenu", "ToyPanelDialog", "ToyPanelHowto"]],
			["How-to frames", LIGHT, ["ToyHowtoFrame", "ToyHowtoFrameDone"]],
			["Map", LIGHT, ["ToyMapBoard"]],
			["Setting row and list", LIGHT, ["ToySettingRow", "ToyScroll"]],
			[
				"Spacing (draws nothing: swatches show the gap)",
				DARK,
				[
					"ToyColumnFour",
					"ToyColumnEight",
					"ToyColumnTwelve",
					"ToyColumnSixteen",
					"ToyColumnTwentyFour",
					"ToyColumnThirtyTwo",
					"ToyRowFour",
					"ToyRowEight",
					"ToyRowTwelve",
					"ToyRowSixteen",
					"ToyRowTwentyFour",
					"ToyRowThirtyTwo",
					"ToyGridList",
					"ToyGridSwatch",
				],
			],
		],
	},
]
const BUTTON_STATES: Array[String] = ["normal", "hover", "held", "disabled", "focus"]
const TOGGLE_STATES: Array[String] = ["selected", "selected + hover"]
## Sample texts of the Labels that sit on a container (the pack's `on`, and the line chips).
const TEXTS: Dictionary[String, String] = {
	"ToyChipAlertText": "New",
	"ToyChipLightText": "Wires",
	"ToyChipLineOnDarkText": "Banned",
	"ToyChipLineOnLightText": "Banned",
	"ToyChipPlateText": "E  Pick up",
	"ToyHowtoNote": "Hold E to fix",
	"ToyHudCaption": "Stamina",
	"ToyKeyQuietText": "Q",
	"ToyKeyText": "E",
	"ToyMapRoomText": "Kitchen",
	"ToyNamePlateText": "Player1",
	"ToyPlateText": "Find the packages",
	"ToyPresetCardName": "Standard",
	"ToySettingRowText": "Match duration",
	"ToySettingRowValue": "10 min",
	"ToySlotText": "Wrench",
	"ToySlotTextEmpty": "Empty",
}
const LABEL_ON: Dictionary[String, Array] = {
	"ToyBarLabel": ["ToyHudCaption"],
	"ToyChipAlert": ["ToyChipAlertText"],
	"ToyChipLight": ["ToyChipLightText"],
	"ToyChipLineOnDark": ["ToyChipLineOnDarkText"],
	"ToyChipLineOnLight": ["ToyChipLineOnLightText"],
	"ToyChipPlate": ["ToyChipPlateText"],
	"ToyKeyOnDark": ["ToyKeyText"],
	"ToyKeyOnLight": ["ToyKeyText"],
	"ToyKeyQuiet": ["ToyKeyQuietText"],
	"ToyKeyRound": ["ToyKeyText"],
	"ToyKeyRoundQuiet": ["ToyKeyQuietText"],
	"ToyNamePlate": ["ToyNamePlateText"],
	"ToyPanelHowto": ["ToyHowtoNote"],
	"ToyPlate": ["ToyPlateText"],
	"ToyPlateAlert": ["ToyPlateText"],
	"ToyPlateNight": ["ToyPlateText"],
	"ToySettingRow": ["ToySettingRowText", "ToySettingRowValue"],
	"ToySlot": ["ToySlotText", "ToySlotTextEmpty"],
	"ToySlotActive": ["ToySlotText", "ToySlotTextEmpty"],
}
const BUTTON_TEXTS: Dictionary[String, String] = {
	"ToyKeyButton": "E",
	"ToyKeyRoundButton": "?",
	"ToyStepper": "+",
	"ToyPresetCard": "",
	"ToyPresetCardQuiet": "",
	"ToyTab": "Lobby",
	"ToyMenuItem": "Join",
	"ToyRadio": "Option",
}

## The page shown.
@export var page := 0
## A window for a human: the page chips, the large-text and reduced-motion switches and a live
## health slider; off for the shots.
@export var interactive := false

var large_text := false
var _body: Control
var _health_bar: ToyBar
var _health_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not interactive:
		UiPrefs.reduced_motion = true
	rebuild()


## Builds the page again (after a switch).
func rebuild() -> void:
	theme = GameUi.THEME_LARGE if large_text else GameUi.THEME
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var night := Panel.new()
	night.theme_type_variation = &"ToyBackdropNight"
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(night)
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.theme_type_variation = &"ToyColumnEight"
	add_child(outer)
	var top := HBoxContainer.new()
	top.theme_type_variation = &"ToyRowSixteen"
	outer.add_child(top)
	var title := Label.new()
	title.theme_type_variation = &"ToyTitleOnDark"
	title.text = (
		"Toy showcase %d/%d: %s%s"
		% [page + 1, PAGES.size(), PAGES[page]["title"], " (large text)" if large_text else ""]
	)
	top.add_child(title)
	if interactive:
		_controls(top)
	_body = HBoxContainer.new()
	_body.theme_type_variation = &"ToyRowSixteen"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_body)
	var dark_column := _stage(DARK)
	var light_column := _stage(LIGHT)
	for section: Array in PAGES[page]["sections"]:
		var column := dark_column if section[1] == DARK else light_column
		_section(column, str(section[0]), StringName(str(section[1])), section[2] as Array)


## Every variation the pages name or build, for the coverage test: theme_type_variation of every
## node of `root`, internal children (a scroll bar, a popup) included.
static func variations_under(root: Node) -> Dictionary[String, bool]:
	var found: Dictionary[String, bool] = {}
	var control := root as Control
	if control != null and not control.theme_type_variation.is_empty():
		found[str(control.theme_type_variation)] = true
	var popup := root as PopupMenu
	if popup != null and not popup.theme_type_variation.is_empty():
		found[str(popup.theme_type_variation)] = true
	var toggle := root as ToyToggle
	if toggle != null and not toggle.selected.is_empty():
		found[str(toggle.selected)] = true
	for child: Node in root.get_children(true):
		found.merge(variations_under(child))
	return found


func _stage(context: StringName) -> VBoxContainer:
	var holder := PanelContainer.new()
	holder.theme_type_variation = &"ToyPlateNight" if context == DARK else &"ToyPanelMenu"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(holder)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"ToyColumnFour"
	holder.add_child(column)
	return column


func _section(column: VBoxContainer, title: String, context: StringName, entries: Array) -> void:
	var heading := Label.new()
	heading.theme_type_variation = &"ToyTextOnDark" if context == DARK else &"ToyTextOnLight"
	heading.text = title
	column.add_child(heading)
	var flow: HFlowContainer = null
	for entry: String in entries:
		if _is_button(entry):
			_button_row(column, entry, context)
			continue
		if flow == null:
			flow = HFlowContainer.new()
			flow.theme_type_variation = &"ToyRowEight"
			column.add_child(flow)
		_sample(flow, entry, context)


func _is_button(entry: String) -> bool:
	var base := StringName(entry.get_slice(":", 0))
	for step in 6:
		if base == &"Button":
			return true
		if base.is_empty():
			return false
		base = theme.get_type_variation_base(base)
	return false


func _name_label(text: String, context: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = (
		&"ToyTextMutedOnDark" if context == DARK else &"ToyTextMutedOnLight"
	)
	label.text = text
	return label


## A state's caption under a cell, in the smallest text.
func _caption(text: String, context: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ToyHudCaption" if context == DARK else &"ToyMapRoomText"
	label.text = text
	return label


## One row of a Button variation: a cell per state it can force, and a live one.
## The cells are forced once they are in the tree, where the theme's constants resolve.
func _button_row(column: VBoxContainer, entry: String, context: StringName) -> void:
	var variation := StringName(entry.get_slice(":", 0))
	var wide := entry.ends_with(":wide")
	column.add_child(_name_label(entry, context))
	var row := HFlowContainer.new()
	row.theme_type_variation = &"ToyRowTwelve"
	column.add_child(row)
	var states: Array[String] = BUTTON_STATES.duplicate()
	if not ToyHints.selected_for(variation).is_empty():
		states.append_array(TOGGLE_STATES)
	states.append("live")
	for state in states:
		var cell := VBoxContainer.new()
		cell.theme_type_variation = &"ToyColumnFour"
		row.add_child(cell)
		var face := _button(cell, variation, context, wide)
		_force(face, variation, state)
		cell.add_child(_caption(state, context))


## A button of `variation` built the way the screens build it, added to `cell`; its face.
func _button(cell: Control, variation: StringName, context: StringName, wide: bool) -> Button:
	var text := _button_text(variation, wide)
	var face: Button
	if not ToyHints.base_for(variation, context).is_empty():
		var raised := UiParts.button(text, Callable(), variation, context)
		raised.custom_minimum_size = Vector2.ZERO
		face = raised.face as Button
		cell.add_child(raised)
	elif not ToyHints.selected_for(variation).is_empty():
		face = UiParts.toggle(text, Callable(), variation)
		cell.add_child(face)
	else:
		face = Button.new()
		face.text = text
		face.theme_type_variation = variation
		ToyPress.attach(face)
		cell.add_child(face)
	if variation in [&"ToyKeyButton", &"ToyKeyRoundButton"]:
		UiParts.sized(face, wide)
	if variation in [&"ToyPresetCard", &"ToyPresetCardQuiet"]:
		_card_content(face)
	if variation == &"ToyPresetCard":
		face.toggle_mode = true
	(cell.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return face


func _button_text(variation: StringName, wide: bool) -> String:
	if variation == &"ToyKeyButton" and wide:
		return "Space"
	if BUTTON_TEXTS.has(str(variation)):
		return BUTTON_TEXTS[str(variation)]
	return "Ready" if str(variation).begins_with("ToyChip") else "Host"


## A preset card's content: the name and the note, which ignore the mouse; the note swaps with
## the card.
func _card_content(card: Button) -> void:
	card.custom_minimum_size = Vector2(184, 96)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	var name_label := UiParts.styled_label("Standard", &"ToyPresetCardName")
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var note := UiParts.styled_label("10 min", &"ToyPresetCardNote")
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)
	if card.has_node(^"ToyToggle"):
		var toggle := card.get_node(^"ToyToggle") as ToyToggle
		toggle.companion(note, &"ToyPresetCardNote", &"ToyPresetCardNoteSelected")


## Forces `state` on a face that is in the tree.
func _force(face: Button, variation: StringName, state: String) -> void:
	var press := face.get_node(^"ToyPress") as ToyPress
	match state:
		"hover":
			face.theme = _hover_theme(variation)
			press.on_mouse_entered()
		"held":
			face.toggle_mode = true
			face.set_pressed_no_signal(true)
			press.refresh()
		"disabled":
			face.disabled = true
			press.refresh()
		"focus":
			face.add_child(FocusRing.new())
		"selected":
			face.toggle_mode = true
			face.button_pressed = true
		"selected + hover":
			face.toggle_mode = true
			face.button_pressed = true
			face.theme = _hover_theme(face.theme_type_variation)
			press.on_mouse_entered()


## A theme whose `variation` draws its hover look as `normal`: Godot cannot force a hover.
func _hover_theme(variation: StringName) -> Theme:
	var hover := Theme.new()
	hover.set_type_variation(variation, theme.get_type_variation_base(variation))
	if theme.has_stylebox(&"hover", variation):
		hover.set_stylebox(&"normal", variation, theme.get_stylebox(&"hover", variation))
		hover.set_stylebox(&"pressed", variation, theme.get_stylebox(&"hover", variation))
	if theme.has_stylebox(&"hover_pressed", variation):
		hover.set_stylebox(&"pressed", variation, theme.get_stylebox(&"hover_pressed", variation))
	var colours: Dictionary[StringName, StringName] = {
		&"font_color": &"font_hover_color", &"font_pressed_color": &"font_hover_pressed_color"
	}
	for item: StringName in colours:
		if theme.has_color(colours[item], variation):
			hover.set_color(item, variation, theme.get_color(colours[item], variation))
	return hover


## A sample of a variation that is not a Button.
func _sample(flow: Control, entry: String, context: StringName) -> void:
	if entry == "ramp":
		_ramp(flow)
		return
	var variation := StringName(entry.get_slice(":", 0).get_slice("@", 0))
	var cell := VBoxContainer.new()
	cell.theme_type_variation = &"ToyColumnFour"
	flow.add_child(cell)
	var made := _made(variation, entry, context)
	cell.add_child(made)
	made.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cell.add_child(_caption(entry, context))


func _made(variation: StringName, entry: String, context: StringName) -> Control:
	if entry.contains("@"):
		return _bar(variation, entry.get_slice("@", 1).to_float())
	var special: Dictionary[StringName, Callable] = {
		&"ToyField": _fields,
		&"ToyDropdown": _dropdowns,
		&"ToySlider": _sliders,
		&"ToyScroll": _scroll,
		&"ToyMapBoard": _map.bind(context),
	}
	if special.has(variation):
		return special[variation].call() as Control
	var base := theme.get_type_variation_base(variation)
	if base == &"Label":
		return _label_sample(variation, context)
	if base in [&"VBoxContainer", &"HBoxContainer", &"GridContainer"]:
		return _spacing(variation, base)
	if base == &"Panel":
		var panel := Panel.new()
		panel.theme_type_variation = variation
		panel.custom_minimum_size = Vector2(64, 48)
		if theme.has_constant(&"width", variation):
			UiParts.sized(panel)
		return panel
	return _container(variation, entry, context)


func _label_sample(variation: StringName, context: StringName) -> Control:
	var label := UiParts.styled_label(_label_text(variation), variation)
	if _has_base(variation, context):
		return UiParts.raised(label, context)
	return label


func _label_text(variation: StringName) -> String:
	match variation:
		&"ToyTimer":
			return "03:12"
		&"ToyLogo":
			return "PrimeGame"
		&"ToyTitlePlate":
			return "Engineer"
		&"ToyDisplayOnLight":
			return "12"
	return str(variation).trim_prefix("Toy")


func _has_base(variation: StringName, context: StringName) -> bool:
	return not ToyHints.base_for(variation, context).is_empty()


## A PanelContainer variation with each Label variation that sits on it.
func _container(variation: StringName, entry: String, context: StringName) -> Control:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"ToyRowEight"
	var labels: Array = LABEL_ON.get(str(variation), [""])
	if variation == &"ToySettingRow":
		# One row holds its text and its value.
		labels = [labels]
	for text_variation: Variant in labels:
		var box := PanelContainer.new()
		box.theme_type_variation = variation
		if theme.has_constant(&"width", variation) or theme.has_constant(&"min_width", variation):
			UiParts.sized(box, entry.ends_with(":wide"))
		if text_variation is Array:
			var line := HBoxContainer.new()
			line.theme_type_variation = &"ToyRowTwentyFour"
			for each: String in text_variation:
				line.add_child(UiParts.styled_label(TEXTS.get(each, "Text") as String, each))
			box.add_child(line)
		elif not str(text_variation).is_empty():
			var label := UiParts.styled_label(
				TEXTS.get(text_variation, "Text") as String, str(text_variation)
			)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			box.add_child(label)
		elif (
			variation
			in [&"ToyPanelMenu", &"ToyPanelDialog", &"ToyHowtoFrame", &"ToyHowtoFrameDone"]
		):
			box.custom_minimum_size = Vector2(160, 96)
		if _has_base(variation, context):
			row.add_child(UiParts.raised(box, context))
		else:
			row.add_child(box)
	return row


func _bar(variation: StringName, fraction: float) -> Control:
	if variation in [ToyBar.HEALTH, ToyBar.STAMINA]:
		var bar := ToyBar.new(variation)
		bar.custom_minimum_size.x = 200
		bar.set_fraction(fraction)
		return bar
	var plain := ProgressBar.new()
	plain.theme_type_variation = variation
	plain.show_percentage = false
	plain.max_value = 1.0
	plain.step = 0.0
	plain.value = fraction
	plain.custom_minimum_size = Vector2(200, 16)
	return plain


## The 21 stops of the health ramp, each a full ToyBar at its stop's fraction.
func _ramp(flow: Control) -> void:
	var strip := HBoxContainer.new()
	strip.theme_type_variation = &"ToyRowFour"
	for step in ToyBar.STEPS + 1:
		var cell := VBoxContainer.new()
		var bar := ToyBar.new()
		bar.custom_minimum_size.x = 36
		bar.set_fraction(step / float(ToyBar.STEPS))
		cell.add_child(bar)
		cell.add_child(_caption("%02d" % step, DARK))
		strip.add_child(cell)
	flow.add_child(strip)


func _fields() -> Control:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"ToyRowEight"
	for state: String in ["normal", "placeholder", "read-only", "focus", "live"]:
		var field := LineEdit.new()
		field.theme_type_variation = &"ToyField"
		field.custom_minimum_size = Vector2(150, 0)
		field.context_menu_enabled = false
		field.text = "" if state == "placeholder" else "Kitchen"
		field.placeholder_text = "Lobby name"
		field.editable = state != "read-only"
		if state == "focus":
			field.add_child(FocusRing.new())
		row.add_child(field)
	return row


func _dropdowns() -> Control:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"ToyRowEight"
	for state: String in ["normal", "hover", "disabled", "focus", "live"]:
		var dropdown := OptionButton.new()
		dropdown.theme_type_variation = &"ToyDropdown"
		dropdown.get_popup().theme_type_variation = &"ToyDropdownList"
		dropdown.add_item("Push to talk")
		dropdown.add_item("Voice activation")
		dropdown.disabled = state == "disabled"
		row.add_child(dropdown)
		if state == "hover":
			dropdown.theme = _hover_theme(&"ToyDropdown")
		if state == "focus":
			dropdown.add_child(FocusRing.new())
	return row


func _sliders() -> Control:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"ToyRowEight"
	for state: String in ["idle", "focus", "not editable", "live"]:
		var slider := ToySlider.new()
		slider.custom_minimum_size = Vector2(150, 24)
		slider.value = 60
		slider.editable = state != "not editable"
		row.add_child(slider)
		if state == "focus" and not interactive:
			slider.grab_focus.call_deferred()
	return row


func _scroll() -> Control:
	var list := UiParts.scroll()
	list.custom_minimum_size = Vector2(220, 120)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.theme_type_variation = &"ToyColumnFour"
	list.add_child(column)
	for index in 10:
		column.add_child(UiParts.styled_label("Player%d" % (index + 1), &"ToyTextOnLight"))
	return list


func _map(context: StringName) -> Control:
	var board := PanelContainer.new()
	board.theme_type_variation = &"ToyMapBoard"
	var row := HBoxContainer.new()
	row.theme_type_variation = &"ToyRowTwelve"
	board.add_child(row)
	var room := PanelContainer.new()
	room.theme_type_variation = &"ToyMapRoom"
	room.add_child(UiParts.styled_label("Kitchen", &"ToyMapRoomText"))
	row.add_child(room)
	var zone := Panel.new()
	zone.theme_type_variation = &"ToyMapZone"
	zone.custom_minimum_size = Vector2(64, 48)
	row.add_child(zone)
	for degrees: float in [0.0, 80.0]:
		var pin := Panel.new()
		pin.theme_type_variation = &"ToyMapPin"
		UiParts.sized(pin)
		pin.offset_transform_enabled = true
		pin.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
		pin.offset_transform_rotation = deg_to_rad(degrees)
		pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pin)
	return UiParts.raised(board, context)


## A spacing variation draws nothing: three swatches show its gap.
func _spacing(variation: StringName, base: StringName) -> Control:
	var box: Container
	match base:
		&"VBoxContainer":
			box = VBoxContainer.new()
		&"HBoxContainer":
			box = HBoxContainer.new()
		_:
			var grid := GridContainer.new()
			grid.columns = 2
			box = grid
	box.theme_type_variation = variation
	for index in 3:
		var swatch := Panel.new()
		swatch.theme_type_variation = &"ToySwatchRing"
		swatch.custom_minimum_size = Vector2(12, 12)
		box.add_child(swatch)
	return box


## The interactive window's switches: pages, large text, reduced motion, a live health slider.
func _controls(top: HBoxContainer) -> void:
	var group := ButtonGroup.new()
	for index in PAGES.size():
		var chip := UiParts.toggle("Page %d" % (index + 1), _show_page.bind(index))
		chip.button_group = group
		chip.set_pressed_no_signal(index == page)
		(chip.get_node(^"ToyToggle") as ToyToggle).sync()
		top.add_child(chip)
	var large := UiParts.toggle("Large text", _switch_large)
	large.set_pressed_no_signal(large_text)
	(large.get_node(^"ToyToggle") as ToyToggle).sync()
	top.add_child(large)
	var reduced := UiParts.toggle("Reduced motion")
	reduced.set_pressed_no_signal(UiPrefs.reduced_motion)
	(reduced.get_node(^"ToyToggle") as ToyToggle).sync()
	reduced.toggled.connect(func(on: bool) -> void: UiPrefs.reduced_motion = on)
	top.add_child(reduced)
	var slider := ToySlider.new()
	slider.custom_minimum_size = Vector2(240, 24)
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.22
	top.add_child(slider)
	_health_bar = ToyBar.new()
	_health_bar.custom_minimum_size.x = 200
	_health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_health_bar)
	_health_label = UiParts.styled_label("", &"ToyTextOnDark")
	top.add_child(_health_label)
	slider.value_changed.connect(show_health)
	show_health(slider.value)


## The live health bar at `hp`, with its stop's number.
func show_health(hp: float) -> void:
	_health_bar.set_fraction(hp)
	_health_label.text = "hp %.2f: stop %02d" % [hp, ToyBar.step_of(hp)]


func _show_page(index: int) -> void:
	page = index
	rebuild.call_deferred()


func _switch_large() -> void:
	large_text = not large_text
	rebuild.call_deferred()


## Draws its parent's `focus` StyleBox over it, as Godot draws a focused control's.
class FocusRing:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var parent := get_parent() as Control
		draw_style_box(parent.get_theme_stylebox(&"focus"), Rect2(Vector2.ZERO, size))
