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
		["Nearby/None", "Label", &"ToyTextMutedOnLight", Vector2.ZERO],
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
