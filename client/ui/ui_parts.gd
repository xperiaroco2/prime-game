class_name UiParts
extends RefCounted
## Small builders the screens share (client/ui/): the greybox look of M4. Every colour, font size,
## spacing and style box comes from the shared theme (GameUi.THEME) through a type variation named
## here; no screen sets one inline (client/CLAUDE.md, a source test holds it).


## A centered panel with a title, filling `parent`; returns the column to add rows to.
static func centered_column(parent: Control, title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"ScreenColumn"
	panel.add_child(_margin(column))
	column.add_child(heading(title))
	return column


## A panel on the right edge of `parent`, full height; returns its column.
static func side_column(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -360
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"SideColumn"
	panel.add_child(_margin(column))
	column.add_child(heading(title))
	return column


static func heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Title"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## A label of the theme's type variation `variation`.
static func styled_label(content: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = content
	label.theme_type_variation = variation
	return label


## A full-screen backdrop drawn by the theme's `variation` (a Panel's style box).
static func backdrop(parent: Control, variation: StringName) -> Panel:
	var panel := Panel.new()
	panel.theme_type_variation = variation
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(panel)
	return panel


static func button(text: String, pressed: Callable) -> Button:
	var made := Button.new()
	made.text = text
	made.custom_minimum_size = Vector2(110, 0)
	made.pressed.connect(pressed)
	return made


## `control` after a label naming it, in one row.
static func labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


static func _margin(inner: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"PanelMargin"
	margin.add_child(inner)
	return margin
