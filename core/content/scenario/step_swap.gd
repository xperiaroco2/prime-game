class_name StepSwap
extends ScenarioStep
## Sends Swap: the bot's hand and belt items change places. Done when its own Swapped arrives.
## (ARCHITECTURE §9.7; M4-5)


func step_name() -> StringName:
	return &"Swap"


func sends_intent() -> bool:
	return true
