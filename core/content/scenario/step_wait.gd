class_name StepWait
extends ScenarioStep
## Waits `seconds`. (ARCHITECTURE §9.7)

@export var seconds := 0.0


func step_name() -> StringName:
	return &"Wait"


func problems() -> PackedStringArray:
	var found := super()
	if seconds < 0.0:
		found.append("seconds is negative")
	return found
