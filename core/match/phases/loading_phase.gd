class_name LoadingPhase
extends Phase
## The base mode's Loading (ARCHITECTURE §3.2, §9.4). A skeleton of 2a: it declares LoadAck, the
## outcome `all_loaded` and its setting `deadline_seconds` (5 to 600; 60); 2b fills in
## RefuseJoins, LoadMatch, the acks, the deadline and DisconnectPeer.


func handled_intents() -> Array[StringName]:
	return [Intents.LOAD_ACK]


func outcomes() -> Array[StringName]:
	return [&"all_loaded"]


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(settings, {&"deadline_seconds": Vector2(5, 600)})
