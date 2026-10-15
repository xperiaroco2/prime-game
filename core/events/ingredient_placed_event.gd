class_name IngredientPlacedEvent
extends MatchEvent
## An ingredient went onto a free slot of one of Cooking's places, locked there (ARCHITECTURE §4.2,
## §9.5; the cooking ADR's §2.5, CE5, #773, and its amendment of 2026-10-15, #1101): `item` the
## ingredient, `station` the place's station id (StationPlaced's). Whether it is the order's is
## never said: a burger is checked only when it is served (BurgerServed). It names no player (the
## ADR's §3, "Who did it"), held apart from this declaration by a unit test. Audience: everyone (a
## client shows it only on the plate).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The ingredient's item id.
var item: int
## The place's station id.
var station: int


func _init(item_id: int, station_id: int) -> void:
	item = item_id
	station = station_id


func event_name() -> StringName:
	return &"IngredientPlaced"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item, "station": station}
