class_name PlayersPlacedEvent
extends MatchEvent
## Where a placement put every player (ARCHITECTURE §3.2, §4.2): on `End -> Lobby` and in the
## deal. Positions are public; each player's new epoch goes out privately in a Correction.
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## Peer -> the spawn point it was placed at.
var spots: Dictionary[int, Vector3] = {}


func _init(placed: Dictionary[int, Vector3]) -> void:
	spots = placed.duplicate()


func event_name() -> StringName:
	return &"PlayersPlaced"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"spots": spots.duplicate()}
