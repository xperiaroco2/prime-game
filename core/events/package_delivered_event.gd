class_name PackageDeliveredEvent
extends MatchEvent
## A package came to rest inside its own circle (ARCHITECTURE §4.2, §7.1): it is locked (no
## longer interactive) and its circle is shown as done. It names no task and no player: tasks are
## shared (#79), and the binding of a package to its circle is public (ItemSpawned). Audience:
## everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var item: int
## The package's circle, now shown as done.
var station: int


func _init(item_id: int, station_id: int) -> void:
	item = item_id
	station = station_id


func event_name() -> StringName:
	return &"PackageDelivered"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item, "station": station}
