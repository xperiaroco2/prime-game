class_name CrystalSocketChangedEvent
extends MatchEvent
## The ship's engine's burnt crystal (ARCHITECTURE §4.2, §9.5.27; GDD §8): the socket `station`'s
## crystal is out as the item `item` (pulled: ItemSpawned and ItemPickedUp follow), or back in its
## socket (`item` -1: fitted, or returned by a blast; the item vanished). A socket without an item
## out holds its crystal, spent while a problem holds the socket. It names no player. Audience:
## everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The socket station.
var station: int
## The crystal out of it, or -1 when it is in.
var item: int


func _init(station_id: int, item_id: int) -> void:
	station = station_id
	item = item_id


func event_name() -> StringName:
	return &"CrystalSocketChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "item": item}
