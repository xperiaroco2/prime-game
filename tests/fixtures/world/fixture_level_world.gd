class_name FixtureLevelWorld
extends FlatWorldQuery
## A flat world that writes down which level Match points it at and each question it is asked, in
## order (ARCHITECTURE §4.5, E9): "use_level <path>" and "floor_below".

var calls := PackedStringArray()


func use_level(path: String) -> void:
	calls.append("use_level %s" % path)


func floor_below(point: Vector3) -> Vector3:
	calls.append("floor_below")
	return super.floor_below(point)
