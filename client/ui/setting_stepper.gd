class_name SettingStepper
extends HBoxContainer
## A whole-number setting's stepper (#491; prime-game-ui handoff s05, the Lobby tab's rows): Less,
## the Value (104 px, so every stepper has one width) and More, ToyStepper buttons with the pack's
## chevrons. Keyboard and gamepad reach the arrows by focus and step with ui_accept; when a step
## reaches a bound the other arrow takes the focus before this one is disabled, so focus never
## rests on an unplugged arrow. A player sees only the value (set_editable(false)).

## The player stepped to `value` (within the bounds).
signal stepped(value: int)

const VALUE_WIDTH := Vector2(104, 0)
const LESS_ICON := preload("res://assets/ui/toy_pack/icons/chevron-left.svg")
const MORE_ICON := preload("res://assets/ui/toy_pack/icons/chevron-right.svg")

var less := Button.new()
var value_label := UiParts.styled_label("", &"ToySettingRowValue")
var more := Button.new()
var value := 0
var low := 0
var high := 0
## How the value reads ({count} for a key like unit.minutes; "" shows the number).
var format_key := ""


func _init() -> void:
	name = "Stepper"
	theme_type_variation = &"ToyRowEight"
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for arrow: Button in [less, more]:
		arrow.theme_type_variation = &"ToyStepper"
		arrow.icon = LESS_ICON if arrow == less else MORE_ICON
		ToyPress.attach(arrow)
	less.name = "Less"
	less.pressed.connect(step.bind(-1))
	add_child(less)
	value_label.name = "Value"
	value_label.custom_minimum_size = VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(value_label)
	more.name = "More"
	more.pressed.connect(step.bind(1))
	add_child(more)


func set_bounds(at_least: int, at_most: int) -> void:
	low = at_least
	high = at_most
	show_value(value)


## Shows `shown` (the model's), without a signal.
func show_value(shown: int) -> void:
	value = clampi(shown, low, high)
	_retext()
	less.disabled = value <= low
	more.disabled = value >= high


## The arrows show (the host) or hide (a player sees the value only).
func set_editable(on: bool) -> void:
	less.visible = on
	more.visible = on


## One step down (-1) or up (+1): the focus moves to the other arrow first when this one reaches
## its bound, then the value shows and is said.
func step(by: int) -> void:
	var next := clampi(value + by, low, high)
	if next == value:
		return
	var leaving := less if by < 0 else more
	if focus_after(next, low, high, by < 0) and leaving.has_focus():
		(more if by < 0 else less).grab_focus()
	show_value(next)
	stepped.emit(next)


## Whether a step to `next` reaches the bound on its own side (the focus must move off its arrow).
static func focus_after(next: int, at_least: int, at_most: int, going_down: bool) -> bool:
	return next <= at_least if going_down else next >= at_most


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and value_label != null:
		_retext()


func _retext() -> void:
	value_label.text = (
		str(value) if format_key.is_empty() else tr(format_key).format({"count": value})
	)
