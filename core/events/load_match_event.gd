class_name LoadMatchEvent
extends MatchEvent
## Entering Loading (ARCHITECTURE §3.2, §4.2): which match to load, on which map, with which
## settings. Each player answers with LoadAck(match_id). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The index of the match in the session (0 for the first): an ack naming another is stale.
var match_id: int
var map: String
var settings: Dictionary[StringName, int] = {}


func _init(id: int, map_path: String, values: Dictionary[StringName, int]) -> void:
	match_id = id
	map = map_path
	settings = values.duplicate()


func event_name() -> StringName:
	return &"LoadMatch"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"match_id": match_id, "map": map, "settings": settings.duplicate()}
