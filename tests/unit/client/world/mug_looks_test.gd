extends GdUnitTestSuite
## The mug's look (client/world/MugLooks, #1678, #1697): both kinds of the base mode; the art's
## mug (art#392's contract) with its Beer by the kind, held by its Grip; else the placeholder, a
## cylinder with a handle on its +X side standing on its origin; ItemView draws it with no label or
## box.

## The contract's grip point (art#392: the handle's middle).
const GRIP_AT := Vector3(0.065, 0.08, 0.0)


func test_both_kinds_of_the_base_mode_are_mugs() -> void:
	var mode := load("res://content/modes/base_mode.tres") as GameMode
	for kind: StringName in MugLooks.KINDS:
		assert_bool(MugLooks.has(kind)).is_true()
		(
			assert_object(mode.find_item_kind(kind))
			. override_failure_message(String(kind))
			. is_not_null()
		)
	assert_bool(MugLooks.has(&"knife")).is_false()


func test_the_placeholder_stands_on_its_origin_with_the_handle_on_its_side() -> void:
	var mug: Node3D = auto_free(MugLooks.placeholder())
	var body := mug.get_node(^"Body") as MeshInstance3D
	var handle := mug.get_node(^"Handle") as MeshInstance3D
	var body_box := body.transform * body.get_aabb()
	assert_float(body_box.position.y).is_equal_approx(0.0, 1e-4)
	assert_vector(body_box.size).is_equal_approx(MugLooks.SIZE, Vector3.ONE * 1e-4)
	var handle_box := handle.transform * handle.get_aabb()
	# It stands up on the +X side, past the body and within its height, flat in Z.
	assert_float(handle_box.end.x).is_greater(body_box.end.x)
	assert_float(handle_box.position.y).is_greater(0.0)
	assert_float(handle_box.end.y).is_less(MugLooks.SIZE.y)
	assert_float(handle_box.size.z).is_less(handle_box.size.y)


func test_an_item_view_of_a_mug_is_the_mug_s_look_with_no_label() -> void:
	for kind: StringName in MugLooks.KINDS:
		var view: ItemView = auto_free(ItemView.make(3, kind, Color.WHITE))
		assert_object(view.look().find_child("Mug", false, false)).is_not_null()
		assert_object(view.look().find_child("Box", true, false)).is_null()
		assert_int(view.find_children("*", "Label3D", true, false).size()).is_zero()
		# The art glass's 0.09 x 0.15 m (art#392's HANDOFF) where the LFS art is here.
		assert_vector(MugLooks.ART_SIZE).is_equal(Vector3(0.09, 0.15, 0.09))
		var size := MugLooks.ART_SIZE if MugLooks.has_art() else MugLooks.SIZE
		assert_vector(ItemView.size_of(kind)).is_equal(size)


## #1697: the art's mug (a scene shaped as art#392's contract) is its look: the Beer shown for a
## full mug and hidden for an empty one; its Grip is the point the hand holds.
func test_the_art_s_mug_shows_its_beer_by_the_kind_and_is_held_by_its_grip() -> void:
	var scene := _art_mug()
	var full: Node3D = auto_free(MugLooks.build(&"mug", scene))
	var empty: Node3D = auto_free(MugLooks.build(&"mug_empty", scene))
	assert_object(full.find_child("Body", true, false)).is_null()
	assert_bool((full.find_child("Beer", true, false) as Node3D).visible).is_true()
	assert_bool((empty.find_child("Beer", true, false) as Node3D).visible).is_false()
	# An exported light or camera is dropped: a mug lights and sees nothing.
	assert_int(full.find_children("*", "Light3D", true, false).size()).is_zero()
	assert_int(full.find_children("*", "Camera3D", true, false).size()).is_zero()
	var grip := MugLooks.grip_of(full)
	assert_vector(grip.origin).is_equal_approx(GRIP_AT, Vector3.ONE * 1e-6)
	assert_vector(grip.basis.y).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-6)
	# Without its Mug node (CI's Git LFS stand-in) the placeholder stands in.
	var stand_in := PackedScene.new()
	var bare := Node3D.new()
	stand_in.pack(bare)
	bare.free()
	var placeholder: Node3D = auto_free(MugLooks.build(&"mug", stand_in))
	assert_object(placeholder.find_child("Body", true, false)).is_not_null()


## The placeholder is held round its middle (#1678): its grip half its height up.
func test_the_placeholder_is_held_round_its_middle() -> void:
	var mug: Node3D = auto_free(MugLooks.placeholder())
	var grip := MugLooks.grip_of(mug)
	assert_vector(grip.origin).is_equal(-MugLooks.IN_HAND)
	assert_that(grip.basis).is_equal(Basis.IDENTITY)


## A scene as art#392's contract: Mug and Beer meshes, a light and a camera a Blender export may
## carry, the Grip in the handle (its +Y up the handle,
## its -Z to the mug's axis, -X).
func _art_mug() -> PackedScene:
	var root := Node3D.new()
	root.name = "ArtMug"
	for part: String in ["Mug", "Beer"]:
		var mesh := MeshInstance3D.new()
		mesh.name = part
		mesh.mesh = BoxMesh.new()
		root.add_child(mesh)
		mesh.owner = root
	# A light in a light and a camera in it: each goes with its parent, freed once.
	var parent: Node3D = root
	for extra: Node3D in [OmniLight3D.new(), OmniLight3D.new(), Camera3D.new()]:
		parent.add_child(extra)
		extra.owner = root
		parent = extra
	var grip := Marker3D.new()
	grip.name = "Grip"
	grip.transform = Transform3D(
		Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), GRIP_AT
	)
	root.add_child(grip)
	grip.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene
