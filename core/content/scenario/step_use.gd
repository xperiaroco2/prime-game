class_name StepUse
extends ScenarioStep
## Faces `towards` and sends Use, or UseSecondary (the item's own action on the right button,
## the mug's drink) with `secondary`. Done when the event `until` names arrives for this bot
## (Swung, the knife's, by default). (ARCHITECTURE §9.7)

@export var towards: ScenarioTarget
@export var until: StringName = &"Swung"
## Sends UseSecondary instead of Use (#1438).
@export var secondary := false


func step_name() -> StringName:
	return &"UseSecondary" if secondary else &"Use"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(towards, "towards"))
	return found
