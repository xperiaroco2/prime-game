class_name StepReturnToLobby
extends ScenarioStep
## The host's bot sends ReturnToLobby. Done when PhaseChanged to the lobby arrives.
## (ARCHITECTURE §9.7) The base mode's End returns everyone by itself after its `seconds` (#212):
## a script waits for that with WaitFor(PhaseChanged, lobby); this step is the host's shortcut.


func step_name() -> StringName:
	return &"ReturnToLobby"


func sends_intent() -> bool:
	return true
