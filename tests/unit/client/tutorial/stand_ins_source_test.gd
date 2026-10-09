extends GdUnitTestSuite
## Only stand_ins.gd names a stand-in's session (docs/design/tutorial.md §2.2, #601): the game never
## reads a stand-in's model, so what the player sees of one comes from the own session like any
## other player's. Held three ways: no client/ file but stand_ins.gd and the game's tutorial wiring
## names StandIns (comments and strings stripped, as client_boundary_test does); that wiring never
## walks into the node (no child or node lookups); and StandIns' public members hand out no session,
## transport, model or session node.

const BOUNDARY := preload("res://tests/unit/client/app/client_boundary_test.gd")
const CLIENT := "res://client"
const STAND_INS := "res://client/tutorial/stand_ins.gd"
const WIRING := "res://client/app/game_tutorial.gd"
## The classes a stand-in's session could leak through.
const LEAKS: Array[StringName] = [
	&"ClientSession", &"ClientModel", &"NetTransport", &"LoopbackTransport", &"SessionNode"
]
const LEAK_WORDS := ["session", "client", "model", "transport"]
## Lookups into another node's children.
const LOOKUPS := "\\b(get_child|get_children|find_child|find_children|get_node|get_node_or_null)\\b"


func test_only_the_stand_ins_and_the_tutorial_wiring_name_them() -> void:
	var files := BOUNDARY._client_files(CLIENT)
	assert_bool(files.has(STAND_INS)).is_true()
	var found := PackedStringArray()
	for path: String in files:
		if path == STAND_INS or path == WIRING:
			continue
		found.append_array(names_problems(path, FileAccess.get_file_as_string(path)))
	assert_array(found).is_empty()


func test_the_tutorial_wiring_never_looks_inside_them() -> void:
	assert_bool(FileAccess.file_exists(WIRING)).is_true()
	assert_array(lookup_problems(FileAccess.get_file_as_string(WIRING))).is_empty()


func test_their_public_members_hand_out_no_session() -> void:
	var script := load(STAND_INS) as Script
	var found := PackedStringArray()
	for method: Dictionary in script.get_script_method_list():
		var name := str(method["name"])
		var returned: Dictionary = method["return"]
		found.append_array(member_problems(name, str(returned.get("class_name", ""))))
	for property: Dictionary in script.get_script_property_list():
		found.append_array(member_problems(str(property["name"]), str(property["class_name"])))
	assert_array(found).is_empty()


func test_it_rejects_the_planted_reads() -> void:
	# A file naming the node, the wiring reaching a child, and a public getter of a session.
	assert_array(names_problems("x.gd", "var s := StandIns.new(hub, mode, 1)")).has_size(1)
	assert_array(names_problems("x.gd", "# StandIns in a comment\nvar t := 'StandIns'")).is_empty()
	assert_array(lookup_problems("var s := stand_ins.get_child(0)")).has_size(1)
	assert_array(lookup_problems("# get_child in a comment")).is_empty()
	assert_array(member_problems("sessions", "")).has_size(1)
	assert_array(member_problems("first", "ClientSession")).has_size(1)
	assert_array(member_problems("_sessions", "")).is_empty()
	assert_array(member_problems("count", "")).is_empty()


static func names_problems(path: String, source: String) -> PackedStringArray:
	var found := PackedStringArray()
	if RegEx.create_from_string("\\bStandIns\\b").search(BOUNDARY.strip(source)) != null:
		found.append("%s names StandIns" % path)
	return found


static func lookup_problems(source: String) -> PackedStringArray:
	var found := PackedStringArray()
	for hit: RegExMatch in RegEx.create_from_string(LOOKUPS).search_all(BOUNDARY.strip(source)):
		found.append("calls %s" % hit.get_string())
	return found


## A public member (no leading underscore) named for a session or typed as one of LEAKS.
static func member_problems(name: String, type_name: String) -> PackedStringArray:
	var found := PackedStringArray()
	if name.begins_with("_"):
		return found
	for word: String in LEAK_WORDS:
		if name.to_lower().contains(word):
			found.append("%s is named for a %s" % [name, word])
	if LEAKS.has(StringName(type_name)):
		found.append("%s is a %s" % [name, type_name])
	return found
