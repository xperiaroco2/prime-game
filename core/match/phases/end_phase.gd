class_name EndPhase
extends Phase
## The base mode's End (ARCHITECTURE §3.2, §9.4). A skeleton of 2a: it declares ReturnToLobby and
## the outcome `back`; 2b fills in the host's ReturnToLobby reporting `back`, and leaves.


func handled_intents() -> Array[StringName]:
	return [Intents.RETURN_TO_LOBBY]


func outcomes() -> Array[StringName]:
	return [&"back"]
