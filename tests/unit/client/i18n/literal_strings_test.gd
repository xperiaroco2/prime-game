extends GdUnitTestSuite
## No player-facing text outside the copy deck (#549, #208 part c; ARCHITECTURE §4.7.48): a source
## test over client/'s scripts and scenes (client/dev/'s previews left out) lists every string
## literal that reads as words and fails on one that is neither a deck key nor in the allow-list
## `literals_allowed.txt` beside this test. Words: any Cyrillic, Latin words with a space between
## ("Hold %s to raise"), and one capitalised word where it is text: a Control's text, a value named
## for text (`const MAP_LABEL := "Map"`) or a tr() argument; elsewhere one word is a node's name.
##
## Not words: keys, ids and paths (lowercase, snake_case, dotted, PascalCase compounds), formats
## with no words ("%02d:%02d"), StringName and NodePath literals (`&"..."`, `^"..."`), comments,
## a string inside a log or assert call (push_error, print, assert...), one inside a call
## that names an engine thing (a node, a signal, a setting, a file...) and a node's name
## (`.name = "Row"`). What the scan cannot see: words built at run time (a content name, the
## host text's ids, #548), an all-caps word ("OK"), text a variable not named for text carries, and
## player-facing literals outside client/ that reach a screen (voice/voice_capture.gd's notices on
## the voice panel); review catches those.
##
## The allow-list holds the rest, one line each: `<path under client/> | <literal as written> |
## <why>`; the why names the issue or comment tracking a missing deck key, or says why the text is
## never shown. `*` as the literal allows a whole file (a debug-only screen). An entry that matches
## nothing fails too, so the list never outlives its literals.

const CLIENT := "res://client"
const LEFT_OUT: Array[String] = ["res://client/dev"]
const ALLOWED := "res://tests/unit/client/i18n/literals_allowed.txt"
const DECK := "res://client/i18n/strings.csv"
## Calls whose strings go to a log or a developer, never the screen (any depth).
const DEV_CALLS: Array[String] = [
	"assert",
	"print",
	"print_debug",
	"print_rich",
	"printerr",
	"printraw",
	"prints",
	"printt",
	"push_error",
	"push_warning",
]
## Calls whose strings name an engine thing, never shown (the innermost call only).
const PLUMBING_CALLS: Array[String] = [
	"add_to_group",
	"call",
	"call_deferred",
	"connect",
	"create_from_string",
	"emit_signal",
	"find_child",
	"find_children",
	"get_meta",
	"get_node",
	"get_node_or_null",
	"get_setting",
	"get_value",
	"has_meta",
	"has_method",
	"has_node",
	"has_section_key",
	"has_signal",
	"is_class",
	"is_in_group",
	"load",
	"preload",
	"set_meta",
	"set_value",
]
## A scene's properties that show text.
const SCENE_TEXT := '^(text|tooltip_text|placeholder_text|title) = "(.*)"$'
const NODE_NAME := "(^|\\.)\\s*name\\s*=\\s*$"
const PLACEHOLDER := "\\{[^}]*\\}|%[-+0-9.*]*[a-zA-Z%]"
## Where one word is text: a value whose name says so (`label.text =`, `const MAP_LABEL :=`),
## or a call that shows or translates it. Elsewhere a capitalised word is a node's name ("Row").
const TEXT_NAMED := (
	"(?i)(label|text|title|caption|hint|message|words|prompt|tooltip)\\w*"
	+ "\\s*(:\\s*[A-Za-z_\\[\\], ]*)?:?=\\s*$"
)
const TEXT_CALLS: Array[String] = ["add_item", "add_tab", "set_tab_title", "set_text", "tr", "tr_n"]
const NOT_WORDS := 0
const ONE_WORD := 1
const PHRASE := 2


## A string literal: its text as written, its line, whether it is a StringName or NodePath (`&`,
## `^`), the calls it sits in (outermost first; "" for a bracket that is no call) and its
## statement's code before it, strings as `""`.
class Literal:
	extends RefCounted
	var text := ""
	var line := 0
	var sigil := false
	var calls: Array[String] = []
	var before := ""

	func _init(at: int, written: String) -> void:
		line = at
		text = written


## One line of the allow-list.
class Entry:
	extends RefCounted
	var path := ""
	var literal := ""
	var why := ""


func test_no_player_facing_literal_outside_the_deck() -> void:
	var files := _files(CLIENT)
	assert_bool(files.has("res://client/ui/lobby_panel.gd")).is_true()
	assert_bool(files.has("res://client/app/game.tscn")).is_true()
	var allowed := allow_list(FileAccess.get_file_as_string(ALLOWED))
	var keys := deck_keys()
	var found := PackedStringArray()
	for path: String in files:
		for hit: Literal in candidates_in(path, keys):
			if not _allows(allowed, _short(path), hit.text):
				found.append('%s:%d: "%s"' % [_short(path), hit.line, hit.text])
	(
		assert_array(found)
		. override_failure_message(
			(
				"Player-facing literals outside the copy deck (a deck key, or a line in %s):\n%s"
				% [ALLOWED, "\n".join(found)]
			)
		)
		. is_empty()
	)


func test_every_allowed_entry_has_a_reason_and_a_literal() -> void:
	var allowed := allow_list(FileAccess.get_file_as_string(ALLOWED))
	assert_int(allowed.size()).is_greater(0)
	var keys := deck_keys()
	var unused := PackedStringArray()
	for entry: Entry in allowed:
		(
			assert_str(entry.why)
			. override_failure_message("no reason: %s | %s" % [entry.path, entry.literal])
			. is_not_empty()
		)
		var path := "res://".path_join(entry.path)
		assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
		var used := false
		for hit: Literal in candidates_in(path, keys):
			used = used or entry.literal == "*" or entry.literal == hit.text
		if not used:
			unused.append("%s | %s" % [entry.path, entry.literal])
	assert_array(unused).override_failure_message("allowed but not found: %s" % unused).is_empty()


func test_it_finds_the_planted_literals() -> void:
	var keys: Array[String] = ["menu.host"]
	var planted := (
		'label.text = "Start"\n'
		+ 'return "%s: pick up %s" % [key, what]\n'
		+ "var note := (\n\t'Ready when you are'\n)\n"
		+ 'button.text = "Хост"\n'
		+ 'const MAP_LABEL := "Map"\n'
		+ 'label.text = """Two\nlines"""\n'
		+ 'var raw := r"Some \\ words"\n'
	)
	var texts := _texts(words_in(planted, keys))
	(
		assert_array(texts)
		. contains_exactly(
			[
				"Start",
				"%s: pick up %s",
				"Ready when you are",
				"Хост",
				"Map",
				"Two\nlines",
				"Some \\ words",
			]
		)
	)
	assert_int(words_in(planted, keys)[2].line).is_equal(4)
	assert_int(words_in(planted, keys)[6].line).is_equal(10)
	# One word is text only where it is shown or translated.
	var one_word := (
		'title_label.text = "Lobby"\n'
		+ 'var words := tr("Ready")\n'
		+ 'list.add_child(SettingRows.row("Window", "settings.window", chips))\n'
		+ 'const ROW_NAMES := {&"jump": "Jump"}\n'
	)
	assert_array(_texts(words_in(one_word, keys))).contains_exactly(["Lobby", "Ready"])


## A conditional expression and a parenthesised value are text where the
## statement's target is named for text (the review of #549). An all-caps word ("OK") is not seen.
func test_it_finds_one_word_text_after_an_if_or_a_parenthesis() -> void:
	var keys: Array[String] = []
	var planted := (
		'label.text = "Ready" if ok else "Waiting"\n'
		+ 'label.text = (\n\t"Closed"\n)\n'
		+ 'var node := Row.new("Waiting" if ok else "Idle")\n'
	)
	assert_array(_texts(words_in(planted, keys))).contains_exactly(["Ready", "Waiting", "Closed"])


func test_it_passes_keys_ids_logs_and_names() -> void:
	var keys: Array[String] = ["menu.host", "Join game"]
	var allowed := (
		'label.text = "menu.host"\n'
		+ 'label.text = "Join game"\n'
		+ 'var id := "package"\n'
		+ 'var path := "res://client/ui/hud.gd"\n'
		+ 'var clock := "%02d:%02d" % [m, s]\n'
		+ 'var type := "ToyRowEight"\n'
		+ 'var named := &"Toy Words"\n'
		+ 'var node := ^"Some Path"\n'
		+ '# a comment with "Some words" in it\n'
		+ 'push_error("A thing went wrong: %s" % why)\n'
		+ 'push_warning(\n\t"Over two lines"\n\t+ " still a log"\n)\n'
		+ 'assert(ok, "Never shown")\n'
		+ 'row.name = "Allowed"\n'
		+ 'name = "Root"\n'
		+ 'var row := get_node_or_null("Some Row")\n'
		+ 'button.pressed.connect(_on_pressed.bind("Host Game"))\n'
		+ 'connect("Some Signal", _on)\n'
		+ 'label.text = "{name}"\n'
		+ 'label.text = "   "\n'
	)
	assert_array(_texts(words_in(allowed, keys))).contains_exactly(["Host Game"])


func test_it_reads_the_allow_list_and_a_scene_text() -> void:
	var listed := allow_list(
		(
			"# a comment\n\n"
			+ "client/ui/lobby_panel.gd | Map | #150 comment 6095875901\n"
			+ "client/ui/debug_overlay.gd | * | debug builds only\n"
		)
	)
	assert_array(listed).has_size(2)
	assert_str(listed[0].path).is_equal("client/ui/lobby_panel.gd")
	assert_str(listed[0].literal).is_equal("Map")
	assert_str(listed[0].why).is_equal("#150 comment 6095875901")
	assert_bool(_allows(listed, "client/ui/debug_overlay.gd", "FPS: %d")).is_true()
	assert_bool(_allows(listed, "client/ui/lobby_panel.gd", "Map")).is_true()
	assert_bool(_allows(listed, "client/ui/lobby_panel.gd", "Maps")).is_false()
	var scene := '[node name="Label" type="Label"]\ntext = "Hello there"\nname_text = "x"\n'
	assert_array(_texts(scene_words(scene, []))).contains_exactly(["Hello there"])


func test_words_tell_text_from_ids() -> void:
	for text: String in ["pick up", "Хост", "{name} is ready", "%d of %d tasks", "Mouse %d"]:
		assert_int(shape(text)).override_failure_message(text).is_equal(PHRASE)
	for text: String in ["Map", "Ready!", "Off", "Player%d"]:
		assert_int(shape(text)).override_failure_message(text).is_equal(ONE_WORD)
	for text: String in ["", " ", "package", "menu.host", "ToyRowEight", "snake_case", "%02d:%02d"]:
		assert_int(shape(text)).override_failure_message(text).is_equal(NOT_WORDS)
	for text: String in ["res://a b.tscn", "{name}", "HUD", "x", "1.0", "%d s"]:
		assert_int(shape(text)).override_failure_message(text).is_equal(NOT_WORDS)


## The candidates of one file under client/: a script's word literals or a scene's texts.
static func candidates_in(path: String, keys: Array[String]) -> Array[Literal]:
	var source := FileAccess.get_file_as_string(path)
	return scene_words(source, keys) if path.ends_with(".tscn") else words_in(source, keys)


## A scene's text properties that read as words and are no deck key.
static func scene_words(source: String, keys: Array[String]) -> Array[Literal]:
	var found: Array[Literal] = []
	var text := RegEx.create_from_string(SCENE_TEXT)
	var lines := source.split("\n")
	for at: int in lines.size():
		var hit := text.search(lines[at])
		var text_now := hit.get_string(2) if hit != null else ""
		if shape(text_now) != NOT_WORDS and not keys.has(text_now):
			found.append(Literal.new(at + 1, hit.get_string(2)))
	return found


## A script's string literals that read as words, are no deck key and are not a log's, an engine
## call's or a node's name.
static func words_in(source: String, keys: Array[String]) -> Array[Literal]:
	var found: Array[Literal] = []
	var node_name := RegEx.create_from_string(NODE_NAME)
	var text_named := RegEx.create_from_string(TEXT_NAMED)
	for literal: Literal in literals(source):
		var reads := shape(literal.text)
		if literal.sigil or keys.has(literal.text) or reads == NOT_WORDS:
			continue
		var innermost: String = literal.calls.back() if not literal.calls.is_empty() else ""
		if (
			reads == ONE_WORD
			and not (TEXT_CALLS.has(innermost) or text_named.search(_assigned_to(literal.before)))
		):
			continue
		var in_log := literal.calls.any(func(called: String) -> bool: return DEV_CALLS.has(called))
		var plumbing := not literal.calls.is_empty() and PLUMBING_CALLS.has(literal.calls.back())
		if in_log or plumbing or node_name.search(literal.before) != null:
			continue
		found.append(literal)
	return found


## What a literal is assigned to: its statement's code before it, less the opening parentheses
## and the `"" if ... else ` of a conditional expression in between.
static func _assigned_to(before: String) -> String:
	var between := RegEx.create_from_string('(\\s*\\(+\\s*|""\\s+if\\s.*\\selse\\s*)$')
	var found := between.search(before)
	while found != null and found.get_start() > 0:
		before = before.left(found.get_start())
		found = between.search(before)
	return before


## Every string literal of a GDScript source (Literal), comments left out.
static func literals(source: String) -> Array[Literal]:
	var found: Array[Literal] = []
	var callee := RegEx.create_from_string("([A-Za-z_][A-Za-z_0-9]*)\\s*$")
	var calls: Array[String] = []
	var statement := ""
	var line := 1
	var i := 0
	var size := source.length()
	while i < size:
		var c := source[i]
		if c == "#":
			while i < size and source[i] != "\n":
				i += 1
			continue
		if c == "\n":
			line += 1
			statement = statement + " " if not calls.is_empty() or statement.ends_with("\\") else ""
			i += 1
			continue
		if c == '"' or c == "'":
			var raw := statement.ends_with("r") and not _ends_in_word(statement.left(-1))
			var prefix := statement.left(-1) if raw else statement
			var quote := c.repeat(3) if source.substr(i, 3) == c.repeat(3) else c
			var start := i + quote.length()
			var end := start
			while end < size and source.substr(end, quote.length()) != quote:
				end += 2 if source[end] == "\\" and not raw else 1
			var literal := Literal.new(line, source.substr(start, end - start))
			literal.sigil = prefix.ends_with("&") or prefix.ends_with("^")
			literal.calls = calls.duplicate()
			literal.before = prefix.trim_suffix("&").trim_suffix("^")
			found.append(literal)
			line += literal.text.count("\n")
			statement += '""'
			i = end + quote.length()
			continue
		if c in ["(", "[", "{"]:
			var hit := callee.search(statement) if c == "(" else null
			calls.append(hit.get_string(1) if hit != null else "")
		elif c in [")", "]", "}"] and not calls.is_empty():
			calls.pop_back()
		statement += c
		i += 1
	return found


## How a literal reads: PHRASE (any Cyrillic letter, or Latin words with a space between, a
## placeholder counting as a word: "Mouse %d"), ONE_WORD (one capitalised word: "Map") or
## NOT_WORDS (ids, keys, paths, compounds, placeholders and numbers alone).
static func shape(text: String) -> int:
	if text.contains("://"):
		return NOT_WORDS
	var placeholder := RegEx.create_from_string(PLACEHOLDER)
	var bare := placeholder.sub(text, " ", true)
	if RegEx.create_from_string("[\\x{0400}-\\x{04FF}]").search(bare) != null:
		return PHRASE
	if RegEx.create_from_string("[A-Za-z]{2,}").search(bare) == null:
		return NOT_WORDS
	var marked := placeholder.sub(text, "X", true)
	if RegEx.create_from_string("[A-Za-z][^\\n]*\\s[^\\n]*[A-Za-z]").search(marked) != null:
		return PHRASE
	if RegEx.create_from_string("^[A-Z][a-z]+[!?.:]?$").search(bare.strip_edges()) != null:
		return ONE_WORD
	return NOT_WORDS


## The allow-list's entries; blank lines and `#` lines left out.
static func allow_list(text: String) -> Array[Entry]:
	var found: Array[Entry] = []
	for row: String in text.split("\n"):
		if row.strip_edges().is_empty() or row.begins_with("#"):
			continue
		var cells := row.split(" | ")
		var entry := Entry.new()
		entry.path = cells[0].strip_edges()
		entry.literal = cells[1] if cells.size() > 1 else ""
		entry.why = cells[2].strip_edges() if cells.size() > 2 else ""
		found.append(entry)
	return found


## The copy deck's keys (a plural's other forms have none).
static func deck_keys() -> Array[String]:
	var keys: Array[String] = []
	var file := FileAccess.open(DECK, FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1 and not row[0].is_empty():
			keys.append(row[0])
	return keys


static func _allows(allowed: Array[Entry], path: String, text: String) -> bool:
	return allowed.any(
		func(entry: Entry) -> bool:
			return entry.path == path and (entry.literal == "*" or entry.literal == text)
	)


static func _ends_in_word(code: String) -> bool:
	return not code.is_empty() and RegEx.create_from_string("[A-Za-z0-9_]$").search(code) != null


static func _short(path: String) -> String:
	return path.trim_prefix("res://")


static func _texts(hits: Array[Literal]) -> Array[String]:
	var texts: Array[String] = []
	for hit: Literal in hits:
		texts.append(hit.text)
	return texts


## Every script and scene under `dir`, recursively, LEFT_OUT's folders left out.
static func _files(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not LEFT_OUT.has(dir.path_join(sub)):
			found.append_array(_files(dir.path_join(sub)))
	return found
