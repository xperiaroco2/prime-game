class_name FlatWorldQuery
extends WorldQuery
## A fake world for tests and the core scenario runner (ARCHITECTURE §7.1, §9.7): one infinite
## floor at `floor_y`, plus optional walls as boxes. Pure arithmetic, no physics.

## Keeps a placed item this far in front of a wall it would hit.
const WALL_MARGIN := 0.05

var floor_y := 0.0
var walls: Array[AABB] = []


func _init(floor_height: float = 0.0) -> void:
	floor_y = floor_height


func add_wall(box: AABB) -> FlatWorldQuery:
	walls.append(box)
	return self


func line_of_sight(from: Vector3, to: Vector3) -> bool:
	for wall: AABB in walls:
		if wall.intersects_segment(from, to) != null:
			return false
	return true


func floor_below(point: Vector3) -> Vector3:
	if point.y < floor_y:
		return NO_FLOOR
	return Vector3(point.x, floor_y, point.z)


func rest_position(from: Vector3, towards: Vector3) -> Vector3:
	var stop := towards
	var reach := from.distance_to(towards)
	for wall: AABB in walls:
		var hit: Variant = wall.intersects_segment(from, towards)
		if hit is Vector3:
			var at: Vector3 = hit
			var distance := from.distance_to(at)
			if distance < reach:
				reach = distance
				stop = from + (towards - from).normalized() * maxf(0.0, distance - WALL_MARGIN)
	var floor_point := floor_below(stop)
	return floor_point if floor_point != NO_FLOOR else stop
