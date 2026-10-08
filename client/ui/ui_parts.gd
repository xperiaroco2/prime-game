class_name UiParts
extends RefCounted
## Small builders the screens share (client/ui/). Every colour, font size, spacing and style box
## comes from the shared theme (GameUi.THEME) through a type variation named here; no screen sets
## one inline (client/CLAUDE.md, a source test holds it).
##
## The Toy components (#289; ARCHITECTURE §4.7.26), one way to build each:
## - button(): a raised Toy button, a ToyRaised (base under the face) whose `face` is the Button;
##   the face has ToyPress and, for a toggle pair (ToyPresetCard), ToyToggle, which acts once the
##   caller sets the face's `toggle_mode` (a preset card; not the Save card).
## - raised(): any face on its toy base with no press: ToyPanelMenu, ToyPanelDialog, ToyPanelHowto,
##   ToyMapBoard, the ToyTitlePlate Label.
## - toggle(): a flat toggle Button (tabs, chips, radios, menu items, keycaps) with ToyPress and
##   ToyToggle; one with no partner (ToyMenuItem, ToyKeyButton) draws its own pressed look.
## - sized(): the size constants (`width`, `height`, `min_width`, `wide_width`, `wide_min_width`)
##   into `custom_minimum_size`, again on every theme change (the large-text keycaps).
## - scroll(): a ToyScroll container with the ToyScrollBar.
## A wrapper takes the placement, size flags, minimum size and visibility; a face keeps its
## variation, text and signals. ToyBar and ToySlider are built with `new()`.

## The greybox buttons' width of M4 at the 1920x1080 base (#287): layout, not style.
const BUTTON_SIZE := Vector2(183, 0)


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


## A raised Toy button of `variation` on a `context` screen (ToyHints.DARK or LIGHT); `pressed`
## runs on its `pressed` signal. The wrapper is BUTTON_SIZE wide at least.
static func button(
	text: String,
	pressed: Callable = Callable(),
	variation: StringName = &"ToyButtonSecondary",
	context: StringName = ToyHints.DARK,
) -> ToyRaised:
	var face := Button.new()
	face.text = text
	face.theme_type_variation = variation
	if pressed.is_valid():
		face.pressed.connect(pressed)
	var made := ToyRaised.wrap(face, context)
	made.custom_minimum_size = BUTTON_SIZE
	ToyPress.attach(face, made)
	if not ToyHints.selected_for(variation).is_empty():
		ToyToggle.attach(face)
	return made


## `face` on its toy base for a `context` screen, with no press (a panel, the title plate).
static func raised(face: Control, context: StringName = ToyHints.DARK) -> ToyRaised:
	return ToyRaised.wrap(face, context)


## A flat toggle Button of `variation`; `pressed` runs on its `pressed` signal.
static func toggle(
	text: String, pressed: Callable = Callable(), variation: StringName = &"ToyChipToggleOnDark"
) -> Button:
	var made := Button.new()
	made.text = text
	made.theme_type_variation = variation
	made.toggle_mode = true
	if pressed.is_valid():
		made.pressed.connect(pressed)
	ToyPress.attach(made)
	ToyToggle.attach(made)
	return made


## `control` with its variation's size constants as its minimum size (`wide`: `wide_width`, else
## `wide_min_width`; plain: `width`, else `min_width`; and `height`), read again after every
## theme change; a dimension the variation does not give keeps the caller's (a bar's length).
## Deferred: while `theme_changed` is emitted, get_theme_constant still answers from the cache of
## the theme before (observed on 4.7.2 when an ancestor's theme is swapped). Returns `control`.
static func sized(control: Control, wide: bool = false) -> Control:
	var apply := func() -> void:
		if is_instance_valid(control):
			_apply_size(control, wide)
	control.theme_changed.connect(apply, CONNECT_DEFERRED)
	if control.is_inside_tree():
		_apply_size(control, wide)
	return control


## The minimum size `control`'s variation gives (see sized()).
static func size_of(control: Control, wide: bool = false) -> Vector2:
	var width := control.get_theme_constant(&"wide_width" if wide else &"width")
	if width == 0:
		width = control.get_theme_constant(&"wide_min_width" if wide else &"min_width")
	return Vector2(width, control.get_theme_constant(&"height"))


## A scroll container of `variation` whose vertical bar is the ToyScrollBar.
static func scroll(variation: StringName = &"ToyScroll") -> ScrollContainer:
	var made := ScrollContainer.new()
	made.theme_type_variation = variation
	made.get_v_scroll_bar().theme_type_variation = &"ToyScrollBar"
	return made


## `control` after a label naming it, in one row.
static func labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(250, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


static func _apply_size(control: Control, wide: bool) -> void:
	var given := size_of(control, wide)
	var size := control.custom_minimum_size
	control.custom_minimum_size = Vector2(
		given.x if given.x > 0 else size.x, given.y if given.y > 0 else size.y
	)


static func _margin(inner: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"PanelMargin"
	margin.add_child(inner)
	return margin
