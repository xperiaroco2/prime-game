class_name ProfileChangedEvent
extends MatchEvent
## A player's accepted SetProfile in the lobby (ARCHITECTURE §3.5, §4.2, #551): its name and body
## colour as the host settled them (the name cleaned and made unique, a taken colour moved to the
## first free one). Both are public (the engineer's answers on #73). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
var player_name: String
## An index into PlayerColours.
var colour: int


func _init(of_peer: int, new_name: String, new_colour: int) -> void:
	peer = of_peer
	player_name = new_name
	colour = new_colour


func event_name() -> StringName:
	return &"ProfileChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "name": player_name, "colour": colour}
