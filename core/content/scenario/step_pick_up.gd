class_name StepPickUp
extends ScenarioStep
## Sends PickUp of the target item. Done when its ItemPickedUp arrives. (ARCHITECTURE §9.7)

@export var target: ScenarioTarget


func step_name() -> StringName:
	return &"PickUp"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(target, "target"))
	return found
