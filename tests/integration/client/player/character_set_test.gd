extends GdUnitTestSuite
## CharacterSet (#522): a set only for a scene that is the character (one skeleton with the bones
## the rig names, one player with every clip AvatarClips plays), null for the LFS stand-in (an empty
## scene), a missing file or a broken character; the ragdoll data kept only when it is whole; and
## the shipped ragdoll file (text, so in CI too) in the art's format on the contract's bones.

const Fixture := preload("res://tests/integration/client/player/character_fixture.gd")
const CONTRACT := "res://tools/assets/asset_contract.json"
const Check := preload("res://tools/assets/asset_check.gd")


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
	# The fixture's own profile (slice_m1's names, #1693) names the bone it lacks.
	var slice := CharacterProfile.slice_m1()
	var without := Fixture.scene(AvatarClips.all_clips(), bones)
	var bare := without.instantiate()
	assert_array(Array(CharacterSet.problems_of(bare, slice))).contains_exactly(["no bone Wrist.R"])
	bare.free()
	assert_object(CharacterSet.from_scene(without, {}, slice)).is_null()
	assert_object(CharacterSet.from_scene(without, {})).is_null()


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
	var data := CharacterSet.read_ragdoll(CharacterSet.default_profile().ragdoll)
	assert_bool(CharacterSet.valid_ragdoll(data)).is_true()
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	var bones: Array = Check.character_role(CharacterSet.default_profile().glb, contract)["bones"]
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


## #1693: the carry clip and the one-shots are optional (the alien has none): the base clips make a
## character; a base clip missing does not.
func test_the_carry_and_the_one_shots_are_optional_clips() -> void:
	var character := CharacterSet.from_scene(
		Fixture.scene(AvatarClips.base_clips()), Fixture.ragdoll()
	)
	assert_object(character).is_not_null()


## #1693: a scene's profile is the one whose bones it has: the fixture carries slice_m1's names; the
## shipped default is the alien's.
func test_the_profile_is_the_one_whose_bones_the_scene_has() -> void:
	var character := CharacterSet.from_scene(Fixture.scene(), Fixture.ragdoll())
	assert_object(character.profile).is_not_null()
	assert_str(String(character.profile.carry_root)).is_equal("Torso")
	assert_str(CharacterSet.default_profile().glb).contains("alien_chameleon")
	var own := CharacterProfile.slice_m1()
	var named := CharacterSet.from_scene(Fixture.scene(), Fixture.ragdoll(), own)
	assert_object(named.profile).is_same(own)


## #1693: the ragdoll's lengths follow the profile's scale (the alien drawn at 0.94); the masses and
## the rest stay, and the data at 1 is the data itself.
func test_the_ragdoll_data_scales_with_the_profile() -> void:
	var data := Fixture.ragdoll()
	assert_object(CharacterSet.scaled_ragdoll(data, 1.0)).is_same(data)
	var half := CharacterSet.scaled_ragdoll(data, 0.5)
	var bodies := data["bones"] as Array
	var scaled := half["bones"] as Array
	for i: int in bodies.size():
		var was := bodies[i] as Dictionary
		var now := scaled[i] as Dictionary
		var offset := was["offset"] as Array
		for k: int in offset.size():
			assert_float((now["offset"] as Array)[k] as float).is_equal_approx(
				(offset[k] as float) * 0.5, 1e-6
			)
		for key: String in ["radius", "height"]:
			if was.has(key):
				assert_float(now[key] as float).is_equal_approx((was[key] as float) * 0.5, 1e-6)
		assert_that(now["mass_share"]).is_equal(was["mass_share"])
	# The data passed in is left as it was.
	assert_that((bodies[0] as Dictionary)["offset"]).is_equal(
		(Fixture.ragdoll()["bones"] as Array)[0]["offset"]
	)


## #1693: every profile's JSON files (the ragdoll data, the look) are no resources, so each must
## match an include_filter of every export preset, or the shipped game reads nothing there.
func test_every_profile_s_json_files_ship_in_every_export() -> void:
	var presets := ConfigFile.new()
	assert_int(presets.load("res://export_presets.cfg")).is_equal(OK)
	var sections := PackedStringArray()
	for section: String in presets.get_sections():
		if presets.has_section_key(section, "include_filter"):
			sections.append(section)
	assert_array(Array(sections)).is_not_empty()
	for profile: CharacterProfile in CharacterSet.profiles():
		for path: String in [profile.ragdoll, profile.look]:
			if path.is_empty():
				continue
			for section: String in sections:
				var shipped := false
				for pattern: String in str(presets.get_value(section, "include_filter")).split(","):
					shipped = shipped or path.get_file().matchn(pattern.strip_edges())
				(
					assert_bool(shipped)
					. override_failure_message("%s in %s" % [path, section])
					. is_true()
				)
