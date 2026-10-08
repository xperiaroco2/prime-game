extends GdUnitTestSuite
## The shared greybox theme (client/CLAUDE.md; the M4 manager's decision of 2026-10-01 on #144):
## every screen in client/ui/ is styled only through GameUi.THEME. A source test over client/ui/'s
## scripts (the theme files under client/ui/theme/ excepted) fails on an inline theme override
## (`add_theme_*_override`), a colour written in code (`Color(...)` or a named `Color.X`) or a font
## size; comments and strings are stripped first (E18's source test's `strip`). A colour that comes
## from the model (a circle's) passes, since no literal names it. And GameUi gives the theme to
## every Control child, also one added later.

const Boundary := preload("res://tests/unit/client/app/client_boundary_test.gd")
const UI := "res://client/ui"
const THEME_DIR := "res://client/ui/theme"
const OVERRIDE := "\\badd_theme_\\w+_override\\b"
const COLOUR := "\\bColor\\s*\\(|\\bColor\\s*\\.\\s*[A-Z_]+\\b"
const FORBIDDEN := OVERRIDE + "|" + COLOUR + "|\\bfont_size\\b"


func test_no_screen_styles_itself_inline() -> void:
	var files := _scripts(UI)
	assert_bool(files.has(UI.path_join("hud.gd"))).is_true()
	assert_bool(files.has(UI.path_join("lobby_panel.gd"))).is_true()
	var found := PackedStringArray()
	for path: String in files:
		for problem: String in problems(FileAccess.get_file_as_string(path)):
			found.append("%s: %s" % [path, problem])
	assert_array(found).is_empty()


func test_it_rejects_the_planted_overrides_and_accepts_the_theme() -> void:
	# The planted failures: what the screens did before the theme.
	assert_array(problems('label.add_theme_font_size_override(&"font_size", 28)')).has_size(1)
	assert_array(problems("label.font_size = 28")).has_size(1)
	assert_array(problems('column.add_theme_constant_override(&"separation", 10)')).has_size(1)
	assert_array(problems("black.color = Color(0.05, 0.05, 0.07)")).has_size(1)
	assert_array(problems("black.color = Color.BLACK")).has_size(1)
	assert_array(problems("label.modulate = Color (1.0, 0.75, 0.4)")).has_size(1)
	assert_array(problems('margin.add_theme_stylebox_override(&"panel", box)')).has_size(1)
	# Allowed: a type variation, a colour from the model, a typed field, comments and strings.
	var allowed := (
		'label.theme_type_variation = &"Title"\n'
		+ "swatch.color = shown.destination_colour\n"
		+ "var destination_colour: Color\n"
		+ "# no Color(1, 0, 0) or add_theme_color_override in a comment\n"
		+ 'var words := "a font_size of Color.RED in a string"\n'
	)
	assert_array(problems(allowed)).is_empty()


func test_every_screen_has_the_theme_also_one_added_later() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	var later := Label.new()
	ui.add_child(later)
	var screens := 0
	for child: Node in ui.get_children():
		var control := child as Control
		if control == null:
			continue
		screens += 1
		assert_object(control.theme).is_same(GameUi.THEME)
	assert_int(screens).is_greater(8)
	# A screen that brought its own theme keeps it.
	var own := Theme.new()
	var themed := Label.new()
	themed.theme = own
	ui.add_child(themed)
	assert_object(themed.theme).is_same(own)


func test_every_type_variation_the_screens_name_is_in_the_theme() -> void:
	var named := RegEx.create_from_string('&"([A-Za-z]+)"')
	var variation := RegEx.create_from_string(
		(
			"theme_type_variation|styled_label|backdrop|variation: StringName ="
			+ "|UiParts\\.(button|raised|toggle|scroll)\\(|ToyBar\\.new\\("
		)
	)
	var missing := PackedStringArray()
	for path: String in _scripts(UI):
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if variation.search(line) == null:
				continue
			for hit: RegExMatch in named.search_all(line):
				var type := StringName(hit.get_string(1))
				if not _is_variation(type):
					missing.append("%s: %s" % [path, type])
	assert_array(missing).is_empty()


## What the theme rule forbids in `source`, one entry per match, after E18's strip().
static func problems(source: String) -> PackedStringArray:
	var found := PackedStringArray()
	var code := Boundary.strip(source)
	for hit: RegExMatch in RegEx.create_from_string(FORBIDDEN).search_all(code):
		found.append("styles inline: %s" % hit.get_string())
	return found


func _is_variation(type: StringName) -> bool:
	return not GameUi.THEME.get_type_variation_base(type).is_empty()


## Every script under `dir`, the theme's folder left out.
func _scripts(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		var path := dir.path_join(sub)
		if path != THEME_DIR:
			found.append_array(_scripts(path))
	return found
