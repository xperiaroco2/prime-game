extends GdUnitTestSuite
## net/ uses nothing game-specific (ARCHITECTURE §1, §4.4, net/CLAUDE.md): no script under net/
## names a class declared under core/. Comments and strings are ignored.

const NET := "res://net/"
const CORE := "res://core/"


func test_net_names_no_core_class() -> void:
	var core_classes := _core_classes()
	assert_bool(core_classes.has("GameMode")).is_true()
	var names := RegEx.create_from_string("\\b(%s)\\b" % "|".join(core_classes))
	var found := PackedStringArray()
	for path: String in _scripts(NET):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for index: int in lines.size():
			var code := _code_of(lines[index])
			for match: RegExMatch in names.search_all(code):
				found.append("%s:%d %s" % [path, index + 1, match.get_string()])
	assert_array(Array(found)).is_empty()


func test_the_check_sees_a_core_class() -> void:
	var names := RegEx.create_from_string("\\b(%s)\\b" % "|".join(_core_classes()))
	assert_object(names.search(_code_of("static func of(mode: GameMode) -> int:"))).is_not_null()
	assert_object(names.search(_code_of("## the mode's GameMode, in a comment"))).is_null()
	assert_object(names.search(_code_of('var name := "GameMode"  # GameMode'))).is_null()


func _core_classes() -> PackedStringArray:
	var found := PackedStringArray()
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if (entry["path"] as String).begins_with(CORE):
			found.append(entry["class"] as String)
	return found


## The code of one line: without its strings and its comment.
func _code_of(line: String) -> String:
	var code := ""
	var quote := ""
	for character: String in line:
		if quote.is_empty():
			if character == "#":
				break
			if character == '"' or character == "'":
				quote = character
				continue
			code += character
		elif character == quote:
			quote = ""
	return code


func _scripts(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir.path_join(sub)))
	return found
