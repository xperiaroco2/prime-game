class_name ItemKindIs
extends TutorialCondition
## Condition: the fired event's `item` is of `kind` in the own model (docs/design/tutorial.md §3).
## It reads the event, so it fits only a step's `conditions`.

@export var kind: StringName = &""


func part_name() -> StringName:
	return &"ItemKindIs"


func reads_event() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if kind.is_empty():
		found.append("ItemKindIs: no kind")
	return found
