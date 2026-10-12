class_name PartNeededEvent
extends MatchEvent
## The part the car needs next (ARCHITECTURE §4.2, §9.5; the car repair ADR's RE10, RD3, #807): sent
## at the deal, after the StationPlaced events, and after each fit. `station` is the picture's
## station id (the `part_picture` display kind on the garage wall), `kind` the needed part's item
## kind id, or empty when none is needed (no subtasks, or the last part fitted). An honest client
## draws the part's picture there, in the world, depth-tested, never through walls (DD4). It names
## no player. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The picture's station id.
var station: int
## The needed part's item kind id; empty for none.
var kind: StringName


func _init(station_id: int, kind_id: StringName) -> void:
	station = station_id
	kind = kind_id


func event_name() -> StringName:
	return &"PartNeeded"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "kind": kind}
