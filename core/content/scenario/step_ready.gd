class_name StepReady
extends ScenarioStep
## Sends SetReady. Done when its ReadyChanged arrives. (ARCHITECTURE §9.7)

@export var ready := true


func step_name() -> StringName:
	return &"Ready"


func sends_intent() -> bool:
	return true
