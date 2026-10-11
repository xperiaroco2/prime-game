class_name SettingRows
extends RefCounted
## The setting rows of the Toy Esc menu and Settings (#491; prime-game-ui handoff s05 at ui-0.4.0),
## one way to build each part, so every page draws them alike:
## - row(): a 64 px ToySettingRow (a PanelContainer) holding H (ToyRowTwelve): the Name label
##   (ToySettingRowText, a deck key) and the row's control.
## - dropdown(): a 500 px ToyDropdown OptionButton whose open list is the ToyDropdownList.
## - slider(): a 500 px ToySlider.
## - chips(): a 500 px ToyRowEight of ToyChipToggleOnLight toggles in one ButtonGroup.
## Sizes are px at the 1920x1080 base (#287): layout, not style.

## Every row's height, the field row's (the handoff: rows of a list keep one height).
const ROW_HEIGHT := 64.0
## The width of a row's control: a dropdown, a slider, a chip group.
const CONTROL_WIDTH := 500.0


## A row named `row_name` with the deck key `key` as its name and `control` at its end.
static func row(row_name: String, key: String, control: Control = null) -> PanelContainer:
	var made := PanelContainer.new()
	made.name = row_name
	made.theme_type_variation = &"ToySettingRow"
	made.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var line := HBoxContainer.new()
	line.name = "H"
	line.theme_type_variation = &"ToyRowTwelve"
	made.add_child(line)
	var label := Label.new()
	label.name = "Name"
	label.theme_type_variation = &"ToySettingRowText"
	label.text = key
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	if control != null:
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(control)
	return made


## The Name label of a row built by row().
static func name_of(made: PanelContainer) -> Label:
	return made.get_node(^"H/Name") as Label


## A dropdown named `node_name`; its items are set by the caller (deck words through tr(), data).
static func dropdown(node_name: String) -> OptionButton:
	var made := OptionButton.new()
	made.name = node_name
	made.theme_type_variation = &"ToyDropdown"
	made.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	made.clip_text = true
	made.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Its items are words from code (tr()) or data: Godot must not translate them again.
	made.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	made.get_popup().theme_type_variation = &"ToyDropdownList"
	made.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return made


## A slider named "Slider" from `low` to `high` in steps of `step`.
static func slider(low: float, high: float, step: float) -> ToySlider:
	var made := ToySlider.new()
	made.name = "Slider"
	made.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	made.min_value = low
	made.max_value = high
	made.step = step
	return made


## A ToyRowEight named `node_name` with one ToyChipToggleOnLight per entry of `keys` (child name:
## deck key), all in one ButtonGroup; a chip's `pressed` runs `picked` with its child name.
static func chips(
	node_name: String, keys: Dictionary[String, String], picked: Callable
) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = node_name
	box.theme_type_variation = &"ToyRowEight"
	box.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	var group := ButtonGroup.new()
	for chip_name: String in keys:
		var chip := UiParts.toggle(keys[chip_name], picked.bind(chip_name), &"ToyChipToggleOnLight")
		chip.name = chip_name
		chip.button_group = group
		box.add_child(chip)
	return box


## Presses the chip named `chip_name` of a chips() box without its signal, the others released.
static func show_chip(box: HBoxContainer, chip_name: String) -> void:
	for child: Node in box.get_children():
		var chip := child as Button
		set_pressed(chip, String(chip.name) == chip_name)


## `button`'s pressed state without its signal, its ToyToggle look drawn again.
static func set_pressed(button: BaseButton, on: bool) -> void:
	button.set_pressed_no_signal(on)
	for inner: Node in button.get_children(true):
		if inner is ToyToggle:
			(inner as ToyToggle).sync()


## A muted line of text (a note between the rows), wrapped.
static func note(text: String) -> Label:
	var label := UiParts.styled_label(text, &"ToyTextMutedOnLight")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
