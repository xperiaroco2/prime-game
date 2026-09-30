class_name PlayerJoinedEvent
extends MatchEvent
## A peer's Hello was accepted (ARCHITECTURE §3.5, §4.2): its name and the lobby spawn point it was
## placed at. The joiner receives it too, after its Welcome. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
var player_name: String
var spot: Vector3


func _init(joiner: int, joiner_name: String, at: Vector3) -> void:
	peer = joiner
	player_name = joiner_name
	spot = at


func event_name() -> StringName:
	return &"PlayerJoined"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "name": player_name, "spot": spot}
