class_name LobbyPhase
extends Phase
## The base mode's Lobby (ARCHITECTURE §3.2, §9.4). A skeleton of 2a: it declares the intents it
## handles and the outcome it reports, so the base mode's data and ModeCheck are complete; 2b
## fills in joins (Hello, Welcome, PlayerJoined), SetReady, ChangeSettings, leaves, AllowJoins
## and `all_ready`. Until then its intents are rejected with `nothing_to_do`.


func handled_intents() -> Array[StringName]:
	return [Intents.HELLO, Intents.SET_READY, Intents.CHANGE_SETTINGS]


func outcomes() -> Array[StringName]:
	return [&"all_ready"]
