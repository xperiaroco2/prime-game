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
## where players collide: D2 (a), waiting for the designer on #96); any other physics body on
## layer 1 (a RigidBody3D, a CharacterBody3D), which players collide with but the host's static
## world would not hold. An AnimatableBody3D is a StaticBody3D: it is built where the scene puts
## it, and never moves on the host. A level with errors is refused by the host like one with
## marker errors.
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
# The level's shapes: a body holds only their RIDs, which live as long as these resources.
var _shapes: Array[Shape3D] = []


## The world of the level scene at `level_path`: loaded, read and freed.
static func build(level_path: String) -> LevelWorld:
	var scene: PackedScene = null
	if ResourceLoader.exists(level_path, "PackedScene"):
		scene = load(level_path) as PackedScene
	if scene == null:
		var failed := LevelWorld.new()
		failed.path = level_path
		failed._fail("%s: not a scene" % level_path)
		return failed
	var root := scene.instantiate()
	var built := from_scene(root, level_path)
	root.free()
	return built


## The world of the scene under `root`, as the level at `level_path`. Read-only: it never changes
## the scene, which may be freed afterwards.
static func from_scene(root: Node, level_path: String) -> LevelWorld:
	var built := LevelWorld.new()
	built.path = level_path
	built._read(root, root)
	return built


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for body: RID in _bodies:
			PhysicsServer3D.free_rid(body)
		_bodies.clear()


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
	var body := RID()
	for child: Node in node.get_children():
		if child is CollisionPolygon3D:
			_fail(_unread(child, root, "a CollisionPolygon3D"))
			continue
		if not child is CollisionShape3D:
			continue
		var collision := child as CollisionShape3D
		if collision.disabled or collision.shape == null:
			continue
		if not body.is_valid():
			body = PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
			PhysicsServer3D.body_set_collision_layer(body, WORLD_LAYER)
			PhysicsServer3D.body_set_collision_mask(body, 0)
			PhysicsServer3D.body_set_state(
				body, PhysicsServer3D.BODY_STATE_TRANSFORM, transform_in_scene(node, root)
			)
			_bodies.append(body)
		_shapes.append(collision.shape)
		PhysicsServer3D.body_add_shape(body, collision.shape.get_rid(), collision.transform)
	if body.is_valid():
		PhysicsServer3D.body_set_space(body, world.space)


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
