class_name FixtureFlightWorld
extends FixtureTerrainWorld
## A fake world for the flight tests: FixtureTerrainWorld (a floor at `floor_y`, walls, platforms)
## that records every sweep's arguments, and that can end at a ledge: past `ledge_x` there is no
## floor at all (floor_below answers NO_FLOOR, and a segment wholly past it meets only the walls),
## a level with a hole.

## Each sweep asked, as [from, to, radius], in order.
var sweeps: Array[Array] = []
## No floor where x > ledge_x.
var ledge_x := INF


func _init(floor_height: float = 0.0, ledge: float = INF) -> void:
	super(floor_height)
	ledge_x = ledge


func floor_below(point: Vector3) -> Vector3:
	if point.x > ledge_x:
		return NO_FLOOR
	return super.floor_below(point)


func sweep(from: Vector3, to: Vector3, radius: float) -> Vector3:
	sweeps.append([from, to, radius])
	if from.x > ledge_x and to.x > ledge_x:
		return sweep_boxes(from, to, radius, walls)
	return super.sweep(from, to, radius)
