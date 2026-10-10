extends GdUnitTestSuite
## The tutorial's screens (client/ui/TutorialScreen, #492; ARCHITECTURE §4.7.50) under the shared
## theme: the UI handoff's s1 node for node (prime-game-ui `ui-0.4.0`
## `docs/handoff/s01-tutorial.md`: names, classes, variations, anchors, offsets, grow directions,
## size flags and minimum sizes) in
## its four states (invite, step, step-keys, step-howto) and lesson 4's title only, over
## content/tutorial/tutorial.tres; the plates taking no mouse or focus; the texts in English and
## Ukrainian, rebuilt on a language change; the keycaps following a rebind (and so the keyboard
## layout, which KeyLabel reads with the binding, key_label_test.gd) and the large-text width;
## nothing outside the screen at large text in Ukrainian; the step under lesson 7's Spectate plate.

const LESSONS := "res://content/tutorial/tutorial.tres"

var _locale := ""


func before_test() -> void:
	# The deck's words: English unless a test switches, whatever the machine's language is.
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	# The InputMap is global: every later suite reads the project's bindings.
	Controls.new().apply()


func test_the_invite_is_the_handoffs_tree_with_start_focused() -> void:
	var screen := await _screen()
	screen.open_invite()
	await get_tree().process_frame
	assert_bool(screen.invite_shown()).is_true()
	assert_bool(screen.step.visible).is_false()
	assert_bool(screen.list.visible).is_false()
	_assert_node(screen.dim, "Dim", "Panel", &"ToyBackdrop")
	assert_float(screen.dim.anchor_right).is_equal(1.0)
	assert_float(screen.dim.anchor_bottom).is_equal(1.0)
	assert_int(screen.dim.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_assert_node(screen.lang, "Lang", "HBoxContainer", &"ToyRowEight")
	_assert_pinned(screen.lang, Control.PRESET_TOP_RIGHT, Vector2(-40, 40))
	assert_int(screen.lang.grow_horizontal).is_equal(Control.GROW_DIRECTION_BEGIN)
	var uk := screen.lang.get_child(0) as Button
	var en := screen.lang.get_child(1) as Button
	assert_str(String(uk.name)).is_equal("Uk")
	assert_str(String(en.name)).is_equal("En")
	assert_str(uk.text).is_equal("lang.uk")
	assert_str(en.text).is_equal("lang.en")
	assert_object(uk.button_group).is_same(en.button_group)
	# English speaks now: its chip is the pressed one, drawn by ToyToggle's selected partner.
	assert_bool(en.button_pressed).is_true()
	assert_bool(uk.button_pressed).is_false()
	assert_str(String(en.theme_type_variation)).is_equal("ToyChipToggleOnDarkSelected")
	assert_str(String(uk.theme_type_variation)).is_equal("ToyChipToggleOnDark")
	# The raised dialog: placement and size on the wrapper.
	var box := screen.box
	assert_str(String(box.face.name)).is_equal("Box")
	assert_str(String(box.face.theme_type_variation)).is_equal("ToyPanelDialog")
	assert_str(String(box.base.theme_type_variation)).is_equal("ToyBasePanel")
	assert_vector(box.custom_minimum_size).is_equal(Vector2(688, 0))
	_assert_pinned(box, Control.PRESET_CENTER, Vector2.ZERO)
	assert_int(box.grow_vertical).is_equal(Control.GROW_DIRECTION_BOTH)
	var column := box.face.get_node("V") as VBoxContainer
	_assert_node(column, "V", "VBoxContainer", &"ToyColumnThirtyTwo")
	_assert_node(column.get_node("Text"), "Text", "VBoxContainer", &"ToyColumnTwelve")
	_assert_node(screen.invite_title, "Title", "Label", &"ToyTitleOnLight")
	assert_str(screen.invite_title.text).is_equal("tutorial.invite.title")
	_assert_node(screen.invite_body, "Body", "Label", &"ToyTextMutedOnLight")
	assert_str(screen.invite_body.text).is_equal("tutorial.invite.body")
	assert_vector(screen.invite_body.custom_minimum_size).is_equal(Vector2(480, 0))
	assert_int(screen.invite_body.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	var buttons := column.get_node("Buttons") as HBoxContainer
	_assert_node(buttons, "Buttons", "HBoxContainer", &"ToyRowSixteen")
	assert_int(buttons.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	_assert_node(screen.start_button, "Start", "Button", &"ToyButtonPrimary")
	assert_str(screen.start_button.text).is_equal("tutorial.invite.start")
	var start_raised := screen.start_button.get_parent() as ToyRaised
	assert_str(String(start_raised.base.theme_type_variation)).is_equal("ToyBasePrimaryOnLight")
	_assert_node(screen.skip_button, "Skip", "Button", &"ToyButtonGhostOnLight")
	assert_str(screen.skip_button.text).is_equal("tutorial.invite.skip")
	# Focus starts on Start; the chips and Skip take focus too.
	assert_object(screen.get_viewport().gui_get_focus_owner()).is_same(screen.start_button)
	for button: Button in [uk, en, screen.skip_button]:
		assert_int(button.focus_mode).is_equal(Control.FOCUS_ALL)
	# The arrows and a gamepad's pad: Skip beside Start, the chips above them.
	var start := screen.start_button
	assert_object(start.find_valid_focus_neighbor(SIDE_RIGHT)).is_same(screen.skip_button)
	assert_object(screen.skip_button.find_valid_focus_neighbor(SIDE_LEFT)).is_same(start)
	assert_bool([uk, en].has(start.find_valid_focus_neighbor(SIDE_TOP))).is_true()
	assert_bool([uk, en].has(screen.skip_button.find_valid_focus_neighbor(SIDE_TOP))).is_true()
	assert_object(en.find_valid_focus_neighbor(SIDE_LEFT)).is_same(uk)
	# Skip and Esc (GameUi's overlay calls skip()) say the same; Start its own.
	var heard: Array[String] = []
	screen.skip_pressed.connect(func() -> void: heard.append("skip"))
	screen.start_pressed.connect(func() -> void: heard.append("start"))
	screen.language_chosen.connect(func(language: String) -> void: heard.append(language))
	screen.skip_button.pressed.emit()
	screen.skip()
	screen.start_button.pressed.emit()
	uk.pressed.emit()
	assert_array(heard).contains_exactly(["skip", "skip", "start", "uk"])
	screen.close_invite()
	assert_bool(screen.invite_shown()).is_false()
	assert_bool(screen.dim.visible or screen.lang.visible).is_false()


func test_step_is_lesson_2s_sentence_with_its_keycap() -> void:
	var screen := await _screen()
	_show(screen, 2, 1, 1)
	await get_tree().process_frame
	assert_bool(screen.step.visible).is_true()
	_assert_node(screen.step, "Step", "PanelContainer", &"ToyPlate")
	_assert_pinned(screen.step, Control.PRESET_CENTER_TOP, Vector2(0, 40))
	assert_int(screen.step.grow_horizontal).is_equal(Control.GROW_DIRECTION_BOTH)
	assert_int(screen.step.grow_vertical).is_equal(Control.GROW_DIRECTION_END)
	assert_vector(screen.step.custom_minimum_size).is_equal(Vector2(912, 0))
	var column := screen.step.get_node("V") as VBoxContainer
	_assert_node(column, "V", "VBoxContainer", &"ToyColumnEight")
	assert_int(column.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	_assert_node(screen.progress_label, "Progress", "Label", &"ToyTextMutedOnDark")
	assert_str(screen.progress_label.text).is_equal("Step 2 of 9")
	assert_int(screen.progress_label.auto_translate_mode).is_equal(
		Node.AUTO_TRANSLATE_MODE_DISABLED
	)
	_assert_node(screen.title_label, "Title", "Label", &"ToyTitleOnDark")
	assert_str(screen.title_label.text).is_equal("tutorial.step.pick_up.title")
	assert_vector(screen.title_label.custom_minimum_size).is_equal(Vector2(600, 0))
	assert_int(screen.title_label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	_assert_node(screen.how, "How", "HBoxContainer", &"ToyRowEight")
	assert_int(screen.how.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	var before := screen.how.get_node("Before") as Label
	_assert_node(before, "Before", "Label", &"ToyTextOnDark")
	assert_str(before.text).is_equal("Aim at the package and press")
	assert_int(before.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	var key := screen.how.get_node("Key") as PanelContainer
	_assert_node(key, "Key", "PanelContainer", &"ToyKeyOnDark")
	assert_vector(key.custom_minimum_size).is_equal(Vector2(36, 0))
	var text := key.get_node("Text") as Label
	_assert_node(text, "Text", "Label", &"ToyKeyText")
	assert_str(text.text).is_equal(KeyLabel.of_action(&"interact"))
	assert_int(text.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_int(text.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_bool((screen.how.get_node("After") as Label).visible).is_false()
	assert_str(screen.how_text()).is_equal("Aim at the package and press E")
	# Its second instruction swaps Title and How within the same step number.
	_show(screen, 2, 2, 1)
	assert_str(screen.progress_label.text).is_equal("Step 2 of 9")
	assert_str(screen.title_label.text).is_equal("tutorial.step.put_down.title")
	assert_str(screen.how_text()).is_equal("Press Q")
	# The list: lesson 1 done with its check, the current one a chip, the rest muted.
	_assert_node(screen.list, "List", "PanelContainer", &"ToyPlate")
	_assert_pinned(screen.list, Control.PRESET_TOP_RIGHT, Vector2(-40, 256))
	assert_int(screen.list.grow_horizontal).is_equal(Control.GROW_DIRECTION_BEGIN)
	assert_vector(screen.list.custom_minimum_size).is_equal(Vector2(440, 0))
	var list_column := screen.list.get_node("V") as VBoxContainer
	_assert_node(list_column, "V", "VBoxContainer", &"ToyColumnSixteen")
	var head := list_column.get_node("Head") as Label
	_assert_node(head, "Head", "Label", &"ToyTextOnDark")
	assert_str(head.text).is_equal("tutorial.list.title")
	_assert_node(screen.rows, "Rows", "VBoxContainer", &"ToyColumnEight")
	var names: Array[String] = []
	for row: Node in screen.rows.get_children():
		names.append(String(row.name))
	assert_array(names).contains_exactly(
		["MoveDone", "PickUpNow", "HandBelt", "Deliver", "Map", "Downed", "Death", "Voice", "Menu"]
	)
	var done := screen.rows.get_node("MoveDone") as HBoxContainer
	_assert_node(done, "MoveDone", "HBoxContainer", &"ToyRowEight")
	var done_name := done.get_node("Name") as Label
	_assert_node(done_name, "Name", "Label", &"ToyTextOnDark")
	assert_str(done_name.text).is_equal("tutorial.list.move")
	assert_int(done_name.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	assert_vector(done_name.custom_minimum_size).is_equal(Vector2(240, 0))
	var check := done.get_node("Check") as TextureRect
	assert_object(check.texture).is_not_null()
	assert_vector(check.custom_minimum_size).is_equal(Vector2(24, 24))
	assert_int(check.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_int(check.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
	assert_int(check.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_object(check.self_modulate).is_equal(
		GameUi.THEME.get_color(&"font_color", &"ToyTextOnDark")
	)
	var now := screen.rows.get_node("PickUpNow") as PanelContainer
	_assert_node(now, "PickUpNow", "PanelContainer", &"ToyChipLight")
	assert_int(now.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	var chip_text := now.get_node("Name") as Label
	_assert_node(chip_text, "Name", "Label", &"ToyChipLightText")
	assert_int(chip_text.autowrap_mode).is_equal(TextServer.AUTOWRAP_OFF)
	var next := screen.rows.get_node("HandBelt") as Label
	_assert_node(next, "HandBelt", "Label", &"ToyTextMutedOnDark")
	assert_vector(next.custom_minimum_size).is_equal(Vector2(240, 0))
	assert_int(next.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	# The map row's {key} is the map key bound now, set from code.
	var map := screen.rows.get_node("Map") as Label
	assert_str(map.text).is_equal("Map and tasks (%s)" % KeyLabel.of_action(&"map"))
	assert_int(map.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	_assert_ignores_mouse(screen.step)
	_assert_ignores_mouse(screen.list)


func test_step_keys_is_lesson_1s_row_of_keycaps() -> void:
	var screen := await _screen()
	_show(screen, 1, 1, 0)
	await get_tree().process_frame
	assert_str(screen.progress_label.text).is_equal("Step 1 of 9")
	assert_str(screen.title_label.text).is_equal("tutorial.step.move.title")
	_assert_node(screen.how, "HowKeys", "HBoxContainer", &"ToyRowTwentyFour")
	assert_int(screen.how.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	var walk := screen.how.get_node("Walk") as HBoxContainer
	_assert_node(walk, "Walk", "HBoxContainer", &"ToyRowEight")
	var keys := walk.get_node("Keys") as HBoxContainer
	_assert_node(keys, "Keys", "HBoxContainer", &"ToyRowFour")
	var names: Array[String] = []
	for key: Node in keys.get_children():
		names.append(String(key.name))
		_assert_node(key, String(key.name), "PanelContainer", &"ToyKeyOnDark")
		assert_vector((key as Control).custom_minimum_size).is_equal(Vector2(36, 0))
	assert_array(names).contains_exactly(["Forward", "Left", "Backward", "Right"])
	var forward := keys.get_node("Forward/Text") as Label
	assert_str(forward.text).is_equal(KeyLabel.of_action(&"move_forward"))
	var walk_label := walk.get_node("Label") as Label
	_assert_node(walk_label, "Label", "Label", &"ToyTextOnDark")
	assert_str(walk_label.text).is_equal("control.walk")
	assert_int(walk_label.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_object(walk.get_child(0)).is_same(keys)
	for group: String in ["Sprint", "Jump"]:
		var row := screen.how.get_node(group) as HBoxContainer
		_assert_node(row, group, "HBoxContainer", &"ToyRowEight")
		var key := row.get_node("Key") as PanelContainer
		# Shift and Space take the wide size.
		assert_vector(key.custom_minimum_size).is_equal(Vector2(96, 0))
		assert_str((row.get_node("Label") as Label).text).is_equal("control." + group.to_lower())
	assert_str((screen.how.get_node("Jump/Key/Text") as Label).text).is_equal("Space")
	(
		assert_str(screen.how_text())
		. is_equal(
			(
				"%s %s %s %s Walk %s Sprint Space Jump"
				% [
					KeyLabel.of_action(&"move_forward"),
					KeyLabel.of_action(&"move_left"),
					KeyLabel.of_action(&"move_back"),
					KeyLabel.of_action(&"move_right"),
					KeyLabel.of_action(&"sprint"),
				]
			)
		)
	)
	var first := screen.rows.get_child(0) as PanelContainer
	assert_str(String(first.name)).is_equal("MoveNow")
	assert_str(String(screen.rows.get_child(1).name)).is_equal("PickUp")
	_assert_ignores_mouse(screen.step)


func test_step_howto_is_lesson_5s_round_keycap_and_lesson_4_has_a_title_only() -> void:
	var screen := await _screen()
	_show(screen, 5, 2, 4)
	await get_tree().process_frame
	assert_str(screen.progress_label.text).is_equal("Step 5 of 9")
	assert_str(screen.title_label.text).is_equal("tutorial.step.howto.title")
	var key := screen.how.get_node("Key") as PanelContainer
	_assert_node(key, "Key", "PanelContainer", &"ToyKeyRound")
	assert_vector(key.custom_minimum_size).is_equal(Vector2(36, 0))
	assert_str((key.get_node("Text") as Label).text).is_equal("?")
	assert_str((screen.how.get_node("After") as Label).text).is_equal("next to a task")
	assert_str(screen.how_text()).is_equal("Press ? next to a task")
	var names: Array[String] = []
	for row: Node in screen.rows.get_children():
		names.append(String(row.name))
	(
		assert_array(names)
		. contains_exactly(
			[
				"MoveDone",
				"PickUpDone",
				"HandBeltDone",
				"DeliverDone",
				"MapNow",
				"Downed",
				"Death",
				"Voice",
				"Menu",
			]
		)
	)
	# Lesson 4 (the engineer's answer on PR #722): the title only.
	_show(screen, 4, 1, 3)
	assert_str(screen.title_label.text).is_equal("tutorial.step.deliver.title")
	assert_bool(screen.how.visible).is_false()
	assert_str(screen.how_text()).is_empty()
	# Lesson 9's Esc is a wide keycap.
	_show(screen, 9, 1, 8)
	await get_tree().process_frame
	assert_vector(screen.keycaps()[0].custom_minimum_size).is_equal(Vector2(96, 0))
	# None current (lesson 8 waiting for the respawn): no step, the list stays.
	_show(screen, 0, 0, 7)
	assert_bool(screen.step.visible).is_false()
	assert_bool(screen.list.visible).is_true()


func test_the_keycaps_follow_a_rebind_and_the_list_its_map_key() -> void:
	var screen := await _screen()
	_show(screen, 2, 1, 1)
	_bind({&"interact": KEY_F, &"map": KEY_K})
	# The same lesson, step and done set: the new labels alone redraw it (the game calls it every
	# frame).
	_show(screen, 2, 1, 1)
	await get_tree().process_frame
	assert_str(screen.how_text()).is_equal("Aim at the package and press F")
	assert_str((screen.rows.get_node("Map") as Label).text).is_equal("Map and tasks (K)")
	_bind({&"interact": KEY_SPACE})
	_show(screen, 2, 1, 1)
	await get_tree().process_frame
	assert_str(screen.how_text()).is_equal("Aim at the package and press Space")
	assert_vector(screen.keycaps()[0].custom_minimum_size).is_equal(Vector2(96, 0))


func test_texts_rebuild_in_ukrainian_and_large_text_keeps_every_plate_on_screen() -> void:
	var screen := await _screen()
	var holder := screen.get_parent() as Control
	_show(screen, 2, 1, 1)
	TranslationServer.set_locale("uk")
	screen.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(screen.progress_label.text).is_equal("Крок 2 з 9")
	assert_str(screen.how_text()).is_equal("Наведи приціл на пакунок і натисни E")
	holder.theme = GameUi.THEME_LARGE
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(screen.keycaps()[0].custom_minimum_size).is_equal(Vector2(42, 0))
	# Every lesson and step at large text in Ukrainian: inside the screen, the two plates apart.
	for lesson in range(1, 10):
		var steps := (load(LESSONS) as TutorialLessons).lessons[lesson - 1].steps.size()
		for number in range(1, steps + 1):
			_show(screen, lesson, number, lesson - 1)
			await get_tree().process_frame
			await get_tree().process_frame
			var screen_rect := Rect2(Vector2.ZERO, holder.size)
			for plate: Control in [screen.step, screen.list]:
				(
					assert_bool(screen_rect.encloses(plate.get_global_rect()))
					. override_failure_message(
						"lesson %d.%d: %s off the screen" % [lesson, number, plate.name]
					)
					. is_true()
				)
			var apart := not screen.step.get_global_rect().intersects(screen.list.get_global_rect())
			assert_bool(apart).override_failure_message("lesson %d.%d" % [lesson, number]).is_true()
	screen.open_invite()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(Rect2(Vector2.ZERO, holder.size).encloses(screen.box.get_global_rect())).is_true()
	assert_bool(screen.lang.get_global_rect().intersects(screen.box.get_global_rect())).is_false()
	# The chip follows the language spoken.
	assert_bool(screen.chips[Languages.UKRAINIAN].button_pressed).is_true()
	assert_bool(screen.chips[Languages.ENGLISH].button_pressed).is_false()


func test_the_step_goes_under_the_spectate_plate() -> void:
	var screen := await _screen()
	_show(screen, 7, 1, 6)
	var spectate := Control.new()
	spectate.position = Vector2(0, 40)
	spectate.size = Vector2(300, 90)
	screen.add_child(spectate)
	screen.set_step_under(spectate)
	assert_float(screen.step.offset_top).is_equal(154.0)
	screen.set_step_under(null)
	assert_float(screen.step.offset_top).is_equal(40.0)


func _show(screen: TutorialScreen, lesson: int, step: int, done_count: int) -> void:
	var done: Array[bool] = []
	for i in 9:
		done.append(i < done_count)
	screen.show_lessons(load(LESSONS) as TutorialLessons, lesson, step, done)


func _bind(keys: Dictionary[StringName, Key]) -> void:
	var controls := Controls.new()
	for action: StringName in keys:
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		controls.bind(action, key)
	controls.apply()


func _assert_node(node: Node, node_name: String, type: String, variation: StringName) -> void:
	assert_str(String(node.name)).is_equal(node_name)
	assert_str(node.get_class()).is_equal(type)
	assert_str(String((node as Control).theme_type_variation)).is_equal(String(variation))


## Anchored at `preset` with all four offsets at `at`.
func _assert_pinned(node: Control, preset: Control.LayoutPreset, at: Vector2) -> void:
	var probe := Control.new()
	probe.set_anchors_preset(preset)
	assert_float(node.anchor_left).is_equal(probe.anchor_left)
	assert_float(node.anchor_top).is_equal(probe.anchor_top)
	assert_float(node.anchor_right).is_equal(probe.anchor_right)
	assert_float(node.anchor_bottom).is_equal(probe.anchor_bottom)
	probe.free()
	assert_float(node.offset_left).is_equal(at.x)
	assert_float(node.offset_right).is_equal(at.x)
	assert_float(node.offset_top).is_equal(at.y)
	assert_float(node.offset_bottom).is_equal(at.y)


func _assert_ignores_mouse(root: Control) -> void:
	assert_int(root.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	for node: Node in root.find_children("*", "Control", true, false):
		var control := node as Control
		assert_int(control.mouse_filter).override_failure_message(str(control.get_path())).is_equal(
			Control.MOUSE_FILTER_IGNORE
		)
		assert_int(control.focus_mode).is_equal(Control.FOCUS_NONE)


func _screen() -> TutorialScreen:
	var holder: Control = auto_free(Control.new())
	holder.theme = GameUi.THEME
	holder.size = Vector2(1920, 1080)
	add_child(holder)
	var screen := TutorialScreen.new()
	holder.add_child(screen)
	await get_tree().process_frame
	return screen
