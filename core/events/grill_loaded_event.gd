class_name GrillLoadedEvent
extends MatchEvent
## Cooking's grill took a raw patty (ARCHITECTURE §4.2, §9.5; the cooking ADR's §2.4, CE5, CE10,
## #773): `station` is the grill's station id (StationPlaced's), `item` the patty, now locked on the
## grill, and `fried` and `burnt` the host ticks it turns fried and burnt at, so a client draws the
## ring and expects the two ItemChanged without rounding seconds itself. Taking the patty off is
## Items.give's ItemPickedUp; no event marks the grill empty. It names no player (the ADR's §3, "Who
## did it"), held apart from this declaration by a unit test. Audience: everyone (a client shows it
## only at the grill, seen and heard within its range).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The grill's station id.
var station: int
## The patty's item id.
var item: int
## The host tick the patty turns fried at.
var fried: int
## The host tick the patty turns burnt at.
var burnt: int


func _init(station_id: int, item_id: int, fried_tick: int, burnt_tick: int) -> void:
	station = station_id
	item = item_id
	fried = fried_tick
	burnt = burnt_tick


func event_name() -> StringName:
	return &"GrillLoaded"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "item": item, "fried": fried, "burnt": burnt}
