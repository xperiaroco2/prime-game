class_name StationPlacedEvent
extends MatchEvent
## A task station was placed by the deal (ARCHITECTURE §3.3, §4.2): in the MVP a delivery circle.
## Emitted in station-id order, and ids follow spawn-point order, so an id says nothing about the
## task it belongs to. Stations are public. Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var station: int
## The StationKind's id (Delivery: `circle`).
var kind: StringName
var colour: Color
var position: Vector3


func _init(station_id: int, kind_id: StringName, station_colour: Color, at: Vector3) -> void:
	station = station_id
	kind = kind_id
	colour = station_colour
	position = at


func event_name() -> StringName:
	return &"StationPlaced"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "kind": kind, "colour": colour, "position": position}
