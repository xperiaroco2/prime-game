extends RefCounted
## The import check of the art handoff (#519, docs/ARCHITECTURE.md §11): every committed GLB loads
## headless and keeps the import options the art repo's docs/godot.md asks for; a character GLB
## under assets/characters/ has the skeleton and the clips of tools/assets/asset_contract.json;
## an image under assets/ keeps its folder's compression. Static, so the test
## (tests/unit/tools/asset_import_test.gd) runs it on the committed files and on broken fixtures
## built in memory. Each problem is one line that starts with the asset's path and says what is
## missing or wrong.

const CONTRACT_PATH := "res://tools/assets/asset_contract.json"
const ASSETS := "res://assets/"
## Folders never searched for assets: third-party code, Godot's cache, run output, scratch probes.
const SKIP_DIRS: Array[String] = [
	"res://addons",
	"res://.godot",
	"res://tools/out",
	"res://tests/scratch",
]
## Every image format Godot imports as a texture that .gitattributes routes through LFS.
const IMAGE_EXTENSIONS: Array[String] = [
	"png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr"
]
## The first line of a Git LFS pointer file (the spec; tools/runner/lfs.py reads it the same way).
const LFS_POINTER := "version https://git-lfs.github.com/spec/v1"
## A pointer file is small; a real asset that starts with these bytes would be larger.
const LFS_POINTER_MAX_BYTES := 1024


static func load_contract(path: String = CONTRACT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data as Dictionary if data is Dictionary else {}


## Every file under `root` with one of `extensions`, outside SKIP_DIRS, sorted.
static func find_files(root: String, extensions: Array[String]) -> PackedStringArray:
	var found := PackedStringArray()
	_walk(root if root.ends_with("/") else root + "/", extensions, found)
	found.sort()
	return found


## `base` ends in "/" (res:// itself does).
static func _walk(base: String, extensions: Array[String], found: PackedStringArray) -> void:
	if base.trim_suffix("/") in SKIP_DIRS:
		return
	var dir := DirAccess.open(base)
	if dir == null:
		return
	for name: String in dir.get_files():
		if name.get_extension().to_lower() in extensions:
			found.append(base + name)
	for name: String in dir.get_directories():
		if not name.begins_with("."):
			_walk(base + name + "/", extensions, found)


## True for the bytes of a Git LFS pointer file: a checkout without LFS content (CI) has these
## where the asset should be, so the asset cannot be checked there.
static func is_lfs_pointer_bytes(head: PackedByteArray, size: int) -> bool:
	if size >= LFS_POINTER_MAX_BYTES:
		return false
	return head.get_string_from_utf8().begins_with(LFS_POINTER)


static func is_lfs_pointer(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var size := file.get_length()
	var head := file.get_buffer(mini(size, LFS_POINTER.length()))
	return is_lfs_pointer_bytes(head, size)


static func is_character(path: String, contract: Dictionary) -> bool:
	return path.begins_with(str(_dict(contract, "folders").get("characters", "\u0000")))


## The [params] of an asset's committed .import file, or null when it has none.
static func import_params(path: String) -> Variant:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK:
		return null
	var params := {}
	if config.has_section("params"):
		for key: String in config.get_section_keys("params"):
			params[key] = config.get_value("params", key)
	return params


## The problems of one GLB's committed .import file. It is text, so a checkout without LFS
## content (CI) has it beside the pointer file and it is checked there too.
static func check_glb_import(path: String, contract: Dictionary) -> PackedStringArray:
	var params: Variant = import_params(path)
	if params == null:
		return PackedStringArray(
			["%s: no committed .import file (run the import and commit it)" % path]
		)
	return check_glb_params(path, params as Dictionary, contract, is_character(path, contract))


## The problems of one GLB: its .import options, then its scene (loaded and instantiated).
static func check_glb(path: String, contract: Dictionary) -> PackedStringArray:
	var problems := check_glb_import(path, contract)
	var character := is_character(path, contract)
	if not ResourceLoader.exists(path):
		problems.append("%s: does not load (the import failed or was never run)" % path)
		return problems
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		problems.append("%s: does not load as a scene" % path)
		return problems
	var root := scene.instantiate()
	if root == null:
		problems.append("%s: its scene does not instantiate" % path)
		return problems
	if character:
		problems.append_array(check_character(path, root, contract))
	root.free()
	return problems


## The glTF import options every GLB keeps, and a character's own (art docs/godot.md).
static func check_glb_params(
	path: String, params: Dictionary, contract: Dictionary, character: bool
) -> PackedStringArray:
	var want := _dict(contract, "glb_params").duplicate()
	var role := _dict(contract, "character")
	if character:
		want.merge(_dict(role, "params"), true)
	var problems := PackedStringArray()
	for key: String in want:
		if key.begins_with("_"):
			continue
		if not params.has(key):
			problems.append("%s: .import has no %s (want %s)" % [path, key, _show(want[key])])
		elif not _same(params[key], want[key]):
			problems.append(
				"%s: .import %s=%s, want %s" % [path, key, _show(params[key]), _show(want[key])]
			)
	if character:
		problems.append_array(_check_player_options(path, params, _dict(role, "player_options")))
	return problems


static func _check_player_options(
	path: String, params: Dictionary, want: Dictionary
) -> PackedStringArray:
	var node_key := "PATH:%s" % str(want.get("node", "AnimationPlayer"))
	var nodes := _dict(_dict(params, "_subresources"), "nodes")
	var options := _dict(nodes, node_key)
	var problems := PackedStringArray()
	for key: String in want:
		if key.begins_with("_") or key == "node":
			continue
		if not options.has(key):
			problems.append(
				(
					"%s: .import _subresources nodes %s has no %s (want %s)"
					% [path, node_key, key, _show(want[key])]
				)
			)
		elif not _same(options[key], want[key]):
			problems.append(
				(
					"%s: .import _subresources nodes %s %s=%s, want %s"
					% [path, node_key, key, _show(options[key]), _show(want[key])]
				)
			)
	return problems


## A character scene: one Skeleton3D with every contract bone, one AnimationPlayer with every
## contract clip, each looping exactly when the contract says so.
static func check_character(path: String, root: Node, contract: Dictionary) -> PackedStringArray:
	var role := _dict(contract, "character")
	var problems := PackedStringArray()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		problems.append("%s: has %d Skeleton3D nodes, want 1" % [path, skeletons.size()])
	else:
		var skeleton := skeletons[0] as Skeleton3D
		var missing := PackedStringArray()
		for bone: Variant in _list(role, "bones"):
			if skeleton.find_bone(str(bone)) == -1:
				missing.append(str(bone))
		if not missing.is_empty():
			problems.append(
				(
					"%s: the skeleton lacks %d contract bones: %s"
					% [path, missing.size(), ", ".join(missing)]
				)
			)
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		problems.append("%s: has %d AnimationPlayer nodes, want 1" % [path, players.size()])
		return problems
	var player := players[0] as AnimationPlayer
	var missing_clips := PackedStringArray()
	for clip: Variant in _list(role, "clips"):
		var spec: Dictionary = clip as Dictionary if clip is Dictionary else {}
		var name := str(spec.get("name", ""))
		if not player.has_animation(name):
			missing_clips.append(name)
			continue
		var loops := player.get_animation(name).loop_mode != Animation.LOOP_NONE
		var should_loop: bool = spec.get("loop", false) == true
		if loops and not should_loop:
			problems.append("%s: the clip %s loops, the contract says it plays once" % [path, name])
		elif not loops and should_loop:
			var why := "the contract says it loops (a _Loop suffix in the art export)"
			problems.append("%s: the clip %s plays once, %s" % [path, name, why])
	if not missing_clips.is_empty():
		var has := ", ".join(player.get_animation_list())
		var lacks := ", ".join(missing_clips)
		var line := "%s: lacks %d contract clips: %s (it has: %s)"
		problems.append(line % [path, missing_clips.size(), lacks, has])
	return problems


## An image under a folder of `texture_compress_mode` keeps that compress/mode.
static func check_texture(path: String, params: Variant, contract: Dictionary) -> PackedStringArray:
	var modes := _dict(contract, "texture_compress_mode")
	for folder: String in modes:
		if folder.begins_with("_") or not path.begins_with(folder):
			continue
		if params == null:
			return PackedStringArray(["%s: no committed .import file" % path])
		var have: Variant = (params as Dictionary).get("compress/mode")
		if have == null or not _same(have, modes[folder]):
			return PackedStringArray(
				[
					(
						"%s: .import compress/mode=%s, want %s for %s"
						% [path, _show(have), _show(modes[folder]), folder]
					)
				]
			)
	return PackedStringArray()


## Every committed asset under `root`: the problems, and the LFS pointer files whose scene it could
## not load (their .import files are still checked).
static func check_all(contract: Dictionary, root: String = "res://") -> Dictionary:
	var problems := PackedStringArray()
	var pointers := PackedStringArray()
	for path: String in find_files(root, ["glb", "gltf"]):
		if is_lfs_pointer(path):
			pointers.append(path)
			problems.append_array(check_glb_import(path, contract))
		else:
			problems.append_array(check_glb(path, contract))
	for path: String in find_files(ASSETS, IMAGE_EXTENSIONS):
		problems.append_array(check_texture(path, import_params(path), contract))
	return {"problems": problems, "pointers": pointers}


static func _same(have: Variant, want: Variant) -> bool:
	if (have is int or have is float) and (want is int or want is float):
		var a: float = have
		var b: float = want
		return is_equal_approx(a, b)
	return typeof(have) == typeof(want) and have == want


static func _dict(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	return value as Dictionary if value is Dictionary else {}


static func _list(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key, [])
	return value as Array if value is Array else []


## A value as the .import file writes it: a whole number from the JSON contract without ".0".
static func _show(value: Variant) -> String:
	if value is float:
		var number: float = value
		if number == floorf(number) and absf(number) < 1e9:
			return str(int(number))
	return str(value)
