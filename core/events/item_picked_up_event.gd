class_name ItemPickedUpEvent
extends MatchEvent
## A player took an item into the hand (ARCHITECTURE §4.2, §7.1): `PickUp`. Who holds what is
## public. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var peer: int
var item: int


func _init(by_peer: int, item_id: int) -> void:
	peer = by_peer
	item = item_id


func event_name() -> StringName:
	return &"ItemPickedUp"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"peer": peer, "item": item}
