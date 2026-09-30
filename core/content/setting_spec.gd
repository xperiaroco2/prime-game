class_name SettingSpec
extends ContentPart
## A match setting (ARCHITECTURE §9.1): a value the host changes in the lobby, declared by the
## mode with its default and bounds. A part names it in a property ending in `_setting`
## (`count_setting = &"knives"`); a part never reads another part's settings. Whole numbers in v0.

@export var id: StringName
@export var display_name: String
@export var default_value := 0
@export var min_value := 0
@export var max_value := 0


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a setting has no id")
	if min_value > max_value:
		found.append("setting %s: min_value %d is above max_value %d" % [id, min_value, max_value])
	append_found(
		found, [out_of_bounds("setting %s default_value" % id, default_value, min_value, max_value)]
	)
	return found


func accepts(value: int) -> bool:
	return value >= min_value and value <= max_value
