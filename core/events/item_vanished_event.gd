class_name ItemVanishedEvent
extends MatchEvent
## An item left the match for good (ARCHITECTURE §4.2; the cooking ADR, CD6 (c), CE3): it lay on
## the ground its kind's `vanish_seconds` (VanishTicks), or a take at its kind's cap removed it
## (C1). Its id may later name a new item (MatchState.add_item). Items on the ground are public,
## and the event names no player. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var item: int


func _init(item_id: int) -> void:
	item = item_id


func event_name() -> StringName:
	return &"ItemVanished"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item}
