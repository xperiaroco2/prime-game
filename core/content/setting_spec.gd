class_name SettingSpec
extends ContentPart
## A match setting (ARCHITECTURE §9.1): a value the host changes in the lobby, declared by the
## mode with its default and bounds. A part names it in a property ending in `_setting`
## (`count_setting = &"knives"`); a part never reads another part's settings.
##
## Two kinds: a whole number (MatchState.settings, bounded by min_value and max_value), or a set
## of the mode's task type ids (MatchState.id_sets; the base mode's `banned_task_types`, #79),
## whose default is the empty set and which has no numbers.

enum Kind {
	## A whole number within min_value and max_value.
	NUMBER,
	## A set of ids of the mode's task types, empty by default.
	TASK_TYPES,
}

@export var id: StringName
@export var display_name: String
@export var kind := Kind.NUMBER
@export var default_value := 0
@export var min_value := 0
@export var max_value := 0


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a setting has no id")
	if kind == Kind.TASK_TYPES:
		if default_value != 0 or min_value != 0 or max_value != 0:
			found.append("setting %s is a set of task types and has no numbers" % id)
		if mode != null and mode.task_types.is_empty():
			found.append("setting %s is a set of task types, but the mode has none" % id)
		return found
	if min_value > max_value:
		found.append("setting %s: min_value %d is above max_value %d" % [id, min_value, max_value])
	append_found(
		found, [out_of_bounds("setting %s default_value" % id, default_value, min_value, max_value)]
	)
	return found


func is_number() -> bool:
	return kind == Kind.NUMBER


func accepts(value: int) -> bool:
	return value >= min_value and value <= max_value
