class_name FixtureTerrainWorld
extends FlatWorldQuery
## A fake world for the movement tests: FlatWorldQuery's floor at y = 0, plus raised platforms,
## each a rectangle in x and z with a flat top. floor_below() answers the highest top (or the
## ground) at or below the point; stand_floor_below() the highest of floor_below() at the point
## and at four points `footprint_radius` from it (+x, -x, +z, -z), as server/'s five rays do
## (ARCHITECTURE §4.5, E10). With a radius of 0 both are one ray.

## Each platform: position = (min x, top y, min z), size = (size x, 0, size z).
var platforms: Array[AABB] = []
## The capsule's radius for stand_floor_below(); 0 by default.
var footprint_radius := 0.0


## Adds a platform from (x0, z0) to (x1, z1) with its top at `top`.
func add_platform(x0: float, z0: float, x1: float, z1: float, top: float) -> FixtureTerrainWorld:
	platforms.append(AABB(Vector3(x0, top, z0), Vector3(x1 - x0, 0.0, z1 - z0)))
	return self


func floor_below(point: Vector3) -> Vector3:
	var found := super.floor_below(point)
	for platform: AABB in platforms:
		var top := platform.position.y
		var inside := (
			point.x >= platform.position.x
			and point.x <= platform.end.x
			and point.z >= platform.position.z
			and point.z <= platform.end.z
		)
		if inside and point.y >= top and (found == NO_FLOOR or top > found.y):
			found = Vector3(point.x, top, point.z)
	return found


func stand_floor_below(point: Vector3) -> Vector3:
	var found := floor_below(point)
	var r := footprint_radius
	for offset: Vector3 in [
		Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)
	]:
		var under := floor_below(point + offset)
		if under != NO_FLOOR and (found == NO_FLOOR or under.y > found.y):
			found = Vector3(point.x, under.y, point.z)
	return found


## FlatWorldQuery's sweep, then each platform as a solid block from the ground to its top.
func sweep(from: Vector3, to: Vector3, radius: float) -> Vector3:
	var stop := super.sweep(from, to, radius)
	if stop == from:
		return from
	var blocks: Array[AABB] = []
	for platform: AABB in platforms:
		var bottom := minf(floor_y, platform.position.y)
		var block_size := Vector3(platform.size.x, platform.position.y - bottom, platform.size.z)
		blocks.append(AABB(Vector3(platform.position.x, bottom, platform.position.z), block_size))
	return sweep_boxes(from, stop, radius, blocks)
