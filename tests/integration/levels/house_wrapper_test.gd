extends GdUnitTestSuite
## The House's art wrappers hold each collider once (#523; levels/CLAUDE.md "Assets"): the GLB's
## .import skips the importer's own bodies (Skip Import), the wrapper's StaticBody3D nodes carry the
## colliders as text shapes. With the GLB's LFS content the GLB alone must show no body; a checkout
## without it imports an empty stand-in, which holds none either.

## A GLB with one root collider, one with colliders nested under leaves, and the wrapper of each.
const GLBS: Array[String] = [
	"res://assets/environment/house_kit/beam_concrete_1m.glb",
	"res://assets/environment/house_kit/dormer_gable.glb",
]


func test_a_glb_alone_has_no_body_of_the_importer() -> void:
	for path: String in GLBS:
		var root := (load(path) as PackedScene).instantiate()
		var bodies := root.find_children("*", "CollisionObject3D", true, false)
		root.free()
		assert_int(bodies.size()).is_equal(0)


func test_a_wrapper_holds_the_shapes_of_its_bodies() -> void:
	for path: String in GLBS:
		var wrapper := path.replace("assets/environment", "levels/kit").replace(".glb", ".tscn")
		var root := (load(wrapper) as PackedScene).instantiate()
		var bodies := root.find_children("*", "StaticBody3D", true, false)
		assert_int(bodies.size()).is_greater(0)
		for body: Node in bodies:
			var shapes := body.find_children("*", "CollisionShape3D", false, false)
			assert_int(shapes.size()).is_equal(1)
			assert_object((shapes[0] as CollisionShape3D).shape).is_not_null()
		root.free()
