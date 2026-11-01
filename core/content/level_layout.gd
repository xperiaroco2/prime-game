class_name LevelLayout
extends RefCounted
## Where the deal may place things in one level (ARCHITECTURE §9.3, §9.6): marker positions by
## spawn tag, in level order (scene-tree order), and each marker's facing (#1522: its yaw as a
## level unit vector, which a placement on it gives the player). server/'s marker reader (2j) fills
## it from the `Marker3D` nodes in `spawn_<tag>` groups; tests build it in code, where a marker
## added without a facing has none (Vector3.ZERO: a placement there keeps the player's look). core/
## loads no files, and the command log records the layouts, so a replay needs no level.

## The level's path, as the mode names it.
var path: String
var _markers: Dictionary[StringName, PackedVector3Array] = {}
## Per tag, parallel to _markers: each marker's facing, Vector3.ZERO for none.
var _facings: Dictionary[StringName, PackedVector3Array] = {}


func _init(level_path: String = "") -> void:
	path = level_path


## Adds a marker of `tag` at `position`, facing `facing` (level_facing of it: only its yaw counts;
## Vector3.ZERO, or a vertical one, for none).
func add_marker(tag: StringName, position: Vector3, facing := Vector3.ZERO) -> void:
	add_recorded_marker(tag, position, level_facing(facing))


## Adds a marker of `tag` at `position` with `facing` stored as it is: one that facings() gave,
## read back from a command log. level_facing again could change its last bit (a float32 normalize
## is not idempotent), and a replay must place players with the recorded facings.
func add_recorded_marker(tag: StringName, position: Vector3, facing: Vector3) -> void:
	var at_tag: PackedVector3Array = _markers.get(tag, PackedVector3Array())
	at_tag.append(position)
	_markers[tag] = at_tag
	var faced: PackedVector3Array = _facings.get(tag, PackedVector3Array())
	faced.append(facing)
	_facings[tag] = faced


## The yaw of `direction` as a level unit vector (y 0), or Vector3.ZERO when it has no yaw (zero or
## vertical). The marker reader passes a marker's forward (-basis.z).
static func level_facing(direction: Vector3) -> Vector3:
	var level := Vector3(direction.x, 0.0, direction.z)
	if level.length_squared() < 1e-8:
		return Vector3.ZERO
	return level.normalized()


## The markers of `tag`, in level order.
func positions(tag: StringName) -> PackedVector3Array:
	return _markers.get(tag, PackedVector3Array())


## The facings of the markers of `tag`, parallel to positions(tag): each a level unit vector, or
## Vector3.ZERO for a marker with none.
func facings(tag: StringName) -> PackedVector3Array:
	return _facings.get(tag, PackedVector3Array())


## The facing of the `index`-th marker of `tag` (facings), Vector3.ZERO for none or out of range.
func facing_at(tag: StringName, index: int) -> Vector3:
	var faced := facings(tag)
	if index < 0 or index >= faced.size():
		return Vector3.ZERO
	return faced[index]


func count(tag: StringName) -> int:
	return positions(tag).size()


## The tags, sorted.
func tags() -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(_markers.keys())
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return found


## Plain data for the command log: "facings" holds only the tags with a faced marker, and is left
## out when no marker has one (CommandLog.from_dict reads a missing one as none).
func to_dict() -> Dictionary:
	var markers := {}
	var faced := {}
	for tag: StringName in tags():
		markers[String(tag)] = positions(tag)
		for facing: Vector3 in facings(tag):
			if facing != Vector3.ZERO:
				faced[String(tag)] = facings(tag)
				break
	var data := {"path": path, "markers": markers}
	if not faced.is_empty():
		data["facings"] = faced
	return data
