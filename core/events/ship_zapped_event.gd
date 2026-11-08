class_name ShipZappedEvent
extends MatchEvent
## The ship zapped its carrier as the crystal passed the edge of the aboard box (ARCHITECTURE §4.2,
## §9.5.27; GDD §8 "The ship is in an emergency mode", #1585): the crystal has gone from its hands
## (ItemPlaced, cause `zapped`, everyone: the world's sound comes from that). It names the carrier,
## its only reader; the flash, the shake and the notice are its own, their numbers in the client's
## copy of the mode.
## Audience: only the carrier.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.ONLY

var peer: int


func _init(carrier: int) -> void:
	peer = carrier


func event_name() -> StringName:
	return &"ShipZapped"


func audience() -> Audience:
	return Audience.only(peer)


func to_dict() -> Dictionary:
	return {"peer": peer}
