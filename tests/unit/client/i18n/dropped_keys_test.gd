extends GdUnitTestSuite
## The deck rows the game no longer reads (#1643): the engineer dropped the lobby's Character tab
## (prime-game-ui s05) on 2026-11-19; the character changes only at the mirror. No script of the
## client names its three keys, so the UI lane can drop the rows from the deck.

const CLIENT := "res://client"
const DROPPED: Array[String] = ["esc.tab.character", "esc.character.colour", "esc.character.hat"]


func test_no_client_script_reads_the_character_tabs_keys() -> void:
	var found := PackedStringArray()
	for path: String in _scripts(CLIENT):
		var text := FileAccess.get_file_as_string(path)
		for key: String in DROPPED:
			if text.contains(key):
				found.append("%s | %s" % [path, key])
	assert_array(Array(found)).is_empty()
	# The same scan finds a key the menu does read, so it would see one of these too.
	var read := 0
	for path: String in _scripts(CLIENT):
		if FileAccess.get_file_as_string(path).contains("esc.tab.settings"):
			read += 1
	assert_int(read).is_greater(0)


func _scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(dir_path.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir_path):
		out.append_array(_scripts(dir_path.path_join(sub)))
	return out
