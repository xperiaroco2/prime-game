class_name LevelLayout
extends RefCounted
## Where the deal may place things in one level (ARCHITECTURE §9.3, §9.6): marker positions by
## spawn tag, in level order (scene-tree order). server/'s marker reader (2j) fills it from the
## `Marker3D` nodes in `spawn_<tag>` groups; tests build it in code. core/ loads no files, and the
## command log records the layouts, so a replay needs no level.

## The level's path, as the mode names it.
var path: String
var _markers: Dictionary[StringName, PackedVector3Array] = {}


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


## Plain data for the command log.
func to_dict() -> Dictionary:
	var markers := {}
	for tag: StringName in tags():
		markers[String(tag)] = positions(tag)
	return {"path": path, "markers": markers}
