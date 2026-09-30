class_name ContentPart
extends Resource
## The base of every content-API part (ARCHITECTURE §9.1, §9.3): a stateless definition whose
## settings are its exported properties, in the units a person thinks in (seconds, metres,
## degrees, whole points).
##
## A part holds no match state: Godot shares a loaded resource between every load of its path,
## so a counter here would leak between matches, tests and replays. What changes lives in
## MatchState, or in the current phase object (§9.1).


## What the mode check (§9.1) reports about this part: numbers outside their bounds, and names
## (roles, sides, item kinds) that `mode` does not declare. A property ending in `_setting` is
## checked for every part by ModeCheck. Empty when the part is fine.
func check(_mode: GameMode) -> PackedStringArray:
	return PackedStringArray()


## "<name> is <value>, outside <low> to <high>", or "" when `value` is within the bounds.
static func out_of_bounds(name: String, value: float, low: float, high: float) -> String:
	if value >= low and value <= high:
		return ""
	return "%s is %s, outside %s to %s" % [name, number(value), number(low), number(high)]


## A number as a person writes it: 5, not 5.0; 0.5 stays 0.5.
static func number(value: float) -> String:
	return str(int(value)) if value == floorf(value) and absf(value) < 1e15 else str(value)


## The names of this part's `_setting` properties that hold a set of ids (SettingSpec.Kind
## TASK_TYPES, #79); ModeCheck requires every other `_setting` property to name a whole number,
## so a part that reads a number never reads a set as 0. Empty by default.
func set_settings() -> PackedStringArray:
	return PackedStringArray()


## Appends the non-empty messages of `found` to `into`.
static func append_found(into: PackedStringArray, found: Array[String]) -> void:
	for message: String in found:
		if not message.is_empty():
			into.append(message)
