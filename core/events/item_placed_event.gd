class_name ItemPlacedEvent
extends MatchEvent
## An item came to rest on the ground (ARCHITECTURE §4.2, §7.1): its rest position and the cause,
## put down, swap, death, leave or the end of a throw's flight (Items). Items on the ground are
## public. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var item: int
var position: Vector3
## Items.PUT_DOWN, SWAP, DEATH, LEAVE or THROWN.
var cause: StringName


func _init(item_id: int, at: Vector3, why: StringName) -> void:
	item = item_id
	position = at
	cause = why


func event_name() -> StringName:
	return &"ItemPlaced"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item, "position": position, "cause": cause}
