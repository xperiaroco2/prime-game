extends GdUnitTestSuite
## The ship's match console's screen (#1604; prime-game-ui `ui-2.5.4` s04 `console-host` and
## `console-guest`): the handoff's tree, the host's steppers and chips against everyone else's
## values and plates, the rows MatchRows shows, the code at the foot. How it looks: the `shot`s of
## client/dev/console_*_preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const HOUSE := "res://levels/house/house.tscn"

var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func _screen(mode: GameMode) -> ConsoleScreen:
	var screen: ConsoleScreen = auto_free(ConsoleScreen.new())
	screen.theme = GameUi.THEME
	add_child(screen)
	screen.set_mode(mode)
	return screen


func test_the_tree_is_the_handoffs() -> void:
	var screen := _screen(load(MODE) as GameMode)
	assert_str(screen.name).is_equal("Console")
	assert_str(screen.theme_type_variation).is_equal("ToyPanelDialog")
	assert_vector(screen.custom_minimum_size).is_equal(ConsoleScreen.SIZE)
	var parts := {
		"V": "ToyColumnSixteen",
		"V/Top": "ToyRowSixteen",
		"V/Top/Title": "ToyTitleMachine",
		"V/Top/HostNote": "ToyTextMutedOnLight",
		"V/Top/HostOnly": "ToyRowTwelve",
		"V/Top/HostOnly/Text": "ToyTextMutedOnLight",
		"V/Rows": "ToyColumnFour",
		"V/Code": "ToyRowTwelve",
		"V/Code/Label": "ToyTextMutedOnLight",
		"V/Code/Value": "ToyTextOnLight",
	}
	for path: String in parts:
		var part := screen.get_node(path) as Control
		assert_str(part.theme_type_variation).override_failure_message(path).is_equal(parts[path])
	assert_str((screen.get_node(^"V/Top/Title") as Label).text).is_equal("console.title")
	var row := screen.row_of(&"match_duration")
	assert_str(row.theme_type_variation).is_equal("ToySettingRow")
	assert_float(row.custom_minimum_size.y).is_equal(ConsoleScreen.ROW_HEIGHT)
	assert_str((row.get_node(^"H") as Control).theme_type_variation).is_equal("ToyRowSixteen")
	var stepper := screen.stepper_of(&"match_duration")
	assert_object(stepper.less.icon).is_same(ConsoleScreen.LESS_ICON)
	assert_object(stepper.more.icon).is_same(ConsoleScreen.MORE_ICON)
	assert_vector(stepper.value_label.custom_minimum_size).is_equal(ConsoleScreen.VALUE_WIDTH)
	var arrow := Vector2(
		screen.get_theme_constant(&"width", &"ToyStepper"),
		screen.get_theme_constant(&"height", &"ToyStepper")
	)
	assert_vector(stepper.less.custom_minimum_size).is_equal(arrow)


func test_the_host_changes_the_settings_and_everyone_else_reads_them() -> void:
	var mode := load(MODE) as GameMode
	var screen := _screen(mode)
	var sent: Array = []
	screen.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	var model := Preview.fake_model(mode, true)
	screen.refresh(model, true, true, true)
	assert_bool(screen.host_note.visible).is_true()
	assert_bool(screen.host_only.visible).is_false()
	var duration := screen.stepper_of(&"match_duration")
	assert_bool(duration.more.visible).is_true()
	var before := duration.value
	duration.more.pressed.emit()
	assert_array(sent).contains_exactly([[&"match_duration", before + 1]])
	var chips := screen.get_node(^"V/Rows/Tasks/H/Allowed") as Control
	assert_bool(chips.visible).is_true()
	# Everyone else: the values, the plates and the lock line naming the host; nothing sent.
	sent.clear()
	var guest := Preview.fake_model(mode, false)
	screen.refresh(guest, false, false, true)
	assert_bool(screen.host_note.visible).is_false()
	assert_bool(screen.host_only.visible).is_true()
	assert_str(screen.host_only_text.text).is_equal(
		"Only the host changes these · %s" % guest.host_name()
	)
	assert_bool(duration.more.visible).is_false()
	assert_bool(duration.less.visible).is_false()
	assert_bool(chips.visible).is_false()
	assert_bool((screen.get_node(^"V/Rows/Tasks/H/Shown") as Control).visible).is_true()
	duration.more.pressed.emit()
	assert_array(sent).is_empty()


func test_the_own_ship_names_no_host() -> void:
	# The own ship (#1285) is shared with nobody: the values alone, no lock line, no host note.
	var mode := load(MODE) as GameMode
	var screen := _screen(mode)
	screen.refresh(Preview.fake_model(mode, true), false, true, false)
	assert_bool(screen.host_only.visible).is_false()
	assert_bool(screen.host_note.visible).is_false()
	assert_bool(screen.stepper_of(&"match_duration").more.visible).is_false()


func test_the_estate_shows_m8s_rows_alone_and_the_house_more() -> void:
	# The same rows as the Esc menu's Lobby page since #1601 (MatchRows): on the Estate the match
	# duration, the ship's engine chip and the dissidents; on the House bench the other tasks too.
	var mode := load(MODE) as GameMode
	var screen := _screen(mode)
	var model := Preview.fake_model(mode, true)
	screen.refresh(model, true, true, true)
	assert_str(HowtoCards.shown_map(mode, model.map)).is_equal(mode.default_map())
	var shown: Array[String] = []
	for row: Node in screen.rows.get_children():
		if (row as Control).visible:
			shown.append(String(row.name))
	assert_array(shown).contains_exactly(["Duration", "Tasks", "Dissidents"])
	var chips: Array[String] = []
	for chip: Node in screen.get_node(^"V/Rows/Tasks/H/Allowed").get_children():
		if (chip as Control).visible:
			chips.append(String(chip.name))
	assert_array(chips).contains_exactly(["Engine"])
	model.map = HOUSE
	screen.refresh(model, true, true, true)
	for row: String in ["Packages", "Switches", "Photos", "Burgers", "CarParts", "TaskCount"]:
		var node := screen.rows.get_node(row) as Control
		assert_bool(node.visible).override_failure_message(row).is_true()


func test_a_chip_sends_the_types_left_unselected() -> void:
	var mode := load(MODE) as GameMode
	var screen := _screen(mode)
	var sent: Array = []
	screen.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	screen.refresh(Preview.fake_model(mode, true), true, true, true)
	var chip := screen.get_node(^"V/Rows/Tasks/H/Allowed/Engine") as Button
	chip.set_pressed_no_signal(false)
	chip.pressed.emit()
	assert_int(sent.size()).is_equal(1)
	assert_str(str(sent[0][0])).is_equal("banned_task_types")
	assert_bool((sent[0][1] as PackedStringArray).has("engine")).is_true()


func test_a_task_types_own_row_reads_the_players_language() -> void:
	var mode := load(MODE) as GameMode
	var screen := _screen(mode)
	var label := screen.row_of(&"switches").get_node(^"H/Name") as Label
	assert_str(label.text).is_equal("Switches: step count")
	TranslationServer.set_locale("uk")
	screen.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(label.text).is_equal("Рубильники: кількість кроків")


func test_the_code_at_the_foot() -> void:
	var screen := _screen(load(MODE) as GameMode)
	screen.show_code(JoinProgress.code_text("K7Q2XR", false, true), "K7Q2XR")
	assert_bool(screen.code_row.visible).is_true()
	assert_str(screen.code_label.text).is_equal("K7Q2XR")
	screen.show_code(JoinProgress.code_text("", false, true), "")
	assert_bool(screen.code_row.visible).is_true()
	assert_str(screen.code_label.text).is_equal(EscMenu.CODE_WAITING)
	screen.show_code(JoinProgress.code_text("", true, true), "")
	assert_bool(screen.code_row.visible).is_false()
	assert_bool(screen.code_gone.visible).is_true()
	# A Direct session has no code: neither shows.
	screen.show_code("", "")
	assert_bool(screen.code_row.visible).is_false()
	assert_bool(screen.code_gone.visible).is_false()


func test_the_host_in_the_countdown_reads_the_values_under_its_own_note() -> void:
	# The countdown takes no ChangeSettings: the host's arrows go, its note stays and no lock line
	# names the host to itself.
	var mode := load(MODE) as GameMode
	var screen := _screen(mode)
	screen.refresh(Preview.fake_model(mode, true), false, true, true)
	assert_bool(screen.host_note.visible).is_true()
	assert_bool(screen.host_only.visible).is_false()
	assert_bool(screen.stepper_of(&"match_duration").more.visible).is_false()
