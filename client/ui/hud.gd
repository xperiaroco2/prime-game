class_name Hud
extends Control
## The round's HUD (ARCHITECTURE §4.7, M4-8): what HudText says, in the corners of the screen, with
## the crosshair and its hint in the middle and the destination's colour swatch beside the slots.
## Styled only through the shared theme (GameUi.THEME: HudMargin, HudPanel, HudText, HudTitle,
## HudCrosshair, HudHint), no inline colours, sizes or fonts; the swatch's colour is the circle's,
## from the model. It reads nothing itself: the game feeds it. A dead spectator's "Spectating
## <name>" heads the slots' corner, over the watched player's hand and belt (#168).

## The swatch's size in pixels (layout, not style).
const SWATCH_SIZE := Vector2(28, 28)

var role_label := UiParts.styled_label("", &"HudText")
var teammates_label := UiParts.styled_label("", &"HudText")
var clock_label := UiParts.styled_label("", &"HudTitle")
var progress_label := UiParts.styled_label("", &"HudText")
var health_label := UiParts.styled_label("", &"HudText")
var stamina_label := UiParts.styled_label("", &"HudText")
var hand_label := UiParts.styled_label("", &"HudText")
var belt_label := UiParts.styled_label("", &"HudText")
var spectating_label := UiParts.styled_label("", &"HudTitle")
var destination_label := UiParts.styled_label("", &"HudText")
var swatch := ColorRect.new()
var crosshair := UiParts.styled_label("+", &"HudCrosshair")
var hint_label := UiParts.styled_label("", &"HudHint")
## The crosshair and its hint show; off while the task screen covers the middle.
var aiming := true:
	set = set_aiming

var _destination_row := HBoxContainer.new()
## The corner panels: one with no line to show is hidden too.
var _corners: Array[PanelContainer] = []


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"HudMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(frame)
	_corner(frame, Control.PRESET_TOP_LEFT, [role_label, teammates_label])
	var top := _corner(frame, Control.PRESET_CENTER_TOP, [clock_label, progress_label])
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_corner(frame, Control.PRESET_BOTTOM_LEFT, [health_label, stamina_label])
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_destination_row.add_child(swatch)
	_destination_row.add_child(destination_label)
	var slots: Array[Control] = [spectating_label, hand_label, belt_label, _destination_row]
	_corner(frame, Control.PRESET_BOTTOM_RIGHT, slots)
	for label: Label in [crosshair, hint_label]:
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		label.grow_vertical = Control.GROW_DIRECTION_BOTH
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	# Below the crosshair, not over it.
	hint_label.offset_top += SWATCH_SIZE.y * 2.0
	hint_label.offset_bottom += SWATCH_SIZE.y * 2.0
	show_hud(HudText.Shown.new())


## Shows `shown`; an empty line hides its label.
func show_hud(shown: HudText.Shown) -> void:
	_show_line(role_label, shown.role)
	_show_line(teammates_label, shown.teammates)
	_show_line(clock_label, shown.clock)
	_show_line(progress_label, shown.progress)
	_show_line(health_label, shown.health)
	_show_line(stamina_label, shown.stamina)
	_show_line(hand_label, shown.hand)
	_show_line(belt_label, shown.belt)
	_show_line(spectating_label, shown.spectating)
	_show_line(destination_label, shown.destination)
	_destination_row.visible = not shown.destination.is_empty()
	swatch.color = shown.destination_colour
	_show_line(hint_label, shown.hint if aiming else "")
	for panel: PanelContainer in _corners:
		panel.visible = (panel.get_child(0) as Control).get_children().any(
			func(row: Node) -> bool: return (row as Control).visible
		)


func set_aiming(on: bool) -> void:
	aiming = on
	crosshair.visible = on
	if not on:
		hint_label.visible = false


## A panel in the corner `preset` of `frame` with `rows` in a column, growing inwards.
func _corner(frame: Control, preset: Control.LayoutPreset, rows: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(preset)
	var right := preset == Control.PRESET_BOTTOM_RIGHT or preset == Control.PRESET_TOP_RIGHT
	var bottom := preset == Control.PRESET_BOTTOM_LEFT or preset == Control.PRESET_BOTTOM_RIGHT
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for row: Control in rows:
		column.add_child(row)
	panel.add_child(column)
	frame.add_child(panel)
	_corners.append(panel)
	return panel


static func _show_line(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()
