class_name LevelLayout
extends RefCounted
## What core/ is told of one level (ARCHITECTURE §9.3, §9.6): where the deal may place things,
## marker positions by spawn tag, in level order (scene-tree order); and its no-rest volumes, the
## boxes in which a thrown item may not come to rest (§7.1.16, the throwing ADR's TD5 (b)).
## server/'s marker reader (2j) fills it from the `Marker3D` nodes in `spawn_<tag>` groups and the
## `Area3D` boxes in the group `no_rest`; tests build it in code. core/ loads no files, and the
## command log records the layouts, so a replay needs no level.

## The level's path, as the mode names it.
var path: String
var _markers: Dictionary[StringName, PackedVector3Array] = {}
var _no_rest: Array[AABB] = []


func _init(level_path: String = "") -> void:
	path = level_path


func add_marker(tag: StringName, position: Vector3) -> void:
	var at_tag: PackedVector3Array = _markers.get(tag, PackedVector3Array())
	at_tag.append(position)
	_markers[tag] = at_tag


## The markers of `tag`, in level order.
func positions(tag: StringName) -> PackedVector3Array:
	return _markers.get(tag, PackedVector3Array())


func count(tag: StringName) -> int:
	return positions(tag).size()


## The tags, sorted.
func tags() -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(_markers.keys())
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return found


## Adds a no-rest volume: an axis-aligned box in the level's coordinates.
func add_no_rest(volume: AABB) -> void:
	_no_rest.append(volume)


## The no-rest volumes, in level order (a copy).
func no_rest_volumes() -> Array[AABB]:
	return _no_rest.duplicate()


## Whether `point` lies in a no-rest volume. Inclusive: a point on a box's face, edge or corner is
## inside, compared explicitly with each box's position and end (never AABB.has_point's own
## convention), so a floor that a box's face lies on is in it.
func is_no_rest(point: Vector3) -> bool:
	for volume: AABB in _no_rest:
		var low := volume.position
		var high := volume.end
		if (
			point.x >= low.x
			and point.x <= high.x
			and point.y >= low.y
			and point.y <= high.y
			and point.z >= low.z
			and point.z <= high.z
		):
			return true
	return false


## Plain data for the command log. `no_rest` only when the level has volumes, so a level without
## them gives the same data as before they existed.
func to_dict() -> Dictionary:
	var markers := {}
	for tag: StringName in tags():
		markers[String(tag)] = positions(tag)
	var data := {"path": path, "markers": markers}
	if not _no_rest.is_empty():
		data["no_rest"] = _no_rest.duplicate()
	return data
