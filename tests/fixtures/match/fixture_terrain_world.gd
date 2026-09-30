class_name FixtureTerrainWorld
extends FlatWorldQuery
## A fake world for the movement tests: FlatWorldQuery's floor at y = 0, plus raised platforms,
## each a rectangle in x and z with a flat top. floor_below() answers the highest top (or the
## ground) at or below the point.

## Each platform: position = (min x, top y, min z), size = (size x, 0, size z).
var platforms: Array[AABB] = []


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
