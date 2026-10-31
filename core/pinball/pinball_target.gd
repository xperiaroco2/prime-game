class_name PinballTarget
extends ContentPart
## A target of the pinball table and its points (#1398; ARCHITECTURE §7.1.22, §9.4): the table
## (server/, #1399) reports a hit by `id` (TargetHit), and the game adds `points`. UsePinball holds
## the machine's targets.

## The id the table's TargetHit names.
@export var id: StringName
## The points a hit adds.
@export var points := 0


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id == &"":
		found.append("PinballTarget needs an id")
	append_found(found, [out_of_bounds("points", points, 1, 100000)])
	return found
