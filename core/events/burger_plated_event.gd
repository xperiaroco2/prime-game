class_name BurgerPlatedEvent
extends MatchEvent
## A full plate was taken from one of Cooking's places (ARCHITECTURE §4.2, §9.5; the cooking ADR's
## amendment of 2026-10-15, #1101): `item` the new burger (its ItemSpawned and ItemPickedUp come
## first, after the ItemVanished of the plate's three items), `station` the place's station id,
## and `bun`, `patty` and `herb` the kind ids on its slots, so a client draws the burger. Whether
## they are the order's is never said before the burger is served (BurgerServed). It names no
## player (the ADR's §3, "Who did it"): the taker is the holder ItemPickedUp names anyway.
## Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The burger's item id.
var item: int
## The place's station id.
var station: int
## The kind ids on its three slots.
var bun: StringName
var patty: StringName
var herb: StringName


func _init(
	item_id: int, station_id: int, bun_id: StringName, patty_id: StringName, herb_id: StringName
) -> void:
	item = item_id
	station = station_id
	bun = bun_id
	patty = patty_id
	herb = herb_id


func event_name() -> StringName:
	return &"BurgerPlated"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item, "station": station, "bun": bun, "patty": patty, "herb": herb}
