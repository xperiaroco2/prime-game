class_name CountdownPhase
extends Phase
## The base mode's Countdown (ARCHITECTURE §3.2, §9.4). A skeleton of 2a: it declares its intents,
## outcomes and its setting `seconds` (0 to 60; 5); 2b fills in joins, leaves and
## SetReady(false) reporting `cancelled`, and `countdown_done` at its end tick.


func handled_intents() -> Array[StringName]:
	return [Intents.HELLO, Intents.SET_READY]


func outcomes() -> Array[StringName]:
	return [&"cancelled", &"countdown_done"]


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(settings, {&"seconds": Vector2(0, 60)})
