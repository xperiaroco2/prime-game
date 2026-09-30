class_name WorldQuery
extends RefCounted
## The port through which core/ asks the geometric questions of the rules (ARCHITECTURE §7.1):
## line of sight, the floor below a point, and where an item placed from A towards B comes to
## rest. server/ implements it over its own World3D of the level's static colliders (M3); unit
## tests use FlatWorldQuery. Match records every answer in the command log, so a replay reads
## them instead of asking a level (§3.3). This base class answers like an empty world with no
## floor: override every method.

## floor_below()'s answer when there is no floor below the point.
const NO_FLOOR := Vector3.INF


## Whether the segment from `from` to `to` is clear of walls.
func line_of_sight(_from: Vector3, _to: Vector3) -> bool:
	return true


## The floor point below `point`, or NO_FLOOR.
func floor_below(_point: Vector3) -> Vector3:
	return NO_FLOOR


## Where an item placed from `from` towards `towards` comes to rest: stopped before a wall and
## dropped to the floor.
func rest_position(_from: Vector3, towards: Vector3) -> Vector3:
	return towards
