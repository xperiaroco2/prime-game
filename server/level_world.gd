class_name LevelWorld
extends RefCounted
## One level's collision world on the host (ARCHITECTURE §4.5, E8): a World3D.new() whose space
## holds one static body per StaticBody3D of layer 1 (`world`) in the level's scene, built through
## PhysicsServer3D with each CollisionShape3D's shape and its transform composed up to the scene's
## root. The scene is instantiated only to be read, never added to a tree, then freed: the host
## keeps no second live copy of the level's meshes and scripts, and its answers never depend on
## the host's client scene. HostWorldQuery asks it through `space_state()`.
##
## Read errors, all listed in `errors` and logged, none fatal to the rest: a scene that does not
## load; a root CSG node with use_collision, or a GridMap whose used items have shapes, on layer
## 1, and a CollisionPolygon3D of a
## layer-1 body (they build their collision only inside a tree, so the host would see nothing
## where players collide: D2 (a), the designer's answer on #96); any other physics body on
## layer 1 (a RigidBody3D, a CharacterBody3D), which players collide with but the host's static
## world would not hold. An AnimatableBody3D is a StaticBody3D: it is built where the scene puts
## it. A scene that gives the world no body at all is an error too:
## the host would see through everything and find no floor. A level with errors is refused by
## the host like one with marker errors.
##
## World toggles (#1295, §4.5.9): a StaticBody3D in group `toggle_<key>` with the int metadata
## `toggle_index` (StationKind's TOGGLE_ constants) is a part of toggle (key, index). A part with
## a child Marker3D `OnPose` is a mover: it gets a second body at the OnPose pose, kept out of the
## space while the toggle is off; `set_toggle` swaps which of the two is in the space. A part
## without one is a collider, taken out of the space while the toggle is on. Only body_set_space
## changes, never a body's pose or layer: an unstepped space sees an added body at once (the
## probe below), which is all a swap needs. A part without its index, or in two toggle groups,
## is an error.
##
## A fresh space answers rays at once, before any physics step (the probe in
## tests/integration/server/level_world_test.gd, §4.5), so a world is ready when it is built.

## The collision layer of the level's static colliders (project.godot: layer 1 is `world`).
const WORLD_LAYER := 1

## The level's path (`res://levels/...`), the key Match names it by (WorldQuery.use_level).
var path: String
## The world whose space holds the level's colliders.
var world := World3D.new()
## Every read error, in scene-tree order.
var errors := PackedStringArray()

var _bodies: Array[RID] = []
# The movers' bodies at their OnPose, out of the space while their toggle is off: not counted.
var _on_bodies: Array[RID] = []
# The level's shapes: a body holds only their RIDs, which live as long as these resources.
var _shapes: Array[Shape3D] = []
# The toggle parts, in scene-tree order.
var _parts: Array[TogglePart] = []


## A part of toggle (key, index): `off_body` stands while the toggle is off; `on_body` (a mover's
## OnPose body, else invalid) while it is on.
class TogglePart:
	extends RefCounted
	var key: StringName
	var index: int
	var off_body: RID
	var on_body: RID


## The world of the level scene at `level_path`: loaded (from `scenes` when given, which keeps it
## for the next reader of the start: LevelScenes), read and freed.
static func build(level_path: String, scenes: LevelScenes = null) -> LevelWorld:
	var scene := LevelScenes.scene_of(level_path, scenes)
	if scene == null:
		return _failed(level_path, "not a scene")
	return from_packed(scene, level_path)


## The world of `scene`, as the level at `level_path`: instantiated, read and freed. A scene that
## cannot be instantiated is an error, not a crash.
static func from_packed(scene: PackedScene, level_path: String) -> LevelWorld:
	if not scene.can_instantiate():
		return _failed(level_path, "cannot be instantiated")
	var root := scene.instantiate()
	if root == null:
		return _failed(level_path, "cannot be instantiated")
	var built := from_scene(root, level_path)
	root.free()
	return built


## The world of the scene under `root`, as the level at `level_path`. Read-only: it never changes
## the scene, which may be freed afterwards.
static func from_scene(root: Node, level_path: String) -> LevelWorld:
	var built := LevelWorld.new()
	built.path = level_path
	built._read(root, root)
	if built._bodies.is_empty():
		built._fail(
			"%s: no static collision on layer 1 (the host sees no wall or floor)" % level_path
		)
	return built


static func _failed(level_path: String, why: String) -> LevelWorld:
	var failed := LevelWorld.new()
	failed.path = level_path
	failed._fail("%s: %s" % [level_path, why])
	return failed


## Where the scene puts `node`: its transform through its Node3D parents up to `root`, the scene's
## root (whose own transform counts), and never past a top_level node, whose transform is global.
## Read outside the scene tree, where Node3D.global_transform is not available.
static func transform_in_scene(node: Node3D, root: Node) -> Transform3D:
	var at := node.transform
	var current := node
	while not current.top_level and current != root and current.get_parent() is Node3D:
		current = current.get_parent() as Node3D
		at = current.transform * at
	return at


## The space's query state (World3D.direct_space_state). Physics runs on the main thread
## (project.godot sets no physics thread), where it may be asked outside _physics_process.
func space_state() -> PhysicsDirectSpaceState3D:
	return world.direct_space_state


## How many static bodies the level gave the world.
func body_count() -> int:
	return _bodies.size()


## How many toggle parts the level has (each counted once, a mover too).
func toggle_part_count() -> int:
	return _parts.size()


## The parts of toggle (key, index) as the toggle is (WorldQuery.set_toggle): a collider out of
## the space while `on`, a mover's OnPose body in it instead of its scene pose. No part: nothing.
func set_toggle(key: StringName, index: int, on: bool) -> void:
	for part: TogglePart in _parts:
		if part.key == key and part.index == index:
			_stand(part, on)


## Every toggle part off, as the scene stands (WorldQuery.reset_toggles).
func reset_toggles() -> void:
	for part: TogglePart in _parts:
		_stand(part, false)


func _stand(part: TogglePart, on: bool) -> void:
	PhysicsServer3D.body_set_space(part.off_body, RID() if on else world.space)
	if part.on_body.is_valid():
		PhysicsServer3D.body_set_space(part.on_body, world.space if on else RID())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for body: RID in _bodies + _on_bodies:
			PhysicsServer3D.free_rid(body)
		_bodies.clear()
		_on_bodies.clear()


func _read(node: Node, root: Node) -> void:
	if node is StaticBody3D:
		_add_body(node as StaticBody3D, root)
	elif node is CSGShape3D:
		# Only a root CSG shape (no CSG parent) builds collision; a child's use_collision is unused.
		var csg := node as CSGShape3D
		if (
			csg.use_collision
			and (csg.collision_layer & WORLD_LAYER) != 0
			and not node.get_parent() is CSGShape3D
		):
			_fail(_unread(node, root, "a CSG node with collision"))
	elif node is GridMap:
		var grid := node as GridMap
		if (grid.collision_layer & WORLD_LAYER) != 0 and _grid_has_shapes(grid):
			_fail(_unread(node, root, "a GridMap with collision"))
	elif node is PhysicsBody3D:
		var moving := node as PhysicsBody3D
		if (moving.collision_layer & WORLD_LAYER) != 0:
			_fail(_unread(node, root, "a %s on layer 1" % moving.get_class()))
	for child: Node in node.get_children():
		_read(child, root)


func _add_body(node: StaticBody3D, root: Node) -> void:
	if (node.collision_layer & WORLD_LAYER) == 0:
		return
	var shapes: Array[CollisionShape3D] = []
	for child: Node in node.get_children():
		if child is CollisionPolygon3D:
			_fail(_unread(child, root, "a CollisionPolygon3D"))
			continue
		if not child is CollisionShape3D:
			continue
		var collision := child as CollisionShape3D
		if collision.disabled or collision.shape == null:
			continue
		shapes.append(collision)
		_shapes.append(collision.shape)
	if shapes.is_empty():
		return
	var at := transform_in_scene(node, root)
	var body := _body_of(shapes, at)
	_bodies.append(body)
	PhysicsServer3D.body_set_space(body, world.space)
	var part := _toggle_part_of(node, root)
	if part == null:
		return
	part.off_body = body
	var on_pose := node.get_node_or_null(StationKind.ON_POSE) as Marker3D
	if on_pose != null:
		part.on_body = _body_of(shapes, at * on_pose.transform)
		_on_bodies.append(part.on_body)
	_parts.append(part)


# A static body on layer 1 at `at` with `shapes`, in no space yet.
func _body_of(shapes: Array[CollisionShape3D], at: Transform3D) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body, WORLD_LAYER)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, at)
	for collision: CollisionShape3D in shapes:
		PhysicsServer3D.body_add_shape(body, collision.shape.get_rid(), collision.transform)
	return body


# The toggle `node` is a part of (its toggle_<key> group and toggle_index metadata), or null for
# a body in no toggle group. A part without an int index, or in two toggle groups: an error, null.
func _toggle_part_of(node: StaticBody3D, root: Node) -> TogglePart:
	var keys: Array[StringName] = []
	for group: StringName in node.get_groups():
		if String(group).begins_with(StationKind.TOGGLE_GROUP_PREFIX):
			keys.append(StringName(String(group).trim_prefix(StationKind.TOGGLE_GROUP_PREFIX)))
	if keys.is_empty():
		return null
	var where := root.get_path_to(node)
	if keys.size() > 1:
		_fail("%s: %s is in two toggle groups" % [path, where])
		return null
	var index: Variant = node.get_meta(StationKind.TOGGLE_INDEX_META, null)
	if not index is int or (index as int) < 0:
		_fail(
			(
				"%s: %s in group %s%s has no int metadata %s"
				% [
					path,
					where,
					StationKind.TOGGLE_GROUP_PREFIX,
					keys[0],
					StationKind.TOGGLE_INDEX_META
				]
			)
		)
		return null
	var part := TogglePart.new()
	part.key = keys[0]
	part.index = index as int
	return part


# Whether a used cell of `grid` holds an item with collision shapes: a looks-only GridMap (items
# with meshes only) has no collision, whatever its collision_layer.
static func _grid_has_shapes(grid: GridMap) -> bool:
	var library := grid.mesh_library
	if library == null:
		return false
	var items := library.get_item_list()
	var seen: Dictionary[int, bool] = {}
	for cell: Vector3i in grid.get_used_cells():
		var item := grid.get_cell_item(cell)
		if seen.has(item):
			continue
		seen[item] = true
		if items.has(item) and not library.get_item_shapes(item).is_empty():
			return true
	return false


func _unread(node: Node, root: Node, what: String) -> String:
	return (
		"%s: %s is %s, which the host cannot read (give collision as StaticBody3D nodes on layer 1)"
		% [path, root.get_path_to(node), what]
	)


func _fail(message: String) -> void:
	errors.append(message)
	push_error("level world: %s" % message)
