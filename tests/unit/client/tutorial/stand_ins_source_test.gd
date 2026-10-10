extends GdUnitTestSuite
## Only stand_ins.gd names a stand-in's session (docs/design/tutorial.md §2.2, #601): the game never
## reads a stand-in's model, so what the player sees of one comes from the own session like any
## other player's. Held four ways: no client/ file but stand_ins.gd and the game's tutorial wiring
## names StandIns, in code or in a node path string (comments stripped; the wiring keeps its one
## STAND_INS_NAME); no client/ file but stand_ins.gd touches its private sessions or transports, and
## ClientSession.new( is only in stand_ins.gd and game.gd (the own session); that wiring never walks
## into the node (no child or node lookups); and StandIns' public members hand out no session,
## transport, model or session node.

const BOUNDARY := preload("res://tests/unit/client/app/client_boundary_test.gd")
const CLIENT := "res://client"
const STAND_INS := "res://client/tutorial/stand_ins.gd"
const WIRING := "res://client/app/game_tutorial.gd"
const OWN_SESSION := "res://client/app/game.gd"
## The classes a stand-in's session could leak through.
const LEAKS: Array[StringName] = [
	&"ClientSession", &"ClientModel", &"NetTransport", &"LoopbackTransport", &"SessionNode"
]
const LEAK_WORDS := ["session", "client", "model", "transport"]
## Lookups into another node's children.
const LOOKUPS := "\\b(get_child|get_children|find_child|find_children|get_node|get_node_or_null)\\b"
## The stand-ins' private lists, and the wiring's private field read from outside.
const PRIVATES := "\\b_sessions\\b|\\b_transports\\b|\\._stand_ins\\b"


func test_only_the_stand_ins_and_the_tutorial_wiring_name_them() -> void:
	var files := BOUNDARY._client_files(CLIENT)
	assert_bool(files.has(STAND_INS)).is_true()
	var found := PackedStringArray()
	for path: String in files:
		if path == STAND_INS:
			continue
		var source := FileAccess.get_file_as_string(path)
		found.append_array(private_problems(path, source))
		found.append_array(session_problems(path, source))
		if path != WIRING:
			found.append_array(names_problems(path, source))
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
	# A file naming the node, in code and in a path string; one reading the private lists; one
	# making a second session; the wiring reaching a child; a public getter of a session.
	assert_array(names_problems("x.gd", "var s := StandIns.new(hub, mode, 1)")).has_size(1)
	assert_array(names_problems("x.gd", 'var n := get_node("StandIns/StandIn1")')).has_size(1)
	assert_array(names_problems("x.gd", "# StandIns in a comment\nvar t := 1")).is_empty()
	assert_array(private_problems("x.gd", "var s := stand_ins._sessions[0].model")).has_size(1)
	assert_array(private_problems("x.gd", "var t := stand_ins._transports")).has_size(1)
	assert_array(private_problems("x.gd", "var c := tutorial._stand_ins.count()")).has_size(1)
	assert_array(private_problems("x.gd", "var c := _stand_ins.count()")).is_empty()
	assert_array(private_problems("x.gd", "# _sessions in a comment")).is_empty()
	assert_array(session_problems("x.gd", "var s := ClientSession.new(t, m, w)")).has_size(1)
	assert_array(session_problems(OWN_SESSION, "var s := ClientSession.new(t, m, w)")).is_empty()
	assert_array(session_problems("x.gd", "# ClientSession.new( in a comment")).is_empty()
	assert_array(lookup_problems("var s := stand_ins.get_child(0)")).has_size(1)
	assert_array(lookup_problems("# get_child in a comment")).is_empty()
	assert_array(member_problems("sessions", "")).has_size(1)
	assert_array(member_problems("first", "ClientSession")).has_size(1)
	assert_array(member_problems("_sessions", "")).is_empty()
	assert_array(member_problems("count", "")).is_empty()


## A file naming the stand-ins node: its class, or its name in a path string.
static func names_problems(path: String, source: String) -> PackedStringArray:
	var found := PackedStringArray()
	if RegEx.create_from_string("StandIn").search(without_comments(source)) != null:
		found.append("%s names StandIns" % path)
	return found


## A file other than stand_ins.gd reaching its private lists or the wiring's private field.
static func private_problems(path: String, source: String) -> PackedStringArray:
	var found := PackedStringArray()
	for hit: RegExMatch in RegEx.create_from_string(PRIVATES).search_all(BOUNDARY.strip(source)):
		found.append("%s reads %s" % [path, hit.get_string()])
	return found


## A file but stand_ins.gd and game.gd (the own session) building a ClientSession.
static func session_problems(path: String, source: String) -> PackedStringArray:
	var found := PackedStringArray()
	if path == STAND_INS or path == OWN_SESSION:
		return found
	if RegEx.create_from_string("\\bClientSession\\.new\\(").search(BOUNDARY.strip(source)) != null:
		found.append("%s builds a ClientSession" % path)
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


## `source` with each comment cut at its `#` (one inside a quoted string is kept), strings kept.
static func without_comments(source: String) -> String:
	var lines := PackedStringArray()
	for line: String in source.split("\n"):
		var quote := ""
		var cut := line.length()
		for i in line.length():
			var c := line[i]
			if quote.is_empty() and (c == '"' or c == "'"):
				quote = c
			elif c == quote and (i == 0 or line[i - 1] != "\\"):
				quote = ""
			elif c == "#" and quote.is_empty():
				cut = i
				break
		lines.append(line.substr(0, cut))
	return "\n".join(lines)
