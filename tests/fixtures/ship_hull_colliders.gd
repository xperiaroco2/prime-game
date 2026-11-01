extends SceneTree
## The estate ship's hull colliders (#1499): the art ship package (prime-game-art#335) gives its
## outer skin, `skin_top` and `skin_belly`, no `-col` hints, so a player would walk through the hull
## under the wings and aft and a throw would fly through it. The game's own trimesh of each skin, in
## the ship scene's frame, is `levels/estate/rooms/ship_hull/<stem>_col.tres`, under the estate
## piece's `Hull` body. Written by running this script after a new ship package:
## `tools/run.sh run tests/fixtures/ship_hull_colliders.gd --headless`;
## `tests/integration/levels/estate_ship_test.gd` fails while a saved shape and the skin differ.

const SHIP := "res://levels/ship/ship.tscn"
const STEMS: Array[String] = ["skin_top", "skin_belly"]
## The saved vertices are snapped to a tenth of a millimetre (a smaller text file, no float noise).
const SNAP_M := 0.0001


## The path of skin `stem`'s saved shape.
static func shape_path(stem: String) -> String:
	return "res://levels/estate/rooms/ship_hull/%s_col.tres" % stem


## The triangles of every piece of the art ship named `<stem>_<n>`, in the ship scene's frame, read
## from `ship` (instanced, not necessarily in a tree).
static func faces_of(ship: Node3D, stem: String) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for piece: Node in ship.get_node(^"Pieces").get_children():
		if not str(piece.name).begins_with(stem + "_"):
			continue
		for found: Node in piece.find_children("*", "MeshInstance3D", true, false):
			var look := found as MeshInstance3D
			var to_ship := _in_ship(look, ship)
			for v: Vector3 in look.mesh.get_faces():
				faces.append((to_ship * v).snapped(Vector3.ONE * SNAP_M))
	return faces


## `node`'s transform in `ship`'s frame, read from the local transforms (no tree needed).
static func _in_ship(node: Node3D, ship: Node3D) -> Transform3D:
	var at := Transform3D.IDENTITY
	var walk: Node = node
	while walk != ship and walk != null:
		if walk is Node3D:
			at = (walk as Node3D).transform * at
		walk = walk.get_parent()
	return at


func _initialize() -> void:
	var ship: Node3D = (load(SHIP) as PackedScene).instantiate()
	for stem: String in STEMS:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces_of(ship, stem))
		var error := ResourceSaver.save(shape, shape_path(stem))
		print("%s: %d triangles, %s" % [shape_path(stem), shape.get_faces().size() / 3, error])
	ship.free()
	quit()
