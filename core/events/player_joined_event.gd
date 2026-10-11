class_name PlayerJoinedEvent
extends MatchEvent
## A peer's Hello was accepted (ARCHITECTURE §3.5, §4.2): its name, its body colour (an index into
## PlayerColours, #551) and the lobby spawn point it was placed at. The joiner receives it too,
## after its Welcome. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
var player_name: String
var spot: Vector3
var colour: int


func _init(joiner: int, joiner_name: String, at: Vector3, joiner_colour: int) -> void:
	peer = joiner
	player_name = joiner_name
	spot = at
	colour = joiner_colour


func event_name() -> StringName:
	return &"PlayerJoined"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "name": player_name, "spot": spot, "colour": colour}
