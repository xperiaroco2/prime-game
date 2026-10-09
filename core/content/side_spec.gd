class_name SideSpec
extends ContentPart
## A side a player can win with (ARCHITECTURE §9.3): the base mode's `crew` and `dissidents`.
## MatchEnded names only the winning side; the end screen shows the copy deck's line for its id.

@export var id: StringName
@export var display_name: String


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a side has no id")
	return found
