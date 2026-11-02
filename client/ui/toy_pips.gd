class_name ToyPips
extends HBoxContainer
## A row of ten pips (#1570; prime-game-ui `ui-2.5.4` `docs/handoff/s07-hud.md`, the engineer's
## segmented pips of 2026-10-21): a value 0 to 1 shows round(value x 10) full pips, the rest empty
## (ToyPip), no number. The full ones are the row's own variation (ToyPipHealth, ToyPipStamina),
## or ToyPipAlarm while the value is under the alarm line, when the row has one (health: 30 %).
## The count of full pips is the cue; the colour only adds to it. Each pip's size is its
## variation's `width` and `height` (UiParts.sized).

const COUNT := 10
const EMPTY := &"ToyPip"
const ALARM := &"ToyPipAlarm"
const HEALTH := &"ToyPipHealth"
const STAMINA := &"ToyPipStamina"
## Health's alarm line (the handoff: under 30 % its pips and label turn to the danger colour).
const HEALTH_ALARM := 0.3

## The value shown (0 to 1).
var fraction := 1.0
## The full pips' variation and the alarm line (a negative line: none).
var full_variation: StringName
var alarm_below := -1.0
var pips: Array[Panel] = []


func _init(variation: StringName, alarm: float = -1.0) -> void:
	name = "Pips"
	theme_type_variation = &"ToyRowFour"
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_variation = variation
	alarm_below = alarm
	for index in COUNT:
		var pip := Panel.new()
		pip.name = "P%d" % (index + 1)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.theme_type_variation = full_variation
		UiParts.sized(pip)
		pips.append(pip)
		add_child(pip)


## The number of full pips for `value` (0 to 1).
static func full_of(value: float) -> int:
	return clampi(roundi(clampf(value, 0.0, 1.0) * COUNT), 0, COUNT)


## Shows `value` (0 to 1).
func set_fraction(value: float) -> void:
	fraction = clampf(value, 0.0, 1.0)
	var full := full_of(fraction)
	var look := ALARM if alarmed() else full_variation
	for index in COUNT:
		pips[index].theme_type_variation = look if index < full else EMPTY


## Whether the value is under the alarm line.
func alarmed() -> bool:
	return alarm_below > 0.0 and fraction < alarm_below


## The pips shown full.
func full_count() -> int:
	return pips.filter(func(pip: Panel) -> bool: return pip.theme_type_variation != EMPTY).size()
