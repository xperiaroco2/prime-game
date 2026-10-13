class_name PhotoHungEvent
extends MatchEvent
## A photo was hung on the board (ARCHITECTURE §4.2, §9.5; the photo ADR §2.7, PE9, #782) by an
## accepted Interact: the photo's item id, the board's station id and whether it counted (its shot
## has a person). Counted, the photo is locked on the board for good and the task's TaskState,
## TaskProgress follow; not counted, it lies on the board, where PickUp takes it down (PD6). No
## ItemPlaced: this event says where the photo went. It names no player. Audience: everyone (the
## board shows what is hung on it, and the count is the public task state).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The photo's item id.
var item: int
## The board's station id.
var station: int
## Whether the photo counted: locked for good, a subtask done.
var counted: bool


func _init(item_id: int, station_id: int, is_counted: bool) -> void:
	item = item_id
	station = station_id
	counted = is_counted


func event_name() -> StringName:
	return &"PhotoHung"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"item": item, "station": station, "counted": counted}
