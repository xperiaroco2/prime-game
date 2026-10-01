extends GdUnitTestSuite
## E18's boundary (ARCHITECTURE §4.7, the M4 ADR): no client/ file, client/app/ included, names
## HostSession or core/'s state (Match, MatchState, PeerView, Snapshots) or reads `.game`, so the
## host's own player sees only what its ClientSession decoded; and client/app/ alone names server/,
## through HostNode only. Comments and strings are stripped first, the names matched
## case-sensitive and word-bounded, so SnapshotBuffer and DecodedView.snapshots pass.

const CLIENT := "res://client"
const APP := "res://client/app"
const SERVER := "res://server/"
## The façade client/app/ may name (E18).
const FACADE := &"HostNode"
## `.game` as a property (HostSession.game); a call such as WireSchema.game(debug) passes.
const FORBIDDEN := "\\b(HostSession|Match|MatchState|PeerView|Snapshots)\\b|\\.game\\b(?!\\s*\\()"


func test_no_client_file_reads_the_host_or_core_state() -> void:
	var found := PackedStringArray()
	var files := _client_files(CLIENT)
	assert_int(files.size()).is_greater(10)
	assert_bool(files.has(APP.path_join("game.gd"))).is_true()
	for path: String in files:
		for problem: String in problems(FileAccess.get_file_as_string(path)):
			found.append("%s: %s" % [path, problem])
	assert_array(found).is_empty()


func test_only_client_app_names_server_and_only_its_facade() -> void:
	var server_classes := _server_classes()
	assert_bool(server_classes.has(FACADE)).is_true()
	assert_bool(server_classes.has(&"HostSession")).is_true()
	var found := PackedStringArray()
	for path: String in _client_files(CLIENT):
		var in_app := path.begins_with(APP + "/")
		var code := strip(FileAccess.get_file_as_string(path))
		for server_class: StringName in server_classes:
			if in_app and server_class == FACADE:
				continue
			if RegEx.create_from_string("\\b%s\\b" % server_class).search(code) != null:
				found.append("%s names %s" % [path, server_class])
	assert_array(found).is_empty()


func test_it_rejects_the_planted_reads_and_accepts_the_look_alikes() -> void:
	# The planted failures of E18: a Snapshots.for_peer call and a typed handle's `.game`.
	assert_array(problems("var avatars := Snapshots.for_peer(state, 2)")).has_size(1)
	assert_array(problems("var host: HostNode\nvar game := _host.game")).has_size(1)
	assert_array(problems("func f(m: MatchState) -> void:\n\tpass")).has_size(1)
	assert_array(problems("var s: HostSession = null")).has_size(1)
	assert_array(problems("var v: PeerView\nvar m := Match.new()")).has_size(2)
	# Look-alikes and mentions pass: other names, comments, strings and StringNames.
	var allowed := (
		"var buffer := SnapshotBuffer.new()\n"
		+ "var ticks := view.snapshots.keys()\n"
		+ 'var ended := MatchEndedEvent.new(&"crew")\n'
		+ "var gamer := own.gamepad\n"
		+ "var schema := WireSchema.game(true)\n"
		+ "# HostSession and Match are only named in this comment: _host.game\n"
		+ 'var text := "Snapshots.for_peer and .game in a string" # and Match\n'
		+ 'var id := &"Match"\n'
		+ "var doc := '''MatchState in a long string\n.game'''\n"
	)
	assert_array(problems(allowed)).is_empty()


## What the boundary forbids in `source`, one entry per match, after strip().
static func problems(source: String) -> PackedStringArray:
	var found := PackedStringArray()
	var code := strip(source)
	for hit: RegExMatch in RegEx.create_from_string(FORBIDDEN).search_all(code):
		found.append("names %s" % hit.get_string())
	return found


## `source` with every comment and every string literal (quoted, triple-quoted, StringName and
## NodePath alike) replaced by a space, so only code is matched.
static func strip(source: String) -> String:
	var out := ""
	var i := 0
	var size := source.length()
	while i < size:
		var c := source[i]
		if c == "#":
			while i < size and source[i] != "\n":
				i += 1
			continue
		if c == '"' or c == "'":
			var quote := c.repeat(3) if source.substr(i, 3) == c.repeat(3) else c
			i += quote.length()
			while i < size and source.substr(i, quote.length()) != quote:
				i += 2 if source[i] == "\\" else 1
			i += quote.length()
			out += " "
			continue
		out += c
		i += 1
	return out


## Every .gd file under `dir`, recursively.
static func _client_files(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		found.append_array(_client_files(dir.path_join(sub)))
	return found


## The global class names declared in server/.
static func _server_classes() -> Array[StringName]:
	var found: Array[StringName] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry["path"]).begins_with(SERVER):
			found.append(StringName(str(entry["class"])))
	return found
