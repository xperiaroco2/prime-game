class_name StationState
extends RefCounted
## One placed task station in MatchState (ARCHITECTURE §9.1): a delivery circle or a zone (#36),
## an invisible cylinder standing on the floor at its marker. Public: StationPlaced shows it to
## everyone.

## How far below its floor a point still counts as inside (contains): float noise between a floor
## the host's physics finds and a hand-placed marker, not a tolerance for a raised marker (§9.6).
## A placeholder, not a decision.
const FLOOR_SLACK_M := 0.001

var id: int
var kind: StationKind
var position := Vector3.ZERO
var colour := Color.WHITE
## Shown as done (a delivered package's circle, a zone that reached its time).
var done := false


func _init(station_id: int, station_kind: StationKind, at: Vector3, station_colour: Color) -> void:
	id = station_id
	kind = station_kind
	position = at
	colour = station_colour


## Whether `point` is inside the station's cylinder (#79, ZE2 of the zone task ADR): it stands on
## the floor at its marker, `radius_m` wide and `height_m` tall. Inside means within the radius
## horizontally, edge included, and from the floor (the marker's height) up to floor + height,
## both included, the floor with FLOOR_SLACK_M of float noise below it. Delivery asks it with a
## package's rest position (the centre of its base on the surface it rests on, §7.1), the zone
## task with a player's feet (the last accepted claim, §7): a point on a crate inside counts, one
## on a floor below the marker or above the cylinder does not.
func contains(point: Vector3) -> bool:
	var flat := Vector2(point.x - position.x, point.z - position.z)
	var rise := point.y - position.y
	return flat.length() <= kind.radius_m and rise >= -FLOOR_SLACK_M and rise <= kind.height_m
