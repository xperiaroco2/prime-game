class_name MarkerReader
extends RefCounted
## Reads a level scene's spawn points into a LevelLayout (ARCHITECTURE §9.1, §9.6), the one place
## server/ (and the tests, §9.7) turn a level into what core/ is handed. Read-only: it never changes
## the scene.
##
## A spawn point is a Marker3D in exactly one persistent group `spawn_<tag>`; the markers are read
## in scene-tree order (depth first, a parent before its children), the level order of §3.3, and
## each is placed where the scene puts it (its transform through its Node3D parents). Load errors,
## all reported, none fatal to the rest: a marker in two `spawn_` groups (it is left out), a node
## that is not a Marker3D in a `spawn_` group, a group named `spawn_` alone, and a floor-standing
## marker with no floor below it.
##
## Floor-standing markers (the engineer's answer on #82, item 3, on #66): a station's cylinder
## starts at its marker's height, so a circle marker even a little above the floor would leave
## its packages below the cylinder (§7.1). The markers of `floor_tags` (the spawn tags of the
## mode's station kinds: `circle`) are snapped down to the floor that `world` finds below them,
## asked from FLOOR_PROBE_M above so a marker a little under the floor still finds it; one with no
## floor below is reported. `world` is the host's WorldQuery over the level (M3); the flat levels
## of stage 2 have one floor at y = 0, which FlatWorldQuery answers.

## The group prefix of spawn points: `spawn_package`.
const GROUP_PREFIX := "spawn_"
## A marker is snapped to the floor found below this point above it.
const FLOOR_PROBE_M := 0.1


## One level read: its layout and every load error.
class Read:
	extends RefCounted
	var layout: LevelLayout
	var errors := PackedStringArray()


## Every level of a mode read: layouts by path and every load error.
class Levels:
	extends RefCounted
	var layouts: Dictionary[String, LevelLayout] = {}
	var errors := PackedStringArray()


## The spawn points of the scene under `root`, as the level at `level_path`.
static func read(
	root: Node, level_path: String, world: WorldQuery, floor_tags: Array[StringName] = []
) -> Read:
	var result := Read.new()
	result.layout = LevelLayout.new(level_path)
	_read_node(root, root, result, world, floor_tags)
	return result


## Loads the scene at `level_path`, reads it and frees it.
static func read_scene(
	level_path: String, world: WorldQuery, floor_tags: Array[StringName] = []
) -> Read:
	var scene: PackedScene = null
	if ResourceLoader.exists(level_path, "PackedScene"):
		scene = load(level_path) as PackedScene
	if scene == null:
		var failed := Read.new()
		failed.layout = LevelLayout.new(level_path)
		failed.errors.append("%s: not a scene" % level_path)
		return failed
	var root := scene.instantiate()
	var result := read(root, level_path, world, floor_tags)
	root.free()
	return result


## The lobby and every map of `mode`, read with `world` for the floor.
static func read_levels(mode: GameMode, world: WorldQuery) -> Levels:
	var levels := Levels.new()
	var paths: Array[String] = []
	if not mode.lobby_level.is_empty():
		paths.append(mode.lobby_level)
	for map: String in mode.maps:
		if not paths.has(map):
			paths.append(map)
	var tags := floor_tags_of(mode)
	for path: String in paths:
		var result := read_scene(path, world, tags)
		levels.layouts[path] = result.layout
		levels.errors.append_array(result.errors)
	return levels


## The spawn tags whose markers stand on the floor: those of the station kinds that the mode's
## task types place (the delivery circle's `circle`), sorted.
static func floor_tags_of(mode: GameMode) -> Array[StringName]:
	var tags: Array[StringName] = []
	for type: TaskType in mode.task_types:
		if type == null:
			continue
		for property: Dictionary in type.get_property_list():
			var usage: int = property["usage"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var value: Variant = type.get(property["name"] as String)
			if value is StationKind:
				var tag := (value as StationKind).spawn_tag
				if not tag.is_empty() and not tags.has(tag):
					tags.append(tag)
	tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return tags


static func _read_node(
	node: Node, root: Node, into: Read, world: WorldQuery, floor_tags: Array[StringName]
) -> void:
	_read_marker(node, root, into, world, floor_tags)
	for child: Node in node.get_children():
		_read_node(child, root, into, world, floor_tags)


static func _read_marker(
	node: Node, root: Node, into: Read, world: WorldQuery, floor_tags: Array[StringName]
) -> void:
	var tags: Array[StringName] = []
	for group: StringName in node.get_groups():
		var name := String(group)
		if name.begins_with(GROUP_PREFIX):
			tags.append(StringName(name.substr(GROUP_PREFIX.length())))
	if tags.is_empty():
		return
	var where := "%s: %s" % [into.layout.path, root.get_path_to(node)]
	if not node is Marker3D:
		into.errors.append(
			"%s is in a spawn group but is a %s, not a Marker3D" % [where, node.get_class()]
		)
		return
	if tags.size() > 1:
		into.errors.append(
			(
				"%s is in %d spawn groups (%s); a marker carries one tag"
				% [where, tags.size(), ", ".join(PackedStringArray(tags))]
			)
		)
		return
	var tag := tags[0]
	if tag.is_empty():
		into.errors.append("%s is in the group %s, which names no tag" % [where, GROUP_PREFIX])
		return
	var position := _position_of(node as Node3D, root)
	if floor_tags.has(tag):
		var found := world.floor_below(position + Vector3.UP * FLOOR_PROBE_M)
		if found == WorldQuery.NO_FLOOR:
			into.errors.append(
				"%s (%s at %s) is not on a floor: nothing below it" % [where, tag, position]
			)
			return
		position.y = found.y
	into.layout.add_marker(tag, position)


## Where the scene puts `node`: its transform through its Node3D parents up to `root`, the scene's
## root (whose own transform counts), and never past a top_level node, whose transform is global.
## Read outside the scene tree, where Node3D.global_position is not available.
static func _position_of(node: Node3D, root: Node) -> Vector3:
	var at := node.transform
	var current := node
	while not current.top_level and current != root and current.get_parent() is Node3D:
		current = current.get_parent() as Node3D
		at = current.transform * at
	return at.origin
