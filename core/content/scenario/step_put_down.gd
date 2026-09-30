class_name StepPutDown
extends ScenarioStep
## Faces `towards` and sends PutDown. Done when ItemPlaced of the item it held arrives.
## (ARCHITECTURE §9.7)

@export var towards: ScenarioTarget


func step_name() -> StringName:
	return &"PutDown"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	found.append_array(target_problems(towards, "towards"))
	return found
