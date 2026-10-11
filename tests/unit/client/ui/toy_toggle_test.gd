extends GdUnitTestSuite
## ToyToggle (#289): a toggle swaps to the pack's selected partner while on and back while off,
## for every pair; in a ButtonGroup the one let go swaps back; a variation with no partner keeps
## its own pressed look; a content label swaps with the card; sync() after set_pressed_no_signal;
## a button already on when attached.

const PAIRS: Dictionary[StringName, String] = {
	&"ToyChipToggleOnDark": "ToyChipToggleOnDarkSelected",
	&"ToyChipToggleOnLight": "ToyChipToggleOnLightSelected",
	&"ToyPresetCard": "ToyPresetCardSelected",
	&"ToyRadio": "ToyRadioSelected",
	&"ToyTab": "ToyTabSelected",
}

var _stage: Control


func before_test() -> void:
	_stage = auto_free(Control.new())
	_stage.theme = GameUi.THEME
	add_child(_stage)


func test_every_pair_swaps_on_and_back() -> void:
	for idle: StringName in PAIRS:
		var button := _toggle(idle)
		button.button_pressed = true
		assert_str(str(button.theme_type_variation)).is_equal(PAIRS[idle])
		button.button_pressed = false
		assert_str(str(button.theme_type_variation)).is_equal(str(idle))


func test_the_handler_swaps_when_called_directly() -> void:
	var button := _toggle(&"ToyTab")
	var toggle := button.get_node(^"ToyToggle") as ToyToggle
	toggle.on_toggled(true)
	assert_str(str(button.theme_type_variation)).is_equal("ToyTabSelected")
	toggle.on_toggled(false)
	assert_str(str(button.theme_type_variation)).is_equal("ToyTab")


func test_a_group_swaps_the_one_let_go_back() -> void:
	var group := ButtonGroup.new()
	var first := _toggle(&"ToyChipToggleOnLight")
	var second := _toggle(&"ToyChipToggleOnLight")
	first.button_group = group
	second.button_group = group
	first.button_pressed = true
	assert_str(str(first.theme_type_variation)).is_equal("ToyChipToggleOnLightSelected")
	second.button_pressed = true
	assert_bool(first.button_pressed).is_false()
	assert_str(str(first.theme_type_variation)).is_equal("ToyChipToggleOnLight")
	assert_str(str(second.theme_type_variation)).is_equal("ToyChipToggleOnLightSelected")


func test_a_variation_without_a_partner_keeps_its_own_look() -> void:
	for idle: StringName in [&"ToyMenuItem", &"ToyKeyButton", &"EscTab"]:
		var button := _toggle(idle)
		button.button_pressed = true
		assert_str(str(button.theme_type_variation)).is_equal(str(idle))


func test_a_card_note_swaps_with_its_card() -> void:
	var raised := UiParts.button("", Callable(), &"ToyPresetCard", ToyHints.LIGHT)
	_stage.add_child(raised)
	var card := raised.face as Button
	card.toggle_mode = true
	var note := UiParts.styled_label("8 players", &"ToyPresetCardNote")
	card.add_child(note)
	var toggle := card.get_node(^"ToyToggle") as ToyToggle
	toggle.companion(note, &"ToyPresetCardNote", &"ToyPresetCardNoteSelected")
	card.button_pressed = true
	assert_str(str(note.theme_type_variation)).is_equal("ToyPresetCardNoteSelected")
	card.button_pressed = false
	assert_str(str(note.theme_type_variation)).is_equal("ToyPresetCardNote")


func test_sync_follows_a_silent_press_and_an_early_one() -> void:
	var button := _toggle(&"ToyRadio")
	button.set_pressed_no_signal(true)
	assert_str(str(button.theme_type_variation)).is_equal("ToyRadio")
	(button.get_node(^"ToyToggle") as ToyToggle).sync()
	assert_str(str(button.theme_type_variation)).is_equal("ToyRadioSelected")
	var early: Button = auto_free(Button.new())
	early.theme_type_variation = &"ToyTab"
	early.toggle_mode = true
	early.button_pressed = true
	ToyToggle.attach(early)
	assert_str(str(early.theme_type_variation)).is_equal("ToyTabSelected")


func _toggle(variation: StringName) -> Button:
	var button := UiParts.toggle("Pick", Callable(), variation)
	_stage.add_child(button)
	return button
