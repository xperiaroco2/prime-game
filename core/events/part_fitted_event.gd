class_name PartFittedEvent
extends MatchEvent
## A part was fitted to the car (ARCHITECTURE §4.2, §9.5; the car repair ADR's §2.4, RE10 and
## RE12, #808): the fit at the car completed, and the part left the fitter's hand, locked at the
## car's use spot (Items.lock_at: no ItemPlaced, and no client draws it there). `station` is the
## car's station id (StationPlaced's), `item` the part's item id. The task's TaskState and
## TaskProgress follow it, then PartNeeded with the next part. It names no player: who fitted is
## what the FitChanged before it said. Audience: everyone (the task's success, RD14, #1341).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The car's station id.
var station: int
## The fitted part's item id.
var item: int


func _init(station_id: int, item_id: int) -> void:
	station = station_id
	item = item_id


func event_name() -> StringName:
	return &"PartFitted"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "item": item}
