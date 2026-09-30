class_name StepJoin
extends ScenarioStep
## Sends Hello `at_s` seconds after the start instead of at once: a late join that cancels
## the countdown, or one refused in Loading. Done when its Welcome arrives. (ARCHITECTURE §9.7)

## Seconds after the start.
@export var at_s := 0.0


func step_name() -> StringName:
	return &"Join"


func sends_intent() -> bool:
	return true


func problems() -> PackedStringArray:
	var found := super()
	if at_s < 0.0:
		found.append("at_s is negative")
	return found
