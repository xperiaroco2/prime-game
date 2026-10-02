class_name ItemPickedUpEvent
extends MatchEvent
## A player took an item into the hand (ARCHITECTURE §4.2, §7.1): `PickUp`. `belted` is the
## one-handed item this pickup moved from the hand to the empty belt, or -1 (E29): a hand item that
## did not fit the belt rests where the picked item lay, and its ItemPlaced (swap) follows. Who
## carries what is public. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
var item: int
var belted: int


func _init(by_peer: int, item_id: int, belted_id: int = -1) -> void:
	peer = by_peer
	item = item_id
	belted = belted_id


func event_name() -> StringName:
	return &"ItemPickedUp"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "item": item, "belted": belted}
