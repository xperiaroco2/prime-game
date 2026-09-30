class_name StepReturnToLobby
extends ScenarioStep
## The host's bot sends ReturnToLobby. Done when PhaseChanged to the lobby arrives.
## (ARCHITECTURE §9.7)


func step_name() -> StringName:
	return &"ReturnToLobby"


func sends_intent() -> bool:
	return true
