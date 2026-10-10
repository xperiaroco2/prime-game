extends GdUnitTestSuite
## The game's font draws every character of the copy deck (#549, #208 part c; ARCHITECTURE
## §4.7.48): each character of both columns (en, uk) of client/i18n/strings.csv, placeholders
## (`{count}`) and line breaks left out, is in the character map of the real Comfortaa file
## (assets/ui/comfortaa/comfortaa.ttf, #684), read from the file itself with FreeType
## (FontFile.load_dynamic_font, has_char), never Godot's imported copy.
##
## A checkout without Git LFS content (CI, §4.7.21) has a pointer file there and imports a stand-in
## font in its place, which says nothing of Comfortaa's glyphs: there the check prints a `skip` line
## naming the pointer and checks only the pointer; it runs on every machine with the font (`git lfs
## pull`), as the local `test` does.

const Check := preload("res://tools/assets/asset_check.gd")
const FONT := "res://assets/ui/comfortaa/comfortaa.ttf"
const DECK := "res://client/i18n/strings.csv"
const PLACEHOLDER := "\\{[^}]*\\}"
## The deck's columns the game shows.
const COLUMNS: Array[String] = ["en", "uk"]


func test_the_font_has_every_character_of_both_columns() -> void:
	# A renamed column would otherwise go unchecked, the other column alone meeting the floor below.
	var header := deck_rows(DECK)[0]
	for column: String in COLUMNS:
		(
			assert_bool(header.has(column))
			. override_failure_message("no deck column " + column)
			. is_true()
		)
	if Check.is_lfs_pointer(FONT):
		print(
			"skip: %s is a Git LFS pointer (no LFS content here): its glyphs are unchecked" % FONT
		)
		assert_bool(FileAccess.get_file_as_string(FONT).contains("oid sha256:")).is_true()
		return
	var font := real_font(FONT)
	assert_str(font.font_name).is_equal("Comfortaa")
	var characters := deck_characters(deck_rows(DECK))
	assert_int(characters.size()).is_greater(60)
	assert_array(missing(font, characters)).is_empty()


func test_the_deck_characters_cover_both_columns_without_placeholders() -> void:
	var deck: Array[PackedStringArray] = [
		PackedStringArray(["keys", "en", "uk", "?plural", "?context"]),
		PackedStringArray(["a.key", "Hold {key}", "Тримай, {key}", "", "ctx"]),
		PackedStringArray(["", "two\nlines", "Ї", "", ""]),
	]
	var found := deck_characters(deck)
	for character: String in ["H", "o", "l", "d", " ", "Т", "р", "и", "м", "а", "й", ",", "Ї"]:
		(
			assert_bool(found.has(character.unicode_at(0)))
			. override_failure_message(character)
			. is_true()
		)
	# Not the keys, the placeholders, a line break or the other columns.
	for character: String in ["k", "y", "{", "}", "\n", "c", "x"]:
		(
			assert_bool(found.has(character.unicode_at(0)))
			. override_failure_message(character)
			. is_false()
		)


func test_a_missing_glyph_is_named() -> void:
	# Godot's own fallback font as the probe: it has Latin, and no private-use character.
	var font := ThemeDB.fallback_font
	var private_use := 0xE000
	var named := missing(font, ["A".unicode_at(0), private_use])
	assert_array(named).has_size(1)
	assert_str(named[0]).starts_with("U+E000 ")
	# The real font, where it is here, lacks it too: the check can fail.
	if not Check.is_lfs_pointer(FONT):
		assert_array(missing(real_font(FONT), [private_use])).has_size(1)
		assert_array(missing(real_font(FONT), ["Ї".unicode_at(0)])).is_empty()


## The font file at `path`, loaded from its own bytes (not Godot's import).
static func real_font(path: String) -> FontFile:
	var font := FontFile.new()
	var loaded := font.load_dynamic_font(path)
	assert(loaded == OK, "cannot read %s" % path)
	return font


## The deck's rows as Godot's CSV reader reads them, its header first.
static func deck_rows(path: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file := FileAccess.open(path, FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1:
			rows.append(row)
	return rows


## Every character of the deck's shown columns (`rows`, its header first), once, in first-seen
## order.
static func deck_characters(rows: Array[PackedStringArray]) -> Array[int]:
	var found: Array[int] = []
	var placeholder := RegEx.create_from_string(PLACEHOLDER)
	var header := rows[0]
	for row: PackedStringArray in rows.slice(1):
		for column: String in COLUMNS:
			var at := header.find(column)
			if at < 0 or at >= row.size():
				continue
			var text := placeholder.sub(row[at], "", true)
			for i: int in text.length():
				var code := text.unicode_at(i)
				if code >= 0x20 and not found.has(code):
					found.append(code)
	return found


## `U+XXXX 'c'` for each character `font` has no glyph for.
static func missing(font: Font, characters: Array[int]) -> PackedStringArray:
	var found := PackedStringArray()
	for code: int in characters:
		if not font.has_char(code):
			found.append("U+%04X '%s'" % [code, String.chr(code)])
	return found
