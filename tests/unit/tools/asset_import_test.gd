extends GdUnitTestSuite
## The import check of the art handoff (#519, docs/ARCHITECTURE.md §11): every committed GLB under
## res:// loads and keeps the art repo's glTF options, every image under assets/ keeps its folder's
## compression (tools/assets/asset_check.gd over tools/assets/asset_contract.json). A checkout
## without LFS content (CI) has pointer files there; their .import files are checked, their scenes
## are named and skipped, the local run loads them. Each rule also runs on a broken fixture built in
## memory and must name the asset and what is missing.

const Check := preload("res://tools/assets/asset_check.gd")
const FIXTURE := "res://assets/characters/fixture/fixture.glb"
const KINDS: Array[String] = ["characters", "environment", "audio", "ui"]
## A tree of probe files the tests write and remove (pointer files stand in for GLBs).
const PROBE := "user://asset_check_probe/"

var _contract: Dictionary


func before() -> void:
	_contract = Check.load_contract()


func after_test() -> void:
	_remove_tree(PROBE)


func test_the_contract_names_a_folder_per_kind_bones_and_clips() -> void:
	assert_bool(_contract.is_empty()).override_failure_message("no asset contract").is_false()
	var folders: Dictionary = _contract.get("folders", {})
	for kind: String in KINDS:
		assert_str(str(folders.get(kind, ""))).is_equal("res://assets/%s/" % kind)
	var character: Dictionary = _contract.get("character", {})
	var bones: Array = character.get("bones", [])
	var unique := {}
	for bone: Variant in bones:
		unique[str(bone)] = true
	assert_int(bones.size()).is_equal(64)
	assert_int(unique.size()).is_equal(bones.size())
	var names := {}
	for clip: Variant in character.get("clips", []):
		var spec: Dictionary = clip
		assert_bool(spec.get("loop") is bool).is_true()
		assert_bool(str(spec.get("name", "")).is_empty()).is_false()
		names[spec["name"]] = true
	assert_int(names.size()).is_equal((character.get("clips", []) as Array).size())


func test_every_committed_glb_and_image_passes() -> void:
	var result: Dictionary = Check.check_all(_contract)
	var pointers: PackedStringArray = result["pointers"]
	if not pointers.is_empty():
		# CI checks out without LFS content (the LFS ADR): the local run checks these.
		print(
			(
				"asset import check: skipped %d LFS pointer files: %s"
				% [pointers.size(), ", ".join(pointers)]
			)
		)
	var problems: PackedStringArray = result["problems"]
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_every_glb_is_found_in_every_folder() -> void:
	# A probe tree, not a committed asset: the dry-run chair may be replaced or removed (#522, #523).
	for path: String in [PROBE + "b/b.glb", PROBE + "a/deep/a.gltf", PROBE + "a/notes.txt"]:
		_write_pointer(path)
	assert_array(Check.find_files(PROBE, ["glb", "gltf"])).contains_exactly(
		[PROBE + "a/deep/a.gltf", PROBE + "b/b.glb"]
	)
	for path: String in Check.find_files("res://", ["glb", "gltf"]):
		assert_bool(path.begins_with("res://addons/")).is_false()
		assert_bool(path.begins_with("res://tests/scratch/")).is_false()


func test_a_character_is_a_glb_under_the_characters_folder() -> void:
	assert_bool(Check.is_character(FIXTURE, _contract)).is_true()
	assert_bool(Check.is_character("res://assets/environment/x/x.glb", _contract)).is_false()
	assert_bool(Check.is_character(FIXTURE, {})).is_false()


func test_a_whole_character_passes() -> void:
	assert_array(Check.check_character(FIXTURE, _character(), _contract)).is_empty()


func test_a_missing_clip_names_the_asset_and_the_clip() -> void:
	var problems := Check.check_character(FIXTURE, _character("", "Crawl"), _contract)
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).starts_with(FIXTURE + ": lacks 1 contract clips: Crawl (it has: ")


func test_a_missing_bone_names_the_asset_and_the_bone() -> void:
	var problems := Check.check_character(FIXTURE, _character("Toe.R"), _contract)
	assert_array(problems).contains_exactly(
		[FIXTURE + ": the skeleton lacks 1 contract bones: Toe.R"]
	)


func test_a_loop_that_plays_once_is_named() -> void:
	var problems := Check.check_character(FIXTURE, _character("", "", "Idle"), _contract)
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).starts_with(FIXTURE + ": the clip Idle plays once, the contract says")


func test_a_character_without_a_skeleton_or_player_is_named() -> void:
	var empty: Node3D = auto_free(Node3D.new())
	(
		assert_array(Check.check_character(FIXTURE, empty, _contract))
		. contains_exactly(
			[
				FIXTURE + ": has 0 Skeleton3D nodes, want 1",
				FIXTURE + ": has 0 AnimationPlayer nodes, want 1",
			]
		)
	)


func test_a_character_import_keeps_the_art_options() -> void:
	var good := _character_params()
	assert_array(Check.check_glb_params(FIXTURE, good, _contract, true)).is_empty()
	var bad := _character_params()
	bad["animation/fps"] = 24
	bad["_subresources"] = {}
	bad.erase("nodes/root_scale")
	var problems := Check.check_glb_params(FIXTURE, bad, _contract, true)
	(
		assert_array(problems)
		. contains_exactly_in_any_order(
			[
				FIXTURE + ": .import has no nodes/root_scale (want 1)",
				FIXTURE + ": .import animation/fps=24, want 30",
				(
					FIXTURE
					+ ": .import _subresources nodes PATH:AnimationPlayer has no optimizer/enabled"
					+ " (want false)"
				),
			]
		)
	)


func test_a_prop_import_needs_no_character_options() -> void:
	var params := _character_params()
	params["animation/fps"] = 24
	params["_subresources"] = {}
	var prop := "res://assets/environment/fixture/fixture.glb"
	assert_array(Check.check_glb_params(prop, params, _contract, false)).is_empty()
	params["nodes/root_scale"] = 0.01
	assert_array(Check.check_glb_params(prop, params, _contract, false)).contains_exactly(
		[prop + ": .import nodes/root_scale=0.01, want 1"]
	)


func test_a_glb_without_an_import_or_scene_is_named() -> void:
	var path := "res://assets/environment/missing/missing.glb"
	(
		assert_array(Check.check_glb(path, _contract))
		. contains_exactly(
			[
				path + ": no committed .import file (run the import and commit it)",
				path + ": does not load (the import failed or was never run)",
			]
		)
	)


func test_an_image_keeps_its_folders_compression() -> void:
	var image := "res://assets/environment/fixture/wood.png"
	assert_array(Check.check_texture(image, {"compress/mode": 2}, _contract)).is_empty()
	assert_array(Check.check_texture(image, {"compress/mode": 0}, _contract)).contains_exactly(
		[image + ": .import compress/mode=0, want 2 for res://assets/environment/"]
	)
	var icon := "res://assets/ui/fixture/icon.png"
	assert_array(Check.check_texture(icon, {"compress/mode": 0}, _contract)).is_empty()
	assert_array(Check.check_texture(icon, null, _contract)).contains_exactly(
		[icon + ": no committed .import file"]
	)
	assert_array(Check.check_texture("res://client/x.png", null, _contract)).is_empty()


func test_every_texture_format_has_its_compression_checked() -> void:
	for ext: String in ["png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr"]:
		var path := PROBE + "wood." + ext
		_write_pointer(path)
		assert_array(Check.find_files(PROBE, Check.IMAGE_EXTENSIONS)).contains([path])


func test_an_lfs_pointer_is_told_from_an_asset() -> void:
	var pointer := (
		"version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize 10756\n" % "0".repeat(64)
	)
	var bytes := pointer.to_utf8_buffer()
	assert_bool(Check.is_lfs_pointer_bytes(bytes, bytes.size())).is_true()
	assert_bool(Check.is_lfs_pointer_bytes(bytes, 4096)).is_false()
	var glb := PackedByteArray([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0])
	assert_bool(Check.is_lfs_pointer_bytes(glb, 10756)).is_false()


func test_a_pointer_glb_still_has_its_import_checked() -> void:
	# CI has no LFS content, but the .import beside a pointer file is text and is there.
	var prop := PROBE + "prop/prop.glb"
	_write_pointer(prop)
	var config := ConfigFile.new()
	config.set_value("params", "nodes/root_type", "")
	config.set_value("params", "nodes/root_scale", 0.01)
	config.set_value("params", "nodes/apply_root_scale", true)
	config.set_value("params", "animation/import", true)
	assert_int(config.save(prop + ".import")).is_equal(OK)
	var bare := PROBE + "bare/bare.glb"
	_write_pointer(bare)
	var result: Dictionary = Check.check_all(_contract, PROBE)
	var pointers: PackedStringArray = result["pointers"]
	assert_array(pointers).contains_exactly([bare, prop])
	var problems: PackedStringArray = result["problems"]
	(
		assert_array(problems)
		. contains(
			[
				prop + ": .import nodes/root_scale=0.01, want 1",
				bare + ": no committed .import file (run the import and commit it)",
			]
		)
	)


## A character as the contract asks for it, less `drop_bone` and `drop_clip`, with `once` (a loop
## of the contract) playing once.
func _character(drop_bone: String = "", drop_clip: String = "", once: String = "") -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	var role: Dictionary = _contract.get("character", {})
	var skeleton := Skeleton3D.new()
	for bone: Variant in role.get("bones", []):
		if str(bone) != drop_bone:
			skeleton.add_bone(str(bone))
	root.add_child(skeleton)
	var library := AnimationLibrary.new()
	for clip: Variant in role.get("clips", []):
		var spec: Dictionary = clip
		var clip_name := str(spec["name"])
		if clip_name == drop_clip:
			continue
		var animation := Animation.new()
		animation.length = 1.0
		var loops: bool = spec["loop"] == true and clip_name != once
		animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		library.add_animation(clip_name, animation)
	var player := AnimationPlayer.new()
	player.add_animation_library("", library)
	root.add_child(player)
	return root


func _character_params() -> Dictionary:
	return {
		"nodes/root_type": "",
		"nodes/root_scale": 1.0,
		"nodes/apply_root_scale": true,
		"animation/import": true,
		"animation/fps": 30,
		"_subresources": {"nodes": {"PATH:AnimationPlayer": {"optimizer/enabled": false}}},
	}


## A Git LFS pointer file at `path`, as a checkout without LFS content has it.
func _write_pointer(path: String) -> void:
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(
		"version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize 10756\n" % "0".repeat(64)
	)
	file.close()


func _remove_tree(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(dir_path + file)
	for sub: String in dir.get_directories():
		_remove_tree(dir_path + sub + "/")
	DirAccess.remove_absolute(dir_path)
