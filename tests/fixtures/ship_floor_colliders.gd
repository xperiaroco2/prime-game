extends SceneTree
## The estate ship's floor colliders (#1499): the art ship package (prime-game-art#335) gives its
## grated and inlaid floors `-col` hints, so `colliders` writes each as the mesh's own trimesh
## (levels/kit/ship/, up to 9,400 triangles of lattice in 3.5 cm of floor). A capsule standing on
## one costs Jolt's motion queries about a hundred times what plain floor costs (0.4 to 1.5 ms per
## test_move, against 0.01), and the player's controller runs several each tick on both the client
## and the host: the playcheck at the ship fell to 6 frames a second. The estate's ship piece swaps
## each such shape for its convex hull here, `levels/estate/rooms/ship_hull/<kit file>` (the same
## outline and top, the lattice's holes filled), through an override of the kit body's
## CollisionShape3D under `Art` in levels/estate/rooms/ship.tscn. Written by running this script
## after a new ship package: `tools/run.sh run tests/fixtures/ship_floor_colliders.gd --headless`;
## tests/integration/levels/estate_ship_test.gd fails while a saved hull and its kit shape differ,
## or while a thin trimesh of the art's floors under the estate's ship is left in place.

## The kit's floor shapes the estate swaps, by file name under KIT.
const FLOOR_SHAPES: Array[String] = [
	"hall_floor_disc.grate_col.tres",
	"hall_floor_disc.trim_col.tres",
	"hall_floor_disc.hub_col.tres",
	"hall_floor_disc.bolts_col.tres",
	"hall_grate.grate_col.tres",
	"throat_floor.grate_col.tres",
	"tip_grate.grate_col.tres",
	"tip_floor_rim.plates_col.tres",
	"tip_floor_disc.disc_col.tres",
	"tip_floor_disc.trim_col.tres",
	"tip_floor_disc.inlay_col.tres",
	"cor_grate.grate_col.tres",
]
const KIT := "res://levels/kit/ship/"
const HULLS := "res://levels/estate/rooms/ship_hull/"
## The saved points are snapped to a tenth of a millimetre (a smaller text file, no float noise).
const SNAP_M := 0.0001


## The path of the convex hull that replaces the kit's shape `file`.
static func hull_path(file: String) -> String:
	return HULLS + file


## The convex hull of `shape`'s triangles, its points snapped to SNAP_M.
static func hull_of(shape: ConcavePolygonShape3D) -> PackedVector3Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = shape.get_faces()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var points := PackedVector3Array()
	for p: Vector3 in mesh.create_convex_shape(true, false).points:
		points.append(p.snapped(Vector3.ONE * SNAP_M))
	return points


func _initialize() -> void:
	for file: String in FLOOR_SHAPES:
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull_of(load(KIT + file) as ConcavePolygonShape3D)
		var error := ResourceSaver.save(shape, hull_path(file))
		print("%s: %d points, %s" % [hull_path(file), shape.points.size(), error_string(error)])
	quit()
