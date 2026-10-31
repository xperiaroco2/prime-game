class_name FixtureToggleWorld
extends FlatWorldQuery
## FlatWorldQuery whose toggles are walls (#1295): a toggle part given by add_part is a box that
## stands while its toggle is off and is gone while it is on, as the host's LevelWorld takes a
## collider out; `calls` lists every set_toggle ("<key> <index> on|off") and reset_toggles
## ("reset"), in order. Match asks it through RecordingWorldQuery while it records, so a call the
## wrapper does not forward never arrives here.

var calls: Array[String] = []
var _parts: Dictionary[String, AABB] = {}
var _open: Dictionary[String, bool] = {}


## A part of toggle `key`'s `index`: the wall `box` while the toggle is off.
func add_part(key: StringName, index: int, box: AABB) -> FixtureToggleWorld:
	_parts["%s %d" % [key, index]] = box
	return self


func set_toggle(key: StringName, index: int, on: bool) -> void:
	calls.append("%s %d %s" % [key, index, "on" if on else "off"])
	_open["%s %d" % [key, index]] = on


func reset_toggles() -> void:
	calls.append("reset")
	_open.clear()


func line_of_sight(from: Vector3, to: Vector3) -> bool:
	for part: String in _parts:
		if not _open.get(part, false) and _parts[part].intersects_segment(from, to) != null:
			return false
	return super.line_of_sight(from, to)
