class_name UiParts
extends RefCounted
## Small builders the screens share (client/ui/): the greybox look of M4, the default theme.


## A centered panel with a title, filling `parent`; returns the column to add rows to.
static func centered_column(parent: Control, title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
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
	column.add_theme_constant_override(&"separation", 8)
	panel.add_child(_margin(column))
	column.add_child(heading(title))
	return column


static func heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


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
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	margin.add_child(inner)
	return margin
