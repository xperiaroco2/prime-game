extends GdUnitTestSuite
## CharacterSet (#522): a set only for a scene that is the character (one skeleton with the bones
## the rig names, one player with every clip AvatarClips plays), null for the LFS stand-in (an empty
## scene), a missing file or a broken character; the ragdoll data kept only when it is whole; and
## the shipped ragdoll file (text, so in CI too) in the art's format on the contract's bones.

const Fixture := preload("res://tests/integration/client/player/character_fixture.gd")
const CONTRACT := "res://tools/assets/asset_contract.json"


func test_the_fixture_character_is_a_set() -> void:
	var data := Fixture.ragdoll()
	var character := CharacterSet.from_scene(Fixture.scene(), data)
	assert_object(character).is_not_null()
	assert_object(character.scene).is_not_null()
	assert_int((character.ragdoll["bones"] as Array).size()).is_equal(4)


func test_a_missing_clip_or_bone_is_no_set() -> void:
	var clips := AvatarClips.all_clips()
	clips.erase(AvatarClips.CROUCH_FWD)
	var root := Fixture.scene(clips).instantiate()
	assert_array(Array(CharacterSet.problems_of(root))).contains_exactly(["no clip Crouch_Fwd"])
	root.free()
	assert_object(CharacterSet.from_scene(Fixture.scene(clips), {})).is_null()
	var bones := Fixture.BONES.duplicate()
	bones.erase(&"Wrist.R")
	(
		assert_object(CharacterSet.from_scene(Fixture.scene(AvatarClips.all_clips(), bones), {}))
		. is_null()
	)


## The LFS stand-in `check` imports in CI is a scene with no skeleton: no set, the placeholder.
func test_an_empty_scene_or_none_is_no_set() -> void:
	var root := Node3D.new()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	assert_object(CharacterSet.from_scene(packed, Fixture.ragdoll())).is_null()
	assert_object(CharacterSet.from_scene(null, {})).is_null()
	assert_object(CharacterSet.from_scene(PackedScene.new(), {})).is_null()


func test_broken_ragdoll_data_is_dropped() -> void:
	for data: Dictionary in [{}, {"format": "other"}, {"format": "prime-ragdoll", "bones": []}]:
		var character := CharacterSet.from_scene(Fixture.scene(), data)
		assert_bool(character.ragdoll.is_empty()).is_true()
	(
		assert_bool(
			CharacterSet.read_ragdoll("res://tests/scratch/no_such_ragdoll.json").is_empty()
		)
		. is_true()
	)


## A body on a bone the skeleton lacks would leave the ragdoll without its pelvis (the builder skips
## it), standing forever: the data is dropped and the capsule stands in.
func test_ragdoll_data_on_a_missing_bone_is_dropped() -> void:
	var data := Fixture.ragdoll()
	((data["bones"] as Array)[0] as Dictionary)["bone"] = "No.Such.Bone"
	var character := CharacterSet.from_scene(Fixture.scene(), data)
	assert_object(character).is_not_null()
	assert_bool(character.ragdoll.is_empty()).is_true()


## The shipped data: 16 bodies, 15 joints, the downed layer against the world only, each body on a
## bone of the import contract, and every key RagdollBuilder reads.
func test_the_shipped_ragdoll_file() -> void:
	var data := CharacterSet.read_ragdoll(CharacterSet.DEFAULT_RAGDOLL)
	assert_bool(CharacterSet.valid_ragdoll(data)).is_true()
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	var bones: Array = (contract["character"] as Dictionary)["bones"]
	var collision := data["collision"] as Dictionary
	assert_int(collision["layer"] as int).is_equal(3)
	assert_array(collision["mask"] as Array).contains_exactly([1.0])
	var joints := 0
	for body: Dictionary in data["bones"]:
		assert_bool(bones.has(body["bone"])).override_failure_message(str(body["bone"])).is_true()
		for key: String in ["shape", "offset", "mass_share", "parent", "joint"]:
			assert_bool(body.has(key)).override_failure_message(key).is_true()
		if body["joint"] != null:
			joints += 1
	assert_int((data["bones"] as Array).size()).is_equal(16)
	assert_int(joints).is_equal(15)


func test_the_eight_way_points_are_optional_clips() -> void:
	# The art MVP set (no diagonals) and the alien set (with them) are both characters (#1334).
	var bare := CharacterSet.from_scene(Fixture.scene(AvatarClips.all_clips()), Fixture.ragdoll())
	assert_object(bare).is_not_null()
	var full := CharacterSet.from_scene(Fixture.scene(Fixture.eight_way_clips()), Fixture.ragdoll())
	assert_object(full).is_not_null()
