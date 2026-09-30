class_name StationState
extends RefCounted
## One placed task station in MatchState (ARCHITECTURE §9.1): the MVP's delivery circle. Public:
## StationPlaced shows it to everyone.

var id: int
var kind: StationKind
var position := Vector3.ZERO
var colour := Color.WHITE
## Shown as done (a delivered package's circle).
var done := false


func _init(station_id: int, station_kind: StationKind, at: Vector3, station_colour: Color) -> void:
	id = station_id
	kind = station_kind
	position = at
	colour = station_colour
