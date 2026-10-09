extends GdUnitTestSuite
## LobbyName (ARCHITECTURE §3.5, #214): the lobby's name keeps 20 characters and is cleaned like a
## player's name (PlayerNames.clean_to): controls and invisible characters dropped, blank edges
## trimmed; "" is the default. Invisible characters are built with String.chr (gdformat writes a \u
## escape of one above U+009F as the character itself).

const NBSP := 0xA0
const ZERO_WIDTH := 0x200B
const IDEOGRAPHIC_SPACE := 0x3000


func test_a_good_name_stays_as_it_is() -> void:
	assert_str(LobbyName.clean("Dima's den")).is_equal("Dima's den")
	assert_str(LobbyName.clean(&"Den")).is_equal("Den")
	assert_str(LobbyName.clean("Лобі Діми")).is_equal("Лобі Діми")


func test_keeps_20_characters() -> void:
	assert_int(LobbyName.MAX_CHARS).is_equal(20)
	assert_str(LobbyName.clean("x".repeat(20))).is_equal("x".repeat(20))
	assert_str(LobbyName.clean("x".repeat(21))).is_equal("x".repeat(20))
	assert_str(LobbyName.clean("abcdefghijklmnopqrstuvwxyz")).is_equal("abcdefghijklmnopqrst")
	# Counted in characters, not bytes: 20 four-byte characters are 80 bytes.
	var emoji := _c(0x1F600)
	assert_str(LobbyName.clean(emoji.repeat(25))).is_equal(emoji.repeat(20))
	assert_int(LobbyName.clean(emoji.repeat(25)).to_utf8_buffer().size()).is_equal(80)
	# A cut that ends on a blank is trimmed again.
	assert_str(LobbyName.clean("nineteen characters x")).is_equal("nineteen characters")


func test_trims_blank_edges_and_drops_invisible_characters() -> void:
	var edged := _c(NBSP) + "  Den" + _c(ZERO_WIDTH) + _c(IDEOGRAPHIC_SPACE)
	assert_str(LobbyName.clean(edged)).is_equal("Den")
	for code: int in [0x07, 0x7F, 0x9F, 0x200B, 0x200F, 0x2028, 0x202E, 0x2060, 0x2066, 0xFEFF]:
		var hidden := "D" + _c(code) + "en"
		assert_str(LobbyName.clean(hidden)).override_failure_message("%x" % code).is_equal("Den")
	# Dropped characters do not count toward the 20.
	assert_str(LobbyName.clean("\u0007".repeat(5) + "y".repeat(30))).is_equal("y".repeat(20))


func test_nothing_usable_is_the_default() -> void:
	for blank: Variant in ["", "   ", _c(NBSP) + _c(ZERO_WIDTH), "\n\t", null, 7, ["Den"]]:
		assert_str(LobbyName.clean(blank)).override_failure_message(str(blank)).is_empty()


func test_a_players_name_still_keeps_16() -> void:
	assert_str(PlayerNames.clean("x".repeat(20))).is_equal("x".repeat(16))
	assert_str(PlayerNames.clean_to("x".repeat(20), 16)).is_equal("x".repeat(16))


func _c(code: int) -> String:
	return String.chr(code)
