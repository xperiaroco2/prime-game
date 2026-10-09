extends GdUnitTestSuite
## PlayerNames (ARCHITECTURE §3.5, #550): clean() drops controls, trims blank edges and keeps 16
## characters; unique() adds " 2", " 3" to a name a present player has, ignoring case, within 16
## characters. Invisible characters are built with String.chr (gdformat writes a \u escape of one
## above U+009F as the character itself).

const NBSP := 0xA0
const BOM := 0xFEFF
const ZERO_WIDTH := 0x200B
const EM_SPACE := 0x2003
const IDEOGRAPHIC_SPACE := 0x3000


func test_clean_trims_and_keeps_a_good_name() -> void:
	assert_str(PlayerNames.clean("Dima")).is_equal("Dima")
	assert_str(PlayerNames.clean("  Dima  ")).is_equal("Dima")
	assert_str(PlayerNames.clean(&"Dima")).is_equal("Dima")
	assert_str(PlayerNames.clean("Діма Ш")).is_equal("Діма Ш")
	assert_str(PlayerNames.clean("a  b")).is_equal("a  b")


func test_clean_drops_controls_and_the_byte_order_mark() -> void:
	assert_str(PlayerNames.clean("a\nb\tc\u0007\u009f")).is_equal("abc")
	assert_str(PlayerNames.clean("a\u009fb")).is_equal("ab")
	assert_str(PlayerNames.clean("\u007fDima\u0001")).is_equal("Dima")
	assert_str(PlayerNames.clean(_c(BOM) + "Di" + _c(BOM) + "ma")).is_equal("Dima")


func test_clean_trims_unicode_blanks_at_the_edges_only() -> void:
	var edged := _c(NBSP) + _c(IDEOGRAPHIC_SPACE) + "Dima" + _c(ZERO_WIDTH) + _c(EM_SPACE)
	assert_str(PlayerNames.clean(edged)).is_equal("Dima")
	var inside := "Di" + _c(NBSP) + "ma"
	assert_str(PlayerNames.clean(inside)).is_equal(inside)
	# Blanks and controls alone are no name.
	for blank: String in [
		"", "   ", _c(NBSP), _c(IDEOGRAPHIC_SPACE) + _c(ZERO_WIDTH), "\n\t\u0007\u001f", " \u0085 "
	]:
		assert_str(PlayerNames.clean(blank)).override_failure_message(blank.c_escape()).is_empty()


func test_clean_keeps_16_characters() -> void:
	assert_str(PlayerNames.clean("x".repeat(10000))).is_equal("x".repeat(16))
	assert_str(PlayerNames.clean("abcdefghijklmnopqrstuvwxyz")).is_equal("abcdefghijklmnop")
	# Counted in characters, not bytes: 16 Cyrillic letters (32 bytes) and 16 four-byte ones.
	assert_str(PlayerNames.clean("Д".repeat(40))).is_equal("Д".repeat(16))
	var emoji := _c(0x1F600)
	assert_str(PlayerNames.clean(emoji.repeat(17))).is_equal(emoji.repeat(16))
	assert_int(PlayerNames.clean(emoji.repeat(17)).to_utf8_buffer().size()).is_equal(64)
	# A cut that ends on a blank is trimmed again; controls do not count toward the 16.
	assert_str(PlayerNames.clean("fifteen letters x")).is_equal("fifteen letters")
	assert_str(PlayerNames.clean("\u0007".repeat(5) + "y".repeat(20))).is_equal("y".repeat(16))


func test_clean_of_anything_but_text_is_empty() -> void:
	for odd: Variant in [null, 7, 1.5, true, ["Dima"], {"name": "Dima"}, PackedByteArray([65])]:
		assert_str(PlayerNames.clean(odd)).is_empty()


func test_unique_keeps_a_free_name() -> void:
	assert_str(PlayerNames.unique("Dima", PackedStringArray())).is_equal("Dima")
	var others := PackedStringArray(["Ann", "Dimas", "Dim"])
	assert_str(PlayerNames.unique("Dima", others)).is_equal("Dima")


func test_unique_adds_the_first_free_number_ignoring_case() -> void:
	assert_str(PlayerNames.unique("Dima", PackedStringArray(["Dima"]))).is_equal("Dima 2")
	assert_str(PlayerNames.unique("dima", PackedStringArray(["Dima"]))).is_equal("dima 2")
	var taken := PackedStringArray(["Dima", "DIMA 2", "Ann"])
	assert_str(PlayerNames.unique("Dima", taken)).is_equal("Dima 3")
	assert_str(PlayerNames.unique("Діма", PackedStringArray(["ДІМА"]))).is_equal("Діма 2")
	# A number freed by a leaver is taken again.
	var gap := PackedStringArray(["Dima", "Dima 3"])
	assert_str(PlayerNames.unique("Dima", gap)).is_equal("Dima 2")


func test_unique_stays_within_16_characters() -> void:
	var long := "abcdefghijklmnop"
	assert_str(PlayerNames.unique(long, PackedStringArray([long]))).is_equal("abcdefghijklmn 2")
	var taken := PackedStringArray([long])
	for number: int in range(2, 12):
		var found := PlayerNames.unique(long, taken)
		assert_int(found.length()).is_less_equal(PlayerNames.MAX_CHARS)
		taken.append(found)
	assert_str(taken[-1]).is_equal("abcdefghijklm 11")
	# The cut base loses a blank it ends on.
	var spaced := "abcdefghijklm op"
	assert_str(PlayerNames.unique(spaced, PackedStringArray([spaced]))).is_equal("abcdefghijklm 2")


func test_unique_always_finds_a_name() -> void:
	var taken := PackedStringArray(["P"])
	for number: int in range(2, 40):
		taken.append("p %d" % number)
	assert_str(PlayerNames.unique("P", taken)).is_equal("P 40")


func test_dropped_and_blank_characters() -> void:
	for code: int in [0, 0x1F, 0x7F, 0x80, 0x9F, 0xD800, 0xDFFF, BOM, 0x110000]:
		assert_bool(PlayerNames.is_dropped(code)).override_failure_message("%x" % code).is_true()
	for code: int in [0x20, 0x41, 0x7E, NBSP, 0x414, 0xD7FF, 0xE000, 0xFFFD, 0x1F600, 0x10FFFF]:
		assert_bool(PlayerNames.is_dropped(code)).override_failure_message("%x" % code).is_false()
	assert_bool(PlayerNames.is_blank(0x41)).is_false()
	assert_bool(PlayerNames.is_blank(IDEOGRAPHIC_SPACE)).is_true()


func _c(code: int) -> String:
	return String.chr(code)
