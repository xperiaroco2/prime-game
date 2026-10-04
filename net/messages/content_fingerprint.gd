class_name ContentFingerprint
extends RefCounted
## The content hash that Hello carries (ARCHITECTURE §4.3 "The content", E1): the game mode's
## ContentHash combined with the SHA-256 of every level file the mode names (the lobby, then the
## maps in order) and of every scene and resource file those levels reach through their
## dependencies (#118). ContentHash covers scripts and levels only by path, so without the files a
## designer's branch that moved a wall, in a map or in a room the map instances, would join main
## and meet unexplained corrections. Any byte of a level or of what it reaches counts; a missing
## file counts as missing.
##
## The walk follows ResourceLoader.get_dependencies from each level that exists, recursively, each
## file once (a cycle or a piece two levels share is walked once), and hashes what it reaches in
## the order of its res:// path. A dependency with a uid is the file the uid names, as Godot loads
## it, else its fallback path. Left out: scripts (ContentHash covers them by path, #118 keeps them
## out) and Godot's generated files under res://.godot/ (made from sources the walk hashes). An
## imported asset counts by its source bytes and its `.import` settings.
##
## In an exported build (#369) a file counts by what the export ships in its place: the export
## converts a text scene or resource to binary under res://.godot/exported/ and leaves a
## `<path>.remap` naming it, and ships an imported asset as its import products, named by the
## `[remap]` of the `.import` it rewrites, without the source. So a level a build ships is found,
## and a level byte that reaches the build changes its hash; the hash of an export differs from
## the source's (another build, §2.5 of the M6 ADR).
##
## net/ names no core/ class (§1), so the caller passes the mode's parts. The host's server/ and
## every client call it the same way, from their own copy of the mode:
## `ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)`.

## The extensions of the scripts the walk leaves out.
const SCRIPT_EXTENSIONS: PackedStringArray = ["gd", "cs"]
## Where Godot keeps the files it generates (imports, caches): never hashed.
const GENERATED := "res://.godot/"


## The fingerprint of a mode whose ContentHash is `content_hash`, with its lobby level and maps,
## an s64: the first 8 bytes of the SHA-256 of `text_of`. Each file the levels reach that is not
## there gets one warning naming it (`missing_from`), so the machine that lacks a room has the
## reason for its wrong_content refusal in its log. A missing level file gets none: the unit
## tests' fixture modes name levels that do not exist.
static func of(content_hash: int, lobby_level: String, maps: PackedStringArray) -> int:
	var levels := _levels_of(lobby_level, maps)
	var reached := reached_from(levels)
	for path: String in _missing_in(reached):
		push_warning("content: %s, which a level reaches, is missing (hashed as missing)" % path)
	return _text(content_hash, levels, reached).sha256_buffer().decode_s64(0)


## What `of` hashes, one line each: `mode <ContentHash>`; `level <path> <sha256>` per level in the
## mode's order; then `file <path> <sha256>` per file the levels reach, by path. `missing` stands
## for the digest of a file that is not there, so the text names a missing dependency. A mode whose
## levels reach nothing has no `file` line.
static func text_of(content_hash: int, lobby_level: String, maps: PackedStringArray) -> String:
	var levels := _levels_of(lobby_level, maps)
	return _text(content_hash, levels, reached_from(levels))


## The files `levels` reach that are not there, sorted by path: what `of` warns about.
static func missing_from(levels: PackedStringArray) -> PackedStringArray:
	return _missing_in(reached_from(levels))


## Every file the walk reaches from `levels`, sorted, the levels themselves and what it leaves out
## (scripts, res://.godot/) excluded; a missing file is listed and not walked further.
static func reached_from(levels: PackedStringArray) -> PackedStringArray:
	var seen: Dictionary[String, bool] = {}
	for level: String in levels:
		seen[level] = true
	var to_walk := levels.duplicate()
	var files := PackedStringArray()
	while not to_walk.is_empty():
		var path := to_walk[to_walk.size() - 1]
		to_walk.remove_at(to_walk.size() - 1)
		# get_dependencies prints an engine error for a file that is not there.
		var shipped := _shipped_as(path)
		if shipped.size() != 1 or not FileAccess.file_exists(shipped[0]):
			continue
		for dependency: String in ResourceLoader.get_dependencies(shipped[0]):
			var target := _target_of(dependency)
			if seen.has(target) or not _hashed(target):
				continue
			seen[target] = true
			files.append(target)
			to_walk.append(target)
			var settings := target + ".import"
			if not seen.has(settings) and FileAccess.file_exists(settings):
				seen[settings] = true
				files.append(settings)
	files.sort()
	return files


static func _levels_of(lobby_level: String, maps: PackedStringArray) -> PackedStringArray:
	var levels := PackedStringArray([lobby_level])
	levels.append_array(maps)
	return levels


static func _text(
	content_hash: int, levels: PackedStringArray, reached: PackedStringArray
) -> String:
	var lines := PackedStringArray(["mode %d" % content_hash])
	for path: String in levels:
		lines.append("level %s %s" % [path, _digest(path)])
	for path: String in reached:
		lines.append("file %s %s" % [path, _digest(path)])
	return "\n".join(lines)


static func _missing_in(files: PackedStringArray) -> PackedStringArray:
	var missing := PackedStringArray()
	for path: String in files:
		if _digest(path) == "missing":
			missing.append(path)
	return missing


## The file a get_dependencies entry names: a bare path, or `uid::type::path` (4.7.2 leaves the
## type empty), where a known uid wins over the fallback path, as when Godot loads it.
static func _target_of(dependency: String) -> String:
	var parts := dependency.split("::")
	if parts.size() < 3:
		return dependency
	var id := ResourceUID.text_to_id(parts[0])
	if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
		return ResourceUID.get_id_path(id)
	return parts[2]


static func _hashed(path: String) -> bool:
	return (
		not path.is_empty()
		and not path.begins_with(GENERATED)
		and not SCRIPT_EXTENSIONS.has(path.get_extension())
	)


## The files `path` is there as: itself; else, in an export, what its `.remap` (a converted scene
## or resource) or its `.import` (an imported asset's products) names, every `path` key of the
## `[remap]` section in key order; else none (missing). Only an export's `.import` counts: the
## editor's has a `[deps]` section, so a deleted source stays missing in a project, not its cache.
static func _shipped_as(path: String) -> PackedStringArray:
	if FileAccess.file_exists(path):
		return PackedStringArray([path])
	for redirect: String in [path + ".remap", path + ".import"]:
		if FileAccess.file_exists(redirect):
			return _remapped_by(redirect)
	return PackedStringArray()


static func _remapped_by(redirect: String) -> PackedStringArray:
	var files := PackedStringArray()
	var config := ConfigFile.new()
	if config.load(redirect) != OK or not config.has_section("remap") or config.has_section("deps"):
		return files
	var keys := config.get_section_keys("remap")
	keys.sort()
	for key: String in keys:
		var target: Variant = config.get_value("remap", key)
		if (key == "path" or key.begins_with("path.")) and target is String:
			files.append(target as String)
	return files


## The SHA-256 of what `path` is there as (`_shipped_as`), the products' digests joined by `+`;
## `missing` when it is not there or a file it names is not.
static func _digest(path: String) -> String:
	var shipped := _shipped_as(path)
	var digests := PackedStringArray()
	for file: String in shipped:
		var digest := FileAccess.get_sha256(file) if FileAccess.file_exists(file) else ""
		if digest.is_empty():
			return "missing"
		digests.append(digest)
	return "+".join(digests) if not digests.is_empty() else "missing"
