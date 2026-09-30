extends GdUnitTestSuite
## ContentFingerprint (ARCHITECTURE §4.3 "The content", E1): the same mode and level files give
## the same value; a changed byte of a level file, or of the mode, gives another.

var _dir := ""


func before_test() -> void:
	# The process id keeps two worktrees' runs, which share user://, apart.
	_dir = "user://content_fingerprint_test_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_dir)
	_write("lobby.tscn", "lobby")
	_write("map.tscn", "map")


func after_test() -> void:
	for file: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file))
	DirAccess.remove_absolute(_dir)


func test_the_same_mode_and_files_give_the_same_value() -> void:
	assert_int(ContentFingerprint.of(_mode())).is_equal(ContentFingerprint.of(_mode()))


func test_a_changed_level_file_gives_another_value() -> void:
	var before := ContentFingerprint.of(_mode())
	_write("map.tscn", "map with a moved wall")
	assert_int(ContentFingerprint.of(_mode())).is_not_equal(before)
	_write("map.tscn", "map")
	assert_int(ContentFingerprint.of(_mode())).is_equal(before)
	_write("lobby.tscn", "lobby with a light")
	assert_int(ContentFingerprint.of(_mode())).is_not_equal(before)


func test_a_changed_mode_gives_another_value() -> void:
	var before := ContentFingerprint.of(_mode())
	var mode := _mode()
	mode.player_rules.walk_speed_mps += 0.5
	assert_int(ContentFingerprint.of(mode)).is_not_equal(before)


func test_a_missing_level_file_gives_another_value() -> void:
	var before := ContentFingerprint.of(_mode())
	DirAccess.remove_absolute(_dir.path_join("map.tscn"))
	assert_int(ContentFingerprint.of(_mode())).is_not_equal(before)


func test_the_content_mode_has_a_fingerprint() -> void:
	var mode: GameMode = load("res://content/modes/base_mode.tres")
	assert_int(ContentFingerprint.of(mode)).is_equal(ContentFingerprint.of(mode))
	assert_int(ContentFingerprint.of(mode)).is_not_equal(ContentHash.of(mode))


func _mode() -> GameMode:
	var mode := FixtureBaseMode.mode()
	mode.lobby_level = _dir.path_join("lobby.tscn")
	mode.maps = PackedStringArray([_dir.path_join("map.tscn")])
	return mode


func _write(file: String, text: String) -> void:
	var out := FileAccess.open(_dir.path_join(file), FileAccess.WRITE)
	out.store_string(text)
	out.close()
