class_name StepNextStage
extends ScenarioStep
## The host's bot sends NextStage: a scripted mode (the tutorial's stages) moves on to its next
## phase. Done when a PhaseChanged arrives; a script that wants a given phase follows it with an
## Expect (since this step began). A mode whose phase lists no NextStage (the base mode) answers
## `not_accepted`, which `expect_rejected` can expect. (ARCHITECTURE §9.7; #599)


func step_name() -> StringName:
	return &"NextStage"


func sends_intent() -> bool:
	return true
