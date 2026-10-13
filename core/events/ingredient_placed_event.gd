class_name IngredientPlacedEvent
extends MatchEvent
## An ingredient went onto one of Cooking's places (ARCHITECTURE §4.2, §9.5; the cooking ADR's
## §2.5, CE5, #773): `item` the ingredient, `station` the place's station id (StationPlaced's), and
## `right` whether it fills one of the order's empty slots (locked there, drawn green) or not (it
## lies on the ground at the place, interactive, drawn red, and PickUp takes it back). It names no
## player (the ADR's §3, "Who did it"), held apart from this declaration by a unit test. Audience:
## everyone (a client shows it only on the plate).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The ingredient's item id.
var item: int
## The place's station id.
var station: int
## Whether it filled an empty slot of the order (green), or lies there wrong (red).
var right: bool


func _init(item_id: int, station_id: int, is_right: bool) -> void:
	item = item_id
	station = station_id
	right = is_right


func event_name() -> StringName:
	return &"IngredientPlaced"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item, "station": station, "right": right}
