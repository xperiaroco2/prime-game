extends GdUnitTestSuite
## The tutorial's screens (client/ui/TutorialScreen, #492; ARCHITECTURE §4.7.49) under the shared
## theme: the UI handoff's s1 node for node (prime-game-ui `ui-2.5.4`
## `docs/handoff/s01-tutorial.md`: names, classes, variations, anchors, offsets, grow directions,
## size flags and minimum sizes) in its states over content/tutorial/tutorial.tres (invite, step,
## step-keys), and the «?» round keycap (step-howto) and a title-only step on steps the test
## builds, since no lesson shows them (#900); the plates taking no mouse or focus; the texts in
## English and Ukrainian, rebuilt on a language change; the keycaps following a rebind (and so the
## keyboard layout, which KeyLabel reads with the binding, key_label_test.gd) and the large-text
## width; nothing outside the screen at large text in Ukrainian; the step under lesson 7's
## DeadTop tile.

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
	# s1 at ui-2.5.4 (#1572): a quiet tile, no language chips (the language only in Settings).
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
	assert_object(screen.get_node_or_null(^"Lang")).is_null()
	var box := screen.box
	_assert_node(box, "Box", "PanelContainer", &"ToyPanelDialog")
	assert_vector(box.custom_minimum_size).is_equal(Vector2(960, 0))
	_assert_pinned(box, Control.PRESET_CENTER, Vector2.ZERO)
	assert_int(box.grow_vertical).is_equal(Control.GROW_DIRECTION_BOTH)
	var column := box.get_node("V") as VBoxContainer
	_assert_node(column, "V", "VBoxContainer", &"ToyColumnThirtyTwo")
	var text := column.get_node("Text") as VBoxContainer
	_assert_node(text, "Text", "VBoxContainer", &"ToyColumnTwelve")
	var head := text.get_node("Head") as Label
	_assert_node(head, "Head", "Label", &"ToyKicker")
	assert_str(head.text).is_equal("tutorial.list.title")
	assert_bool(head.uppercase).is_true()
	_assert_node(screen.invite_title, "Title", "Label", &"ToyTitleOnLight")
	assert_str(screen.invite_title.text).is_equal("tutorial.invite.title")
	_assert_node(screen.invite_body, "Body", "Label", &"ToyTextMutedOnLight")
	assert_str(screen.invite_body.text).is_equal("tutorial.invite.body")
	assert_vector(screen.invite_body.custom_minimum_size).is_equal(Vector2(876, 0))
	assert_int(screen.invite_body.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	var buttons := column.get_node("Buttons") as HBoxContainer
	_assert_node(buttons, "Buttons", "HBoxContainer", &"ToyRowSixteen")
	# The two buttons at the left.
	assert_int(buttons.alignment).is_equal(BoxContainer.ALIGNMENT_BEGIN)
	_assert_node(screen.start_button, "Start", "Button", &"ToyButtonPrimary")
	assert_str(screen.start_button.text).is_equal("tutorial.invite.start")
	_assert_node(screen.skip_button, "Skip", "Button", &"ToyButtonGhostOnLight")
	assert_str(screen.skip_button.text).is_equal("tutorial.invite.skip")
	# Focus starts on Start with its ring hidden; Skip takes focus too.
	assert_object(screen.get_viewport().gui_get_focus_owner()).is_same(screen.start_button)
	assert_bool(screen.start_button.has_focus(true)).is_false()
	assert_int(screen.skip_button.focus_mode).is_equal(Control.FOCUS_ALL)
	# The arrows and a gamepad's pad: Skip beside Start.
	var start := screen.start_button
	assert_object(start.find_valid_focus_neighbor(SIDE_RIGHT)).is_same(screen.skip_button)
	assert_object(screen.skip_button.find_valid_focus_neighbor(SIDE_LEFT)).is_same(start)
	# Skip and Esc (GameUi's overlay calls skip()) say the same; Start its own.
	var heard: Array[String] = []
	screen.skip_pressed.connect(func() -> void: heard.append("skip"))
	screen.start_pressed.connect(func() -> void: heard.append("start"))
	screen.skip_button.pressed.emit()
	screen.skip()
	screen.start_button.pressed.emit()
	assert_array(heard).contains_exactly(["skip", "skip", "start"])
	screen.close_invite()
	assert_bool(screen.invite_shown()).is_false()
	assert_bool(screen.dim.visible).is_false()


func test_step_is_lesson_2s_sentence_with_its_keycap() -> void:
	var screen := await _screen()
	_show(screen, 2, 1, 1)
	await get_tree().process_frame
	assert_bool(screen.step.visible).is_true()
	_assert_node(screen.step, "Step", "PanelContainer", &"ToyPlate")
	_assert_pinned(screen.step, Control.PRESET_CENTER_TOP, Vector2(0, 36))
	assert_int(screen.step.grow_horizontal).is_equal(Control.GROW_DIRECTION_BOTH)
	assert_int(screen.step.grow_vertical).is_equal(Control.GROW_DIRECTION_END)
	assert_vector(screen.step.custom_minimum_size).is_equal(Vector2(720, 0))
	var column := screen.step.get_node("V") as VBoxContainer
	_assert_node(column, "V", "VBoxContainer", &"ToyColumnTwelve")
	_assert_node(screen.progress_label, "Progress", "Label", &"ToyKicker")
	assert_bool(screen.progress_label.uppercase).is_true()
	assert_str(screen.progress_label.text).is_equal("Step 2 of 9")
	assert_int(screen.progress_label.auto_translate_mode).is_equal(
		Node.AUTO_TRANSLATE_MODE_DISABLED
	)
	_assert_node(screen.title_label, "Title", "Label", &"ToyPlateTitle")
	assert_str(screen.title_label.text).is_equal("tutorial.step.pick_up.title")
	_assert_node(screen.how, "How", "HBoxContainer", &"ToyRowTwelve")
	var lead := screen.how.get_node("Before") as Label
	_assert_node(lead, "Before", "Label", &"ToyPlateText")
	assert_str(lead.text).is_equal("Aim at the package and press")
	assert_int(lead.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	var key := screen.how.get_node("Key") as PanelContainer
	_assert_node(key, "Key", "PanelContainer", &"ToyKeyOnDark")
	assert_vector(key.custom_minimum_size).is_equal(Vector2(42, 0))
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
	# The list in the roster's place and look: lesson 1 done with its check, the current one in
	# the accent, the rest dim.
	_assert_node(screen.list, "List", "PanelContainer", &"ToyRoster")
	_assert_pinned(screen.list, Control.PRESET_TOP_RIGHT, Vector2(-39, 39))
	assert_int(screen.list.grow_horizontal).is_equal(Control.GROW_DIRECTION_BEGIN)
	assert_vector(screen.list.custom_minimum_size).is_equal(Vector2(330, 0))
	var list_column := screen.list.get_node("V") as VBoxContainer
	_assert_node(list_column, "V", "VBoxContainer", &"ToyColumnTwelve")
	var head := list_column.get_node("Head") as Label
	_assert_node(head, "Head", "Label", &"ToyKicker")
	assert_bool(head.uppercase).is_true()
	assert_str(head.text).is_equal("tutorial.list.title")
	_assert_node(screen.rows, "Rows", "VBoxContainer", &"ToyColumnEight")
	var names: Array[String] = []
	for row: Node in screen.rows.get_children():
		names.append(String(row.name))
	assert_array(names).contains_exactly(
		["Move", "PickUp", "HandBelt", "Throw", "Map", "Downed", "Death", "Voice", "Menu"]
	)
	var done := screen.rows.get_node("Move") as HBoxContainer
	_assert_node(done, "Move", "HBoxContainer", &"ToyRowTwelve")
	var done_name := done.get_node("Name") as Label
	_assert_node(done_name, "Name", "Label", &"ToyRosterName")
	assert_str(done_name.text).is_equal("tutorial.list.move")
	var check := done.get_node("Check") as TextureRect
	assert_object(check.texture).is_not_null()
	assert_vector(check.custom_minimum_size).is_equal(Vector2(27, 27))
	assert_int(check.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_int(check.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
	assert_int(check.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_object(check.self_modulate).is_equal(
		GameUi.THEME.get_color(&"font_color", &"ToyRosterName")
	)
	var now := screen.rows.get_node("PickUp/Name") as Label
	_assert_node(now, "Name", "Label", &"ToyRosterNameSelf")
	assert_bool(screen.rows.has_node("PickUp/Check")).is_false()
	var next := screen.rows.get_node("HandBelt/Name") as Label
	_assert_node(next, "Name", "Label", &"ToyRosterNameDead")
	# The map row's {key} is the map key bound now, set from code.
	var map := screen.rows.get_node("Map/Name") as Label
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
	_assert_node(screen.how, "HowKeys", "HBoxContainer", &"ToyRowThirtyTwo")
	var walk := screen.how.get_node("Walk") as HBoxContainer
	_assert_node(walk, "Walk", "HBoxContainer", &"ToyRowTwelve")
	var keys := walk.get_node("Keys") as HBoxContainer
	_assert_node(keys, "Keys", "HBoxContainer", &"ToyRowEight")
	var names: Array[String] = []
	for key: Node in keys.get_children():
		names.append(String(key.name))
		_assert_node(key, String(key.name), "PanelContainer", &"ToyKeyOnDark")
		assert_vector((key as Control).custom_minimum_size).is_equal(Vector2(42, 0))
	assert_array(names).contains_exactly(["Forward", "Left", "Backward", "Right"])
	var forward := keys.get_node("Forward/Text") as Label
	assert_str(forward.text).is_equal(KeyLabel.of_action(&"move_forward"))
	var walk_label := walk.get_node("Label") as Label
	_assert_node(walk_label, "Label", "Label", &"ToyPlateText")
	assert_str(walk_label.text).is_equal("control.walk")
	assert_int(walk_label.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_object(walk.get_child(0)).is_same(keys)
	for group: String in ["Sprint", "Jump"]:
		var row := screen.how.get_node(group) as HBoxContainer
		_assert_node(row, group, "HBoxContainer", &"ToyRowTwelve")
		var key := row.get_node("Key") as PanelContainer
		# Shift and Space take the wide size.
		assert_vector(key.custom_minimum_size).is_equal(Vector2(144, 0))
		assert_str((row.get_node("Label") as Label).text).is_equal("control." + group.to_lower())
	assert_str((screen.how.get_node("Jump/Key/Text") as Label).text).is_equal("Space")
	# The crouch key (#902, LD4 (b)): the row lists it after Jump. Ctrl is no wide key. Its label is
	# the deck key of Controls' row (#951), as the other keys' are.
	var crouch := screen.how.get_node("Crouch") as HBoxContainer
	_assert_node(crouch, "Crouch", "HBoxContainer", &"ToyRowTwelve")
	assert_int(crouch.get_index()).is_equal(screen.how.get_node("Jump").get_index() + 1)
	assert_str((crouch.get_node("Key/Text") as Label).text).is_equal("Ctrl")
	assert_vector((crouch.get_node("Key") as Control).custom_minimum_size).is_equal(Vector2(42, 0))
	assert_str((crouch.get_node("Label") as Label).text).is_equal("control.crouch")
	(
		assert_str(screen.how_text())
		. is_equal(
			(
				"%s %s %s %s Walk %s Sprint Space Jump Ctrl Crouch Alt Sneak"
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
	var first := screen.rows.get_child(0) as HBoxContainer
	assert_str(String(first.name)).is_equal("Move")
	assert_str((first.get_node("Name") as Label).theme_type_variation).is_equal(
		&"ToyRosterNameSelf"
	)
	assert_str(String(screen.rows.get_child(1).name)).is_equal("PickUp")
	_assert_ignores_mouse(screen.step)


func test_a_howto_step_is_a_round_keycap_and_a_step_with_no_how_a_title_only() -> void:
	# No lesson shows either since the tutorial deals no task (#900, LE3 (a)): the screen keeps
	# both, drawn here on lesson 5 (the map) with a step the test builds after its own.
	var screen := await _screen()
	var howto := TutorialStep.new()
	howto.title_key = &"tutorial.step.howto.title"
	howto.how_key = &"tutorial.step.howto.how"
	howto.keys = [TutorialStep.HOWTO_GLYPH]
	var built := _lessons_with_step_after_the_map(howto)
	_show(screen, 5, 2, 4, built)
	await get_tree().process_frame
	assert_str(screen.progress_label.text).is_equal("Step 5 of 9")
	assert_str(screen.title_label.text).is_equal("tutorial.step.howto.title")
	var key := screen.how.get_node("Key") as PanelContainer
	_assert_node(key, "Key", "PanelContainer", &"ToyKeyRound")
	assert_vector(key.custom_minimum_size).is_equal(Vector2(42, 0))
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
				"Move",
				"PickUp",
				"HandBelt",
				"Throw",
				"Map",
				"Downed",
				"Death",
				"Voice",
				"Menu",
			]
		)
	)
	# A step with neither how nor keys (as the map lesson had, the engineer's answer on PR #722): the
	# title only.
	var bare := TutorialStep.new()
	bare.title_key = &"tutorial.step.deliver.title"
	_show(screen, 5, 2, 4, _lessons_with_step_after_the_map(bare))
	assert_str(screen.title_label.text).is_equal("tutorial.step.deliver.title")
	assert_bool(screen.how.visible).is_false()
	assert_str(screen.how_text()).is_empty()
	# Lesson 9's Esc is a wide keycap.
	_show(screen, 9, 1, 8)
	await get_tree().process_frame
	assert_vector(screen.keycaps()[0].custom_minimum_size).is_equal(Vector2(144, 0))
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
	assert_str((screen.rows.get_node("Map/Name") as Label).text).is_equal("Map and tasks (K)")
	_bind({&"interact": KEY_SPACE})
	_show(screen, 2, 1, 1)
	await get_tree().process_frame
	assert_str(screen.how_text()).is_equal("Aim at the package and press Space")
	assert_vector(screen.keycaps()[0].custom_minimum_size).is_equal(Vector2(144, 0))


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
	assert_vector(screen.keycaps()[0].custom_minimum_size).is_equal(Vector2(50, 0))
	# Every lesson and step at large text in Ukrainian: inside the screen, the two plates apart.
	var lessons := (load(LESSONS) as TutorialLessons).lessons
	for lesson in range(1, lessons.size() + 1):
		var steps := lessons[lesson - 1].steps.size()
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
	assert_str((screen.box.get_node("V/Text/Head") as Label).text).is_equal("tutorial.list.title")


func test_the_step_goes_under_the_dead_s_tile() -> void:
	var screen := await _screen()
	_show(screen, 7, 1, 6)
	var spectate := Control.new()
	spectate.position = Vector2(0, 40)
	spectate.size = Vector2(300, 90)
	screen.add_child(spectate)
	screen.set_step_under(spectate)
	assert_float(screen.step.offset_top).is_equal(154.0)
	screen.set_step_under(null)
	assert_float(screen.step.offset_top).is_equal(36.0)


func _show(
	screen: TutorialScreen,
	lesson: int,
	step: int,
	done_count: int,
	lessons: TutorialLessons = null,
) -> void:
	if lessons == null:
		lessons = load(LESSONS) as TutorialLessons
	var done: Array[bool] = []
	for i in lessons.lessons.size():
		done.append(i < done_count)
	screen.show_lessons(lessons, lesson, step, done)


## The real lessons with `extra` as the map lesson's second step, on copies: the loaded
## tutorial.tres stays as it is for the other tests.
func _lessons_with_step_after_the_map(extra: TutorialStep) -> TutorialLessons:
	var real := load(LESSONS) as TutorialLessons
	var built := TutorialLessons.new()
	for lesson: TutorialLesson in real.lessons:
		if lesson.list_key != &"tutorial.list.map":
			built.lessons.append(lesson)
			continue
		var map := TutorialLesson.new()
		map.list_key = lesson.list_key
		map.list_action = lesson.list_action
		map.steps = lesson.steps.duplicate()
		map.steps.append(extra)
		built.lessons.append(map)
	return built


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
