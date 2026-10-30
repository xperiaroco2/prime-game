class_name AtMarker
extends Condition
## Passes when the actor's feet, the position of its last accepted claim (never a position inside
## the intent; ARCHITECTURE §7.1), stand inside the cylinder of any marker of `tag` on the level
## the match plays (MatchContext.layout): within `radius_m` of the marker horizontally and from
## the marker's height up to `height_m` above it, the same cylinder as a station's
## (StationState.contains). It needs no target: the place is the level's, so an intent with no
## arguments can be gated by where its sender stands (the camera wall's chair: the base mode's
## Pose, #1383). A level without a marker of the tag, or no level, refuses. Rejects with
## `out_of_reach`: the sender knows its own position, and the markers are in the level's scene,
## which every client loads (ARCHITECTURE §9.6).

const OUT_OF_REACH := &"out_of_reach"

## The spawn tag of the markers (`spawn_<tag>`, §9.6). A tag the level lacks is no marker at all,
## never a load error: LayoutCheck demands no condition's tag, so a map without the place simply
## has none.
@export var tag: StringName
## Metres, 0.2 to 10, as a station kind's. The neutral defaults are out of bounds on purpose: the
## data sets them, so the mode check refuses a rule that forgot them.
@export var radius_m := 0.0
## Metres above the marker, 0.1 to 10.
@export var height_m := 0.0


## It reads the actor's position (the default) and no target.
func needs_target() -> bool:
	return false


func _test(ctx: MatchContext) -> bool:
	var actor := ctx.actor_state()
	if actor == null or ctx.layout == null:
		return false
	for marker: Vector3 in ctx.layout.positions(tag):
		if contains(actor.position, marker, radius_m, height_m):
			return true
	return false


func _reason() -> StringName:
	return OUT_OF_REACH


## Whether `point` is inside the cylinder standing at `marker`, `radius_m` wide and `height_m`
## tall: StationState.contains's geometry (edges included, StationState.FLOOR_SLACK_M of float
## noise below the marker). Static, so the client gates its key on the same test (PoseUse).
static func contains(point: Vector3, marker: Vector3, radius: float, height: float) -> bool:
	var flat := Vector2(point.x - marker.x, point.z - marker.z)
	var rise := point.y - marker.y
	return flat.length() <= radius and rise >= -StationState.FLOOR_SLACK_M and rise <= height


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if tag.is_empty():
		found.append("AtMarker has no tag")
	append_found(
		found,
		[
			out_of_bounds("AtMarker radius_m", radius_m, 0.2, 10),
			out_of_bounds("AtMarker height_m", height_m, 0.1, 10),
		]
	)
	return found
