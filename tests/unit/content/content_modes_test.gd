extends GdUnitTestSuite
## The mode check over `content/` (ARCHITECTURE §9.1): every game mode in `content/modes/` loads as
## a GameMode and passes ModeCheck without layouts. The check with the levels' layouts joins in 2j,
## when the levels exist. This is one of the two tests that load `content/` (§9.6).

const MODES_DIR := "res://content/modes/"


func test_every_mode_in_content_passes_the_mode_check() -> void:
	var paths := _mode_paths(MODES_DIR)
	assert_array(paths).contains(["res://content/modes/base_mode.tres"])
	for path: String in paths:
		var mode := load(path) as GameMode
		assert_object(mode).override_failure_message("%s is not a GameMode" % path).is_not_null()
		if mode == null:
			continue
		var check := ModeCheck.run(mode)
		(
			assert_array(Array(check.errors))
			. override_failure_message("%s: %s" % [path, "\n".join(check.errors)])
			. is_empty()
		)


func test_a_match_of_the_base_mode_starts_in_the_lobby() -> void:
	var mode := load("res://content/modes/base_mode.tres") as GameMode
	var game := Match.new(mode, 1, FlatWorldQuery.new(), {})
	assert_bool(game.start(0)).is_true()
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.command_log.mode_path).is_equal("res://content/modes/base_mode.tres")
	assert_int(game.command_log.mode_hash).is_equal(ContentHash.of(mode))


func _mode_paths(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			found.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		found.append_array(_mode_paths(dir_path.path_join(sub)))
	found.sort()
	return found
