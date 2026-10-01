class_name StepStopRaise
extends ScenarioStep
## Sends StopRaise: the bot lets go of E. Done when its RaiseStopped arrives (a raise that already
## ended answers with Rejected `not_channeling`, which `expect_rejected` may name).
## (ARCHITECTURE §9.7; M4-4)


func step_name() -> StringName:
	return &"StopRaise"


func sends_intent() -> bool:
	return true
