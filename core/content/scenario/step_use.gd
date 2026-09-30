class_name StepUse
extends ScenarioStep
## Faces `towards` and sends Use. Done when the event `until` names arrives for this bot
## (Swung, the knife's, by default). (ARCHITECTURE §9.7)

@export var towards: ScenarioTarget
@export var until: StringName = &"Swung"


func step_name() -> StringName:
	return &"Use"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(towards, "towards"))
	return found
