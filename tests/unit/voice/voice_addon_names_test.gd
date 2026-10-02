extends GdUnitTestSuite
## E34 (the M5 ADR §1.3): no project script outside addons/ names a TwoVoIP class as an
## identifier, so every script parses where the extension is not loaded (CI on Linux, a clone
## before the addon's download). TwoVoipCodec names them only in strings, for ClassDB. Comments and
## strings are stripped first (the E18 boundary test's strip()), the names matched case-sensitive
## and word-bounded. Like `check`, the scan leaves out the scratch folder, folders whose name starts
## with "." (a checkout's .claude/worktrees would hold every worktree's copy) and folders holding a
## .gdignore.

const Boundary := preload("res://tests/unit/client/app/client_boundary_test.gd")
const NAMES := "\\b(TwovoipOpusEncoder|AudioStreamOpus|AudioStreamPlaybackOpus)\\b"
const SKIPPED: Array[String] = ["res://addons", "res://.godot", "res://tests/scratch"]
const SCAN_PROBE := "user://voice_addon_names_scan"


func test_no_script_outside_addons_names_a_twovoip_class() -> void:
	var files := _scripts("res://")
	assert_bool(files.has("res://voice/two_voip_codec.gd")).is_true()
	var found := PackedStringArray()
	for path: String in files:
		for problem: String in problems(FileAccess.get_file_as_string(path)):
			found.append("%s: %s" % [path, problem])
	assert_array(found).is_empty()


func test_it_rejects_the_planted_names_and_accepts_strings_and_comments() -> void:
	assert_array(problems("var encoder := TwovoipOpusEncoder.new()")).has_size(1)
	assert_array(problems("var stream := AudioStreamOpus.new()")).has_size(1)
	assert_array(problems("var p := x as AudioStreamPlaybackOpus")).has_size(1)
	assert_array(problems("func f(e: TwovoipOpusEncoder) -> AudioStreamOpus:")).has_size(2)
	var allowed := (
		'const ENCODER_CLASS := &"TwovoipOpusEncoder"\n'
		+ "# AudioStreamPlaybackOpus is named only in this comment\n"
		+ 'var text := "AudioStreamOpus"\n'
		+ "var stream := AudioStreamOpusLike.new()\n"
		+ "var mine := MyAudioStreamOpus.new()\n"
	)
	assert_array(problems(allowed)).is_empty()


func test_the_scan_skips_dot_folders_and_gdignored_ones() -> void:
	var files := PackedStringArray(
		["kept/a.gd", ".hidden/b.gd", "ignored/c.gd", "ignored/.gdignore"]
	)
	for file: String in files:
		var path := SCAN_PROBE.path_join(file)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		FileAccess.open(path, FileAccess.WRITE).close()
	var found := _scripts(SCAN_PROBE)
	for file: String in files:
		DirAccess.remove_absolute(SCAN_PROBE.path_join(file))
	for dir: String in ["kept", ".hidden", "ignored", ""]:
		DirAccess.remove_absolute(SCAN_PROBE.path_join(dir))
	assert_array(Array(found)).contains_exactly([SCAN_PROBE.path_join("kept/a.gd")])


## The TwoVoIP class names `source` uses as identifiers, after strip().
static func problems(source: String) -> PackedStringArray:
	var found := PackedStringArray()
	var code := Boundary.strip(source)
	for hit: RegExMatch in RegEx.create_from_string(NAMES).search_all(code):
		found.append("names %s" % hit.get_string())
	return found


## Every .gd file under `dir`, recursively, outside the skipped folders, those whose name starts
## with "." and those holding a .gdignore (as `check` collects them).
static func _scripts(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	if SKIPPED.has(dir.trim_suffix("/")) or FileAccess.file_exists(dir.path_join(".gdignore")):
		return found
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			found.append_array(_scripts(dir.path_join(sub)))
	return found
