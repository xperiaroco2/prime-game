class_name FixtureLevelWorld
extends FlatWorldQuery
## A flat world that writes down which level Match points it at and each question it is asked, in
## order (ARCHITECTURE §4.5, E9, E10): "use_level <path>", "floor_below", "stand_floor_below" and
## "sweep". It answers on FlatWorldQuery's floor and walls.

var calls := PackedStringArray()


func use_level(path: String) -> void:
	calls.append("use_level %s" % path)


func floor_below(point: Vector3) -> Vector3:
	calls.append("floor_below")
	return super.floor_below(point)


func stand_floor_below(point: Vector3) -> Vector3:
	calls.append("stand_floor_below")
	return super.stand_floor_below(point)


func sweep(from: Vector3, to: Vector3, radius: float) -> Vector3:
	calls.append("sweep")
	return super.sweep(from, to, radius)
