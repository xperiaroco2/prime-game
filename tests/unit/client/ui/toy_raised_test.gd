extends GdUnitTestSuite
## ToyRaised and ToyHints (#289): the base Panel first and ignoring the mouse, then the face; the
## base's variation from the generated theme's hints for the screen's context; panels and the
## title plate raised with no press; the base following a later variation; the wrapper taking the
## face's minimum size.

var _stage: Control


func before_test() -> void:
	_stage = auto_free(Control.new())
	_stage.theme = GameUi.THEME
	add_child(_stage)


func test_the_base_comes_first_and_ignores_the_mouse() -> void:
	var raised := UiParts.button("Go")
	_stage.add_child(raised)
	assert_object(raised.get_child(0)).is_same(raised.base)
	assert_object(raised.get_child(1)).is_same(raised.face)
	assert_int(raised.get_child_count()).is_equal(2)
	assert_int(raised.base.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(raised.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_str((raised.face as Button).text).is_equal("Go")


func test_the_base_follows_the_hints_and_the_context() -> void:
	var cases: Array[Array] = [
		[&"ToyButtonSecondary", ToyHints.DARK, "ToyBaseRaisedOnDark"],
		[&"ToyButtonSecondary", ToyHints.LIGHT, "ToyBaseRaisedOnLight"],
		[&"ToyButtonDanger", ToyHints.LIGHT, "ToyBaseRaisedOnLight"],
		[&"ToyButtonPrimary", ToyHints.DARK, "ToyBasePrimaryOnDark"],
		[&"ToyPresetCard", ToyHints.DARK, "ToyBaseCard"],
		[&"ToyPresetCardSelected", ToyHints.LIGHT, "ToyBaseCard"],
		[&"ToyButtonGhostOnDark", ToyHints.DARK, ""],
		[&"EscTab", ToyHints.DARK, ""],
	]
	for each in cases:
		var variation: StringName = each[0]
		var context: StringName = each[1]
		var raised := UiParts.button("Go", Callable(), variation, context)
		_stage.add_child(raised)
		var want: String = each[2]
		(
			assert_str(str(raised.base.theme_type_variation))
			. override_failure_message("%s on %s" % [each[0], each[1]])
			. is_equal(want)
		)
		assert_bool(raised.base.visible).is_equal(not want.is_empty())


func test_panels_and_the_title_plate_are_raised_without_a_press() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToyPanelMenu"
	var raised_panel := UiParts.raised(panel)
	_stage.add_child(raised_panel)
	assert_str(str(raised_panel.base.theme_type_variation)).is_equal("ToyBasePanel")
	assert_bool(raised_panel.base.visible).is_true()
	assert_int(panel.get_child_count(true)).is_equal(0)
	var plate := UiParts.styled_label("Engineer", &"ToyTitlePlate")
	var raised_plate := UiParts.raised(plate, ToyHints.LIGHT)
	_stage.add_child(raised_plate)
	assert_str(str(raised_plate.base.theme_type_variation)).is_equal("ToyBaseTitle")


func test_the_base_follows_a_later_variation() -> void:
	var raised := UiParts.button("Go", Callable(), &"ToyButtonGhostOnDark")
	_stage.add_child(raised)
	assert_bool(raised.base.visible).is_false()
	raised.face.theme_type_variation = &"ToyButtonPrimary"
	assert_str(str(raised.base.theme_type_variation)).is_equal("ToyBasePrimaryOnDark")
	assert_bool(raised.base.visible).is_true()


func test_the_wrapper_takes_the_faces_minimum_size() -> void:
	var raised := UiParts.button("A longer label than the width")
	_stage.add_child(raised)
	await get_tree().process_frame
	var face_min := raised.face.get_combined_minimum_size()
	var wrapper_min := raised.get_combined_minimum_size()
	assert_float(wrapper_min.y).is_equal(face_min.y)
	assert_float(wrapper_min.x).is_equal(maxf(face_min.x, UiParts.BUTTON_SIZE.x))
	assert_that(raised.base.size).is_equal(raised.face.size)


func test_the_hints_name_toggle_partners() -> void:
	assert_str(str(ToyHints.selected_for(&"ToyTab"))).is_equal("ToyTabSelected")
	assert_str(str(ToyHints.selected_for(&"ToyRadio"))).is_equal("ToyRadioSelected")
	assert_str(str(ToyHints.selected_for(&"ToyMenuItem"))).is_empty()
	assert_str(str(ToyHints.selected_for(&"ToyKeyButton"))).is_empty()
	assert_str(str(ToyHints.selected_for(&"EscTab"))).is_empty()
	assert_str(str(ToyHints.base_for(&"ToyMapBoard", ToyHints.LIGHT))).is_equal("ToyBasePanel")
