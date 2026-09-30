extends GdUnitTestSuite
## core/ stays pure (root CLAUDE.md invariant 3, core/CLAUDE.md): no Node or scene, no file, OS or
## clock access, no networking, and no global RNG, in any script under core/. Comments are
## ignored; a method called on an object (`rng.randi_range(...)`) is allowed.

const CORE := "res://core/"
## Engine classes and singletons core/ must not name.
const FORBIDDEN_NAMES := [
	"Node",
	"Node2D",
	"Node3D",
	"SceneTree",
	"PackedScene",
	"Engine",
	"OS",
	"Time",
	"FileAccess",
	"DirAccess",
	"ResourceLoader",
	"ResourceSaver",
	"MultiplayerAPI",
	"MultiplayerPeer",
	"ENetMultiplayerPeer",
	"PacketPeer\\w*",
	"StreamPeer\\w*",
	"TCPServer",
	"UDPServer",
	"HTTPClient",
	"HTTPRequest",
	"WebSocket\\w*",
	"IP",
	"Thread",
	"WorkerThreadPool",
	"Mutex",
	"Semaphore",
	"ProjectSettings",
	"Audio\\w*",
	"Input",
]
## Global functions that use the global RNG or load files; allowed only as methods of an object.
const FORBIDDEN_CALLS := [
	"randi",
	"randf",
	"randi_range",
	"randf_range",
	"randfn",
	"randomize",
	"seed",
	"load",
	"preload",
	"hash",
]
## Array methods that use the global RNG; hash() (no documented algorithm, §3.3) and
## get_instance_id() (differs between runs), which would break a replay.
const FORBIDDEN_METHODS := ["shuffle", "pick_random", "hash", "get_instance_id"]


func test_core_names_no_engine_class_it_must_not_use() -> void:
	var names := RegEx.create_from_string("\\b(%s)\\b" % "|".join(FORBIDDEN_NAMES))
	var calls := RegEx.create_from_string("(?<![.\\w])(%s)\\s*\\(" % "|".join(FORBIDDEN_CALLS))
	var methods := RegEx.create_from_string("\\.(%s)\\s*\\(" % "|".join(FORBIDDEN_METHODS))
	var found: Array[String] = []
	var scripts := _scripts(CORE)
	assert_int(scripts.size()).is_greater(30)
	for path: String in scripts:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := _code_of(lines[i])
			for pattern: RegEx in [names, calls, methods]:
				var hit := pattern.search(code)
				if hit != null:
					found.append("%s:%d: %s" % [path, i + 1, hit.get_string()])
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


func test_the_check_sees_a_forbidden_call() -> void:
	var calls := RegEx.create_from_string("(?<![.\\w])(%s)\\s*\\(" % "|".join(FORBIDDEN_CALLS))
	assert_object(calls.search(_code_of("\tvar x := randi() # a comment"))).is_not_null()
	assert_object(calls.search(_code_of("\tvar x := rng.randi_range(0, 3)"))).is_null()
	assert_object(calls.search(_code_of("\t## randi() in a doc comment"))).is_null()


func test_the_check_sees_a_forbidden_name_and_method() -> void:
	var names := RegEx.create_from_string("\\b(%s)\\b" % "|".join(FORBIDDEN_NAMES))
	var methods := RegEx.create_from_string("\\.(%s)\\s*\\(" % "|".join(FORBIDDEN_METHODS))
	assert_object(names.search("\tvar peer := PacketPeerUDP.new()")).is_not_null()
	assert_object(names.search("\tvar player := AudioStreamPlayer.new()")).is_not_null()
	assert_object(names.search("\tvar t := Thread.new()")).is_not_null()
	assert_object(names.search("\tvar kind := ItemKind.new()")).is_null()
	assert_object(methods.search("\tvar s := String(purpose).hash()")).is_not_null()
	assert_object(methods.search("\tvar i := item.get_instance_id()")).is_not_null()
	assert_object(methods.search("\tvar h := ContentHash.of(mode)")).is_null()


## The line without its comment; a `#` inside a string ends nothing.
static func _code_of(line: String) -> String:
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote.is_empty():
			if c == "#":
				return line.substr(0, i)
			if c == '"' or c == "'":
				quote = c
		elif c == quote and (i == 0 or line[i - 1] != "\\"):
			quote = ""
	return line


static func _scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		found.append_array(_scripts(dir_path.path_join(sub)))
	return found
