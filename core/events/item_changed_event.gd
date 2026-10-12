class_name ItemChangedEvent
extends MatchEvent
## An item became another kind (ARCHITECTURE §4.2; the cooking ADR, CE4): Items.change_kind, such
## as a patty on the grill turning fried, then burnt. The item keeps its id, its place and its
## holder; only its kind (its look, its display name, the rules it follows) changes. Items are
## public, and the event names no player. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var item: int
var kind: StringName


func _init(item_id: int, kind_id: StringName) -> void:
	item = item_id
	kind = kind_id


func event_name() -> StringName:
	return &"ItemChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item, "kind": kind}
