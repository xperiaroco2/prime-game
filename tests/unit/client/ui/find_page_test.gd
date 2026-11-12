extends GdUnitTestSuite
## The suit menu's Find a lobby (client/ui/find_page.gd, #1285): prime-game-ui's s05 `ship-find`,
## `ship-empty`, `ship-code` and `ship-direct` at ui-2.5.4 node for node, the code field's alphabet
## and Join at six characters, the address entry's Join and Host and its Back, and the port line.
## The game's wiring (each request leaves the ship first) is game_ship_test.gd's. How it looks:
## the `shot`s of client/dev/esc_ship_*_preview.tscn.

var _page: FindPage
var _codes: Array[String] = []
var _joins: Array = []
var _hosts: Array[int] = []


func before_test() -> void:
	_codes.clear()
	_joins.clear()
	_hosts.clear()
	_page = auto_free(FindPage.new())
	_page.theme = GameUi.THEME
	_page.code_join_requested.connect(func(code: String) -> void: _codes.append(code))
	_page.direct_join_requested.connect(
		func(address: String, port: int) -> void: _joins.append([address, port])
	)
	_page.direct_host_requested.connect(func(port: int) -> void: _hosts.append(port))
	add_child(_page)


func after_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


func test_the_tree_matches_the_handoff_node_for_node() -> void:
	# [path, class, variation, minimum size].
	var nodes: Array = [
		[".", "HBoxContainer", &"ToyRowTwentyFour", Vector2.ZERO],
		["Nearby", "VBoxContainer", &"ToyColumnTwelve", Vector2.ZERO],
		["Nearby/Head", "Label", &"ToyKicker", Vector2.ZERO],
		["Nearby/Scroll", "ScrollContainer", &"ToyScroll", Vector2.ZERO],
		["Nearby/Scroll/List", "VBoxContainer", &"ToyColumnEight", Vector2.ZERO],
		["Nearby/None", "Label", &"ToyTextMutedOnLight", Vector2.ZERO],
		["Nearby/Join", "Button", &"ToyButtonPrimary", Vector2.ZERO],
		["Code", "VBoxContainer", &"ToyColumnTwelve", Vector2(420, 0)],
		["Code/Head", "Label", &"ToyKicker", Vector2.ZERO],
		["Code/Field", "LineEdit", &"ToyField", Vector2.ZERO],
		["Code/Join", "Button", &"ToyButtonSecondary", Vector2.ZERO],
		["Code/Direct", "Button", &"ToyButtonGhostOnLight", Vector2.ZERO],
		["Address", "VBoxContainer", &"ToyColumnTwelve", Vector2(420, 0)],
		["Address/Head", "Label", &"ToyKicker", Vector2.ZERO],
		["Address/Field", "LineEdit", &"ToyField", Vector2.ZERO],
		["Address/Port", "Label", &"ToyTextMutedOnLight", Vector2.ZERO],
		["Address/Buttons", "VBoxContainer", &"ToyColumnTwelve", Vector2.ZERO],
		["Address/Buttons/Join", "Button", &"ToyButtonSecondary", Vector2.ZERO],
		["Address/Buttons/Host", "Button", &"ToyButtonSecondary", Vector2.ZERO],
		["Address/Buttons/Back", "Button", &"ToyButtonGhostOnLight", Vector2.ZERO],
	]
	for row: Array in nodes:
		var node := _page.get_node(str(row[0])) as Control
		assert_object(node).override_failure_message(str(row[0])).is_not_null()
		assert_str(node.get_class()).override_failure_message(str(row[0])).is_equal(str(row[1]))
		assert_str(node.theme_type_variation).override_failure_message(str(row[0])).is_equal(row[2])
		assert_object(node.custom_minimum_size).override_failure_message(str(row[0])).is_equal(
			row[3]
		)
	var texts := {
		"Nearby/Head": "find.nearby",
		"Nearby/None": "find.none",
		"Nearby/Join": "join.connect",
		"Code/Head": "common.code",
		"Code/Join": "join.connect",
		"Code/Direct": "menu.direct",
		"Address/Head": "join.address",
		"Address/Buttons/Join": "join.connect",
		"Address/Buttons/Host": "menu.host",
		"Address/Buttons/Back": "common.back",
	}
	for path: String in texts:
		var control := _page.get_node(path)
		var text: String = (control as Label).text if control is Label else (control as Button).text
		assert_str(text).override_failure_message(path).is_equal(str(texts[path]))


func test_the_code_entry_shows_first_and_the_address_swaps_in_its_place() -> void:
	assert_bool(_page.code_column.visible).is_true()
	assert_bool(_page.address_column.visible).is_false()
	assert_bool(_page.direct_open()).is_false()
	_page.direct_button.pressed.emit()
	assert_bool(_page.direct_open()).is_true()
	assert_bool(_page.code_column.visible).is_false()
	_page.back_button.pressed.emit()
	assert_bool(_page.direct_open()).is_false()
	assert_bool(_page.code_column.visible).is_true()


func test_the_code_field_keeps_the_code_alphabet_and_joins_at_six() -> void:
	assert_int(_page.code_edit.max_length).is_equal(SignalCodec.CODE_LENGTH)
	assert_bool(_page.code_join.disabled).is_true()
	_page.code_edit.text_changed.emit("ab-c")
	assert_str(_page.code_edit.text).is_equal(MainMenu.code_text("ab-c"))
	assert_bool(_page.code_join.disabled).is_true()
	# Join with fewer than six asks nothing.
	_page.code_join.pressed.emit()
	assert_array(_codes).is_empty()
	var code := SignalCodec.CODE_ALPHABET.left(SignalCodec.CODE_LENGTH)
	_page.set_code(code)
	assert_bool(_page.code_join.disabled).is_false()
	_page.code_join.pressed.emit()
	_page.code_edit.text_submitted.emit(code)
	assert_array(_codes).is_equal([MainMenu.code_text(code), MainMenu.code_text(code)])


func test_the_address_joins_and_hosts_on_the_default_or_typed_port() -> void:
	_page.set_default_port(7777)
	assert_bool(_page.address_join.disabled).is_true()
	_page.address_join.pressed.emit()
	assert_array(_joins).is_empty()
	_page.set_address(" 10.0.0.2 ")
	assert_bool(_page.address_join.disabled).is_false()
	_page.address_join.pressed.emit()
	assert_array(_joins).is_equal([["10.0.0.2", 7777]])
	# Host on the default port, or on the one the address names.
	_page.address_host.pressed.emit()
	_page.set_address("10.0.0.2:7900")
	_page.address_host.pressed.emit()
	assert_array(_hosts).is_equal([7777, MainMenu.typed_port("10.0.0.2:7900", 7777)])
	# What was typed stays.
	assert_str(_page.address_edit.text).is_equal("10.0.0.2:7900")


func test_an_address_that_does_not_parse_joins_and_hosts_nowhere() -> void:
	# As the main menu's Direct panel (MainMenu.refresh_buttons): a bad address leaves the ship
	# for nothing otherwise.
	_page.set_default_port(7777)
	_page.set_address("a b")
	assert_bool(_page.address_join.disabled).is_true()
	_page.address_join.pressed.emit()
	_page.set_address("10.0.0.2:99999")
	assert_bool(_page.address_join.disabled).is_true()
	assert_bool(_page.address_host.disabled).is_true()
	_page.address_join.pressed.emit()
	_page.address_host.pressed.emit()
	_page.address_edit.text_submitted.emit("10.0.0.2:99999")
	assert_array(_joins).is_empty()
	assert_array(_hosts).is_empty()


func test_the_port_line_follows_the_default_port_and_the_language() -> void:
	_page.set_default_port(7777)
	assert_str(_page.port_label.text).is_equal(tr("join.port").format({"port": "7777"}))
	TranslationServer.set_locale(Languages.UKRAINIAN)
	await get_tree().process_frame
	assert_str(_page.port_label.text).is_equal(tr("join.port").format({"port": "7777"}))
	assert_str(_page.port_label.text).contains("Порт")


## A lobby found nearby: host number `host`, `players` of 10, a round trip of `ping` ms.
func _found(host: int, players: int, ping: int, code := "", lobby_name := "") -> LobbyFinder.Found:
	var found := LobbyFinder.Found.new()
	found.answer = LobbyBeacon.Answer.new()
	found.answer.host = host
	found.answer.players = players
	found.answer.most = 10
	found.answer.port = 0 if not code.is_empty() else 24600
	found.answer.code = code
	found.answer.host_name = "Host%d" % host
	found.answer.lobby_name = lobby_name
	found.address = "192.168.1.%d" % host
	found.ping_ms = ping
	return found


func test_the_lobbies_nearby_are_rows_the_first_with_room_chosen() -> void:
	# #1316, s05 `ship-find`: one ToyPresetCard toggle per lobby (name, players, round trip), a full
	# one disabled and dim with `connect.fail.full`, the first with room chosen, Join under them.
	var list: Array[LobbyFinder.Found] = [
		_found(1, 10, 9), _found(2, 6, 24), _found(3, 3, 41, "", "Zinga's den")
	]
	_page.show_lobbies(list)
	assert_bool(_page.lobby_scroll.visible).is_true()
	assert_bool(_page.none_label.visible).is_false()
	assert_bool(_page.nearby_join.visible).is_true()
	assert_bool(_page.nearby_join.disabled).is_false()
	assert_int(_page.rows.size()).is_equal(3)
	var row := _page.rows[2]
	# The chosen row draws ToyPresetCardSelected (ToyToggle), the others ToyPresetCard.
	assert_str(row.theme_type_variation).is_equal("ToyPresetCardSelected")
	assert_str(_page.rows[3].theme_type_variation).is_equal("ToyPresetCard")
	assert_bool(row.toggle_mode).is_true()
	assert_float(row.custom_minimum_size.y).is_equal(FindPage.ROW_HEIGHT)
	assert_str((row.get_node(^"H/Name") as Label).text).is_equal("Host2's lobby")
	assert_str((row.get_node(^"H/Count") as Label).text).is_equal("6 / 10")
	assert_str((row.get_node(^"H/Ping") as Label).text).is_equal("24 ms")
	assert_bool((row.get_node(^"H/Full") as Control).visible).is_false()
	assert_str((_page.rows[3].get_node(^"H/Name") as Label).text).is_equal("Zinga's den")
	# The full one: disabled, dim, "The lobby is full." in place of the players and the ping.
	var full := _page.rows[1]
	assert_bool(full.disabled).is_true()
	assert_str((full.get_node(^"H/Name") as Label).theme_type_variation).is_equal(
		"ToyPresetCardNote"
	)
	assert_bool((full.get_node(^"H/Full") as Control).visible).is_true()
	assert_bool((full.get_node(^"H/Count") as Control).visible).is_false()
	assert_int(_page.chosen()).is_equal(2)
	assert_bool(_page.rows[2].button_pressed).is_true()
	assert_str(_page.rows[2].get_node(^"H/Ping").get(&"theme_type_variation")).is_equal(
		"ToyPresetCardNoteSelected"
	)
	# Ukrainian: the default name and the unit follow the language.
	TranslationServer.set_locale(Languages.UKRAINIAN)
	_page.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str((row.get_node(^"H/Name") as Label).text).is_equal("Лобі: Host2")
	assert_str((row.get_node(^"H/Ping") as Label).text).is_equal("24 мс")


func test_join_takes_the_chosen_lobbys_code_or_its_address() -> void:
	var list: Array[LobbyFinder.Found] = [_found(4, 2, 5), _found(5, 2, 7, "K7Q2XR")]
	_page.show_lobbies(list)
	_page.join_chosen()
	assert_array(_joins).contains_exactly([["192.168.1.4", 24600]])
	_page.rows[5].pressed.emit()
	assert_int(_page.chosen()).is_equal(5)
	_page.nearby_join.pressed.emit()
	assert_array(_codes).contains_exactly(["K7Q2XR"])
	# A full row cannot be chosen.
	var full: Array[LobbyFinder.Found] = [_found(4, 2, 5), _found(6, 10, 3)]
	_page.show_lobbies(full)
	_page.rows[6].pressed.emit()
	assert_int(_page.chosen()).is_equal(4)


func test_a_lobby_gone_leaves_its_row_and_none_shows_the_quiet_line() -> void:
	var two: Array[LobbyFinder.Found] = [_found(7, 2, 5), _found(8, 2, 6)]
	_page.show_lobbies(two)
	_page.rows[8].pressed.emit()
	var one: Array[LobbyFinder.Found] = [_found(7, 2, 5)]
	_page.show_lobbies(one)
	assert_bool(_page.rows.has(8)).is_false()
	# The chosen one went: the first with room is chosen again.
	assert_int(_page.chosen()).is_equal(7)
	var none: Array[LobbyFinder.Found] = []
	_page.show_lobbies(none)
	assert_bool(_page.none_label.visible).is_true()
	assert_bool(_page.lobby_scroll.visible).is_false()
	assert_bool(_page.nearby_join.visible).is_false()
	assert_int(_page.chosen()).is_equal(-1)
	_page.join_chosen()
	assert_array(_joins).is_empty()
	assert_array(_codes).is_empty()


## A double click on a row (s05: = Join).
func _double_click(row: Button) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	row.gui_input.emit(click)


func test_a_double_click_joins_its_row_and_on_a_full_one_nothing() -> void:
	var list: Array[LobbyFinder.Found] = [_found(11, 2, 5), _found(12, 10, 6), _found(13, 3, 7)]
	_page.show_lobbies(list)
	assert_int(_page.chosen()).is_equal(11)
	# A full lobby's row still gets the input: it joins nothing, not the one chosen before.
	_double_click(_page.rows[12])
	assert_array(_joins).is_empty()
	assert_int(_page.chosen()).is_equal(11)
	_double_click(_page.rows[13])
	assert_array(_joins).contains_exactly([["192.168.1.13", 24600]])
	assert_int(_page.chosen()).is_equal(13)


func test_a_row_stays_the_same_button_across_refreshes_and_the_list_scrolls_past_five() -> void:
	var list: Array[LobbyFinder.Found] = [_found(21, 2, 5)]
	_page.show_lobbies(list)
	var row := _page.rows[21]
	var again: Array[LobbyFinder.Found] = [_found(21, 3, 9)]
	_page.show_lobbies(again)
	assert_object(_page.rows[21]).is_same(row)
	assert_str((row.get_node(^"H/Count") as Label).text).is_equal("3 / 10")
	var many: Array[LobbyFinder.Found] = []
	for host: int in range(30, 38):
		many.append(_found(host, 1, 5))
	_page.show_lobbies(many)
	var gap := _page.lobby_list.get_theme_constant(&"separation")
	var five := FindPage.ROWS_SHOWN * FindPage.ROW_HEIGHT + (FindPage.ROWS_SHOWN - 1) * gap
	assert_float(_page.lobby_scroll.custom_minimum_size.y).is_equal(five)
	assert_int(_page.rows.size()).is_equal(8)
