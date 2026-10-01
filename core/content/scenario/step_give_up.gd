class_name StepGiveUp
extends ScenarioStep
## Sends GiveUp: the downed bot dies at once. Done when its own Died arrives.
## (ARCHITECTURE §9.7; M4-4)


func step_name() -> StringName:
	return &"GiveUp"


func sends_intent() -> bool:
	return true
