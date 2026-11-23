extends GdUnitTestSuite
## The base alien's package (#1690; the art's alien_chameleon of art#398, M8's base alien): its GLB
## imports with the 18 clips the HANDOFF lists, looping as named, on a humanoid skeleton with the
## bones the game's character sockets need; its look dresses the model (the head's and the body's
## materials, in a player's colour) with no error; its ragdoll data names its bodies. A checkout
## without the Git LFS content (CI) imports a stand-in: each test says skip and checks only that the
## GLB is a pointer. The nightly `lfs` job runs it.

const Check := preload("res://tools/assets/asset_check.gd")
const GLB := "res://assets/characters/alien_chameleon/alien_chameleon.glb"
const LOOK := "res://assets/characters/alien_chameleon/look/alien_chameleon_look.json"
const DRESS := "res://assets/characters/alien_chameleon/look/alien_dress.gd"
const RAGDOLL := "res://assets/characters/alien_chameleon/alien_chameleon.ragdoll.json"
## The package's clips (HANDOFF, package.json), as Godot imports them; the hits and the jump's
## start and landing play once.
const CLIPS: Array[String] = [
	"Crouch_Fwd",
	"Crouch_Idle",
	"Crouch_Run",
	"Idle",
	"Jog_Bwd",
	"Jog_Bwd_Left",
	"Jog_Bwd_Right",
	"Jog_Fwd",
	"Jog_Fwd_Left",
	"Jog_Fwd_Right",
	"Jump_Air",
	"Jump_Land",
	"Jump_Start",
	"Sprint_Fwd",
	"Strafe_Left",
	"Strafe_Right",
	"Talk_Upper",
	"Walk",
]
const ONCE: Array[String] = ["Jump_Land", "Jump_Start"]
## The bones the swap's sockets and carry root use (the art's note: Hips, Chest, UpperChest,
## RightHand), and the ragdoll's root.
const BONES: Array[String] = ["Hips", "Chest", "UpperChest", "RightHand"]


func test_the_clips_import_as_named_and_looping_as_the_package_says() -> void:
	var model := _model()
	if model == null:
		return
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var names: Array[String] = []
	for clip: StringName in player.get_animation_list():
		names.append(String(clip))
	assert_array(names).contains_exactly_in_any_order(CLIPS)
	for clip: String in CLIPS:
		var looping := player.get_animation(clip).loop_mode != Animation.LOOP_NONE
		assert_bool(looping).override_failure_message(clip).is_equal(not ONCE.has(clip))


func test_the_skeleton_has_the_bones_the_sockets_need() -> void:
	var model := _model()
	if model == null:
		return
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for bone: String in BONES:
		assert_int(skeleton.find_bone(bone)).override_failure_message(bone).is_not_equal(-1)


func test_the_look_dresses_the_model_in_a_player_s_colour() -> void:
	var model := _model()
	if model == null:
		return
	var dress := load(DRESS) as GDScript
	var materials: Array = dress.call(&"dress_from", model, LOOK)
	assert_int(materials.size()).is_equal(2)
	for material: Variant in materials:
		assert_object(material as ShaderMaterial).is_not_null()


func test_the_ragdoll_data_names_its_bodies() -> void:
	if _model() == null:
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RAGDOLL))
	assert_bool(data is Dictionary).is_true()
	var bones: Variant = (data as Dictionary).get("bones")
	assert_bool(bones is Array or bones is Dictionary).is_true()
	(
		assert_int((bones as Array).size() if bones is Array else (bones as Dictionary).size())
		. is_equal(16)
	)


## The package's model in the tree, or null (after the skip check) without the art.
func _model() -> Node3D:
	var scene := load(GLB) as PackedScene
	var model := scene.instantiate() as Node3D if scene != null else null
	if model == null or model.find_children("*", "AnimationPlayer", true, false).is_empty():
		if model != null:
			model.free()
		print("skip: %s has no Git LFS content here: the alien's package is unchecked" % GLB)
		assert_bool(Check.is_lfs_pointer(GLB)).is_true()
		return null
	auto_free(model)
	add_child(model)
	return model
