class_name OwnLife
extends TutorialCondition
## Condition: the own player's life is `life`, as the own model tells it (docs/design/tutorial.md
## §3). By name, so core/ data never names a client or match state class.

## The lives, in the order of ClientModel.Life (a test holds both lists in step).
const LIVES: Array[StringName] = [&"alive", &"downed", &"dead", &"left"]

## One of LIVES.
@export var life: StringName = &"alive"


func part_name() -> StringName:
	return &"OwnLife"


func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if not LIVES.has(life):
		found.append("OwnLife: unknown life '%s'" % life)
	return found
