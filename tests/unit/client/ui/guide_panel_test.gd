extends GdUnitTestSuite
## The Esc menu's Guide (GuidePanel, #254; prime-game-ui's s5 `guide` at ui-0.4.0): the basics and
## every task type of the mode with its card, one chip each in one ButtonGroup, the selected chip's
## card on the right with 160x120 art and the chip's title, in both languages; and the Esc menu's
## Guide tab shows it in every screen.

const MODE := "res://content/modes/base_mode.tres"
const Preview := preload("res://client/dev/screen_preview.gd")

const S := GameFlow.Screen

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func after_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


func test_the_list_holds_the_basics_then_every_task_type() -> void:
	var guide := _guide()
	assert_str(guide.name).is_equal("Guide")
	assert_str(String(guide.theme_type_variation)).is_equal("ToyRowTwentyFour")
	assert_int(guide.size_flags_vertical).is_equal(Control.SIZE_EXPAND_FILL)
	assert_str(String(guide.list.theme_type_variation)).is_equal("ToyScroll")
	assert_that(guide.list.custom_minimum_size).is_equal(Vector2(332, 0))
	assert_bool(guide.list.follow_focus).is_true()
	assert_int(guide.list.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	var rows: Array[String] = []
	for child: Node in guide.column.get_children():
		if child is Label:
			rows.append("%s %s" % [child.name, (child as Label).text])
		elif child is Button:
			rows.append("%s %s" % [child.name, (child as Button).text])
		else:
			rows.append(String(child.name))
	assert_array(rows).is_equal(
		[
			"Basics guide.basics",
			"Moving guide.moving",
			"Voice guide.voice",
			"Downed guide.downed",
			"Gap",
			"Tasks guide.tasks",
			"Delivery task.delivery",
		]
	)
	for id: StringName in guide.chips:
		var chip := guide.chips[id]
		assert_object(chip.button_group).is_same(guide.group)
		assert_bool(chip.toggle_mode).is_true()
		assert_int(chip.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	assert_that(
		(guide.column.get_node(^"Gap") as Control).custom_minimum_size
	).is_equal(Vector2(0, 8))
	await get_tree().process_frame


func test_delivery_is_selected_first_and_a_chip_shows_its_card() -> void:
	var guide := _guide()
	assert_str(String(guide.selected)).is_equal("delivery")
	assert_bool(guide.chips[&"delivery"].button_pressed).is_true()
	assert_str(String(guide.chips[&"delivery"].theme_type_variation)).is_equal(
		"ToyChipToggleOnLightSelected"
	)
	var face := HowtoCardView.face_of(guide.card)
	assert_str(face.title_label.text).is_equal("task.delivery")
	assert_object(face.close_button).is_null()
	assert_that(
		(face.frames_box.get_child(0).get_child(0) as Control).custom_minimum_size
	).is_equal(HowtoCardView.GUIDE_ART)
	assert_int(guide.card.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	assert_int(guide.card.size_flags_vertical).is_equal(Control.SIZE_SHRINK_BEGIN)
	assert_object(guide.card.get_parent()).is_same(guide)
	guide.chips[&"downed"].button_pressed = true
	guide.chips[&"downed"].pressed.emit()
	assert_str(String(guide.selected)).is_equal("downed")
	assert_bool(guide.chips[&"delivery"].button_pressed).is_false()
	face = HowtoCardView.face_of(guide.card)
	assert_str(face.title_label.text).is_equal("guide.downed")
	assert_int(face.frames_box.get_child_count()).is_equal(4)
	await get_tree().process_frame


func test_the_words_are_in_both_languages() -> void:
	var guide := _guide()
	guide.select(&"moving")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	guide.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	var face := HowtoCardView.face_of(guide.card)
	assert_str(face.title_label.atr(face.title_label.text)).is_equal("Рух і руки")
	assert_str((face.get_node(^"V/Frames/Frame1/Words") as Label).text).is_equal(
		"Походи кімнатою"
	)
	var tasks := guide.column.get_node(^"Tasks") as Label
	assert_str(tasks.atr(tasks.text)).is_equal("Задачі")
	await get_tree().process_frame


func test_no_mode_lists_the_basics_only() -> void:
	var guide: GuidePanel = auto_free(GuidePanel.new())
	assert_array(guide.chips.keys()).is_equal([&"moving", &"voice", &"downed"])
	assert_bool(guide.tasks_label.visible).is_false()
	assert_str(String(guide.selected)).is_equal("moving")


func test_the_esc_menus_guide_tab_shows_it() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	ui.esc.guide.set_mode(_mode)
	for screen: S in [S.LOBBY, S.ROUND]:
		ui.show_screen(screen)
		ui.open_esc(false, Preview.fake_model(_mode, false))
		var tab := ui.esc.tab_buttons[EscMenuState.Tab.GUIDE]
		assert_bool(tab.visible).is_true()
		assert_str(tab.text).is_equal("esc.tab.guide")
		ui.esc.press(EscMenuState.Tab.GUIDE)
		assert_object(ui.esc.page()).is_same(ui.esc.guide)
		assert_bool(ui.esc.guide.is_visible_in_tree()).is_true()
		ui.close_esc()
	await get_tree().process_frame


func _guide() -> GuidePanel:
	var guide: GuidePanel = auto_free(GuidePanel.new())
	guide.theme = GameUi.THEME
	add_child(guide)
	guide.set_mode(_mode)
	return guide
