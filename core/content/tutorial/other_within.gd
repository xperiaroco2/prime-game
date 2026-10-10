class_name OtherWithin
extends TutorialCondition
## Condition: another living player stands within `metres` of the own player, the others from the
## own model's latest snapshot, the own from the local player (docs/design/tutorial.md §3).

## Metres, its edge included; 0: the current phase's voice radius (VoiceRule.radius_of).
@export var metres := 0.0


func part_name() -> StringName:
	return &"OtherWithin"


func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if metres < 0.0:
		found.append("OtherWithin: metres %s below 0" % metres)
	return found
