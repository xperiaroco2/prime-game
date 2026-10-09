extends GdUnitTestSuite
## The connecting screen (client/ui/connecting_screen.gd, #494): prime-game-ui's s3 handoff at
## ui-0.4.0 node for node, each of its 16 states, each failure from its EndReasons id, the focus
## as drawn, the texts in both languages, the players of the loading, the card's hook, the spinner
## and the keycap under large text. How it looks: the `shot`s of client/dev/connecting_preview.tscn
## per state (the PR).

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const DECK := "res://client/i18n/strings.csv"

var _screen: ConnectingScreen


func before_test() -> void:
	_screen = auto_free(ConnectingScreen.new())
	_screen.theme = GameUi.THEME
	add_child(_screen)


func after_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)
	UiPrefs.reset()


func test_the_tree_matches_the_handoff_node_for_node() -> void:
	# The size constants come in deferred, on the theme's arrival (UiParts.sized).
	await _frames(1)
	# [path, class, variation, minimum size] as the handoff's node lines give them.
	var nodes: Array = [
		["Night", "Panel", &"ToyBackdropNight", Vector2.ZERO],
		["Connecting", "VBoxContainer", &"ToyColumnTwentyFour", Vector2(768, 0)],
		["Connecting/Spinner", "Panel", &"ToySpinner", Vector2(90, 90)],
		["Connecting/Texts", "VBoxContainer", &"ToyColumnEight", Vector2.ZERO],
		["Connecting/Texts/Title", "Label", &"ToyTitleOnDark", Vector2(768, 0)],
		["Connecting/Texts/Step", "Label", &"ToyTextOnDark", Vector2.ZERO],
		["Connecting/CodeRow", "HBoxContainer", &"ToyRowEight", Vector2.ZERO],
		["Connecting/CodeRow/Label", "Label", &"ToyTextMutedOnDark", Vector2.ZERO],
		["Connecting/CodeRow/Code", "PanelContainer", &"ToyKeyOnDark", Vector2(36, 0)],
		["Connecting/CodeRow/Code/Text", "Label", &"ToyKeyText", Vector2.ZERO],
		["Connecting/Elapsed", "Label", &"ToyTextMutedOnDark", Vector2.ZERO],
		["Connecting/CancelRaised/Cancel", "Button", &"ToyButtonSecondary", Vector2.ZERO],
		["Failure", "VBoxContainer", &"ToyColumnThirtyTwo", Vector2(848, 0)],
		["Failure/Texts", "VBoxContainer", &"ToyColumnSixteen", Vector2.ZERO],
		["Failure/Texts/Title", "Label", &"ToyTitleOnDark", Vector2(848, 0)],
		["Failure/Texts/Body", "Label", &"ToyTextMutedOnDark", Vector2(848, 0)],
		["Failure/Texts/Versions", "VBoxContainer", &"ToyColumnFour", Vector2.ZERO],
		["Failure/Texts/Versions/Host", "Label", &"ToyTextOnDark", Vector2.ZERO],
		["Failure/Texts/Versions/Own", "Label", &"ToyTextOnDark", Vector2.ZERO],
		["Failure/Buttons", "HBoxContainer", &"ToyRowSixteen", Vector2.ZERO],
		["Failure/Buttons/PrimaryRaised/Primary", "Button", &"ToyButtonPrimary", Vector2.ZERO],
		["Failure/Buttons/BackGhost", "Button", &"ToyButtonGhostOnDark", Vector2.ZERO],
		["Failure/Buttons/BackSoloRaised/BackSolo", "Button", &"ToyButtonSecondary", Vector2.ZERO],
		["Loading", "VBoxContainer", &"ToyColumnSixteen", Vector2(768, 0)],
		["Loading/Title", "Label", &"ToyTitleOnDark", Vector2.ZERO],
		["Loading/Bar", "ProgressBar", &"ToyBarProgress", Vector2(768, 16)],
		["Loading/Players", "VBoxContainer", &"ToyColumnEight", Vector2.ZERO],
		["Tip", "PanelContainer", &"ToyPlate", Vector2(1072, 0)],
		["Tip/Text", "Label", &"ToyPlateText", Vector2(1036, 0)],
		["Head", "VBoxContainer", &"ToyColumnTwelve", Vector2(768, 0)],
		["Head/Title", "Label", &"ToyTitleOnDark", Vector2.ZERO],
		["Head/Bar", "ProgressBar", &"ToyBarProgress", Vector2(768, 16)],
	]
	for each: Array in nodes:
		var path := str(each[0])
		var found := _screen.get_node_or_null(NodePath(path)) as Control
		assert_object(found).override_failure_message(path).is_not_null()
		if found == null:
			continue
		assert_str(found.get_class()).override_failure_message(path).is_equal(str(each[1]))
		assert_str(String(found.theme_type_variation)).override_failure_message(path).is_equal(
			String(each[2] as StringName)
		)
		assert_that(found.custom_minimum_size).override_failure_message(path).is_equal(each[3])
	# The roots in the handoff's order, each a child of the screen's full-rect root.
	var roots: Array[String] = []
	for child: Node in _screen.get_children():
		roots.append(String(child.name))
	assert_array(roots).contains_exactly(
		["Night", "Connecting", "Failure", "Loading", "Tip", "Head"]
	)
	assert_int(_screen.night.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_assert_full_rect(_screen.night)
	# Anchors, offsets and grow as drawn.
	_assert_placed(_screen.connecting, Control.PRESET_CENTER, 0, Control.GROW_DIRECTION_BOTH)
	_assert_placed(_screen.failure, Control.PRESET_CENTER, 0, Control.GROW_DIRECTION_BOTH)
	_assert_placed(_screen.loading, Control.PRESET_CENTER_TOP, 368, Control.GROW_DIRECTION_END)
	_assert_placed(_screen.tip, Control.PRESET_CENTER_BOTTOM, -88, Control.GROW_DIRECTION_BOTH)
	_assert_placed(_screen.head, Control.PRESET_CENTER_TOP, 64, Control.GROW_DIRECTION_END)
	assert_int(_screen.connecting.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	assert_int(_screen.failure.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	# Size flags as drawn; raised buttons on their ToyRaised with its base, Back beside flat.
	assert_int(_screen.spinner.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_that(_screen.spinner.pivot_offset_ratio).is_equal(Vector2(0.5, 0.5))
	assert_int(_screen.code_row.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_int(_screen.code_key.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	assert_int(_screen.cancel.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_CENTER)
	for raised: ToyRaised in [_screen.cancel, _screen.primary, _screen.back_solo]:
		assert_bool(raised.base.visible).is_true()
		assert_object(raised.face.get_node(^"ToyPress")).is_not_null()
	assert_str(String(_screen.primary.base.theme_type_variation)).is_equal("ToyBasePrimaryOnDark")
	assert_str(String(_screen.cancel.base.theme_type_variation)).is_equal("ToyBaseRaisedOnDark")
	assert_object(_screen.back_ghost.get_node(^"ToyPress")).is_not_null()
	assert_int(_screen.title_label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_float(_screen.bar.max_value).is_equal(100.0)
	assert_bool(_screen.bar.show_percentage).is_false()


func test_each_end_reason_shows_its_failure_state_title_body_and_buttons() -> void:
	# [reason, state, title key, body key, Primary's key or "" for Back alone]: the s3 table.
	var table: Array = [
		[&"no_room", "fail-no-room", "connect.fail.title", "connect.fail.no_room", ""],
		[&"joins_closed", "fail-started", "connect.fail.title", "connect.fail.started", "retry"],
		[&"wrong_version", "fail-version", "connect.fail.title", "connect.fail.version", ""],
		[&"wrong_content", "fail-version", "connect.fail.title", "connect.fail.version", ""],
		[&"service_refused", "fail-version", "connect.fail.title", "connect.fail.version", ""],
		[&"unknown_map", "fail-version", "connect.fail.title", "connect.fail.version", ""],
		[&"full", "fail-full", "connect.fail.title", "connect.fail.full", "retry"],
		[
			&"service_unreachable",
			"fail-service",
			"connect.fail.title",
			"connect.fail.service",
			"direct"
		],
		[
			&"host_unreachable",
			"fail-unreachable",
			"connect.fail.title",
			"connect.fail.unreachable",
			"direct"
		],
		[&"connect_failed", "fail-no-answer", "connect.fail.title", "connect.fail.body", "retry"],
		[&"host_lost", "lost", "connect.lost.title", "connect.lost.body", ""],
		[&"load_failed", "map-failed", "connect.map_fail.title", "connect.map_fail.body", ""],
		[&"load_deadline", "map-failed", "connect.map_fail.title", "connect.map_fail.body", ""],
		[&"row_error", "error", "connect.error.title", "connect.error.body", ""],
		[&"own_client_malformed", "error", "connect.error.title", "connect.error.body", ""],
		[&"own_client_disconnected", "error", "connect.error.title", "connect.error.body", ""],
		[&"cannot_host", "host-failed", "connect.host_fail.title", "connect.error.body", "retry"],
	]
	for row: Array in table:
		var reason := row[0] as StringName
		var why := String(reason)
		var state := EndReasons.failure_state(reason)
		assert_str(String(state)).override_failure_message(why).is_equal(str(row[1]))
		assert_bool(_screen.show_failure(state)).override_failure_message(why).is_true()
		assert_str(String(_screen.state())).override_failure_message(why).is_equal(str(row[1]))
		assert_str(_screen.failure_title.text).override_failure_message(why).is_equal(str(row[2]))
		assert_str(_screen.failure_body.text).override_failure_message(why).is_equal(str(row[3]))
		var action := str(row[4])
		assert_bool(_screen.failure.visible).is_true()
		assert_bool(_screen.connecting.visible).is_false()
		assert_bool(_screen.versions.visible).override_failure_message(why).is_false()
		assert_bool(_screen.primary.visible).override_failure_message(why).is_equal(
			not action.is_empty()
		)
		assert_bool(_screen.back_ghost.visible).override_failure_message(why).is_equal(
			not action.is_empty()
		)
		assert_bool(_screen.back_solo.visible).override_failure_message(why).is_equal(
			action.is_empty()
		)
		if not action.is_empty():
			assert_str((_screen.primary.face as Button).text).is_equal("connect.fail." + action)
	assert_int(table.size()).is_equal(EndReasons.FAILURE_STATES.size())


func test_leaving_and_an_unknown_reason_show_no_failure() -> void:
	_screen.show_join("K7M2QX", JoinProgress.Step.FINDING)
	for reason: StringName in [&"left", &"closed", &"no_such_reason"]:
		assert_bool(_screen.show_failure(EndReasons.failure_state(reason))).is_false()
	assert_str(String(_screen.state())).is_equal("finding")


func test_each_button_says_what_it_does() -> void:
	var said: Array[String] = []
	_screen.cancel_requested.connect(func() -> void: said.append("cancel"))
	_screen.back_requested.connect(func() -> void: said.append("back"))
	_screen.retry_requested.connect(func() -> void: said.append("retry"))
	_screen.direct_requested.connect(func() -> void: said.append("direct"))
	(_screen.cancel.face as Button).pressed.emit()
	_screen.show_failure(&"fail-full")
	(_screen.primary.face as Button).pressed.emit()
	_screen.back_ghost.pressed.emit()
	_screen.show_failure(&"fail-service")
	(_screen.primary.face as Button).pressed.emit()
	_screen.show_failure(&"lost")
	(_screen.back_solo.face as Button).pressed.emit()
	assert_array(said).is_equal(["cancel", "retry", "back", "direct", "back"])


func test_the_join_states_show_the_step_the_code_and_the_time() -> void:
	_screen.show_join("K7M2QX", JoinProgress.Step.FINDING)
	_screen.set_elapsed(4)
	assert_str(String(_screen.state())).is_equal("finding")
	assert_str(_screen.step_label.text).is_equal("connect.step.finding")
	assert_bool(_screen.code_row.visible).is_true()
	assert_str(_screen.code_label.text).is_equal("K7M2QX")
	assert_str(_screen.elapsed_label.text).is_equal("0:04")
	assert_str(_screen.title_label.text).is_equal("Connecting…")
	# CONNECTING of a code join looks as finding, with its own step.
	_screen.set_step(JoinProgress.Step.CONNECTING)
	assert_str(String(_screen.state())).is_equal("finding")
	assert_str(_screen.step_label.text).is_equal("connect.step.connecting")
	_screen.set_step(JoinProgress.Step.JOINED)
	assert_str(String(_screen.state())).is_equal("joined")
	assert_str(_screen.step_label.text).is_equal("connect.step.joined")
	# A Direct join: no code row and no address anywhere.
	_screen.show_join("", JoinProgress.Step.CONNECTING)
	assert_str(String(_screen.state())).is_equal("connecting-direct")
	assert_bool(_screen.code_row.visible).is_false()
	assert_str(_screen.elapsed_label.text).is_equal("0:00")
	assert_str(ConnectingScreen.elapsed_text(65)).is_equal("1:05")
	assert_str(ConnectingScreen.elapsed_text(600)).is_equal("10:00")
	assert_str(ConnectingScreen.elapsed_text(-3)).is_equal("0:00")
	for label: Label in [_screen.code_label, _screen.elapsed_label, _screen.title_label]:
		assert_int(label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)


func test_the_title_names_the_lobby_once_known_and_follows_the_language() -> void:
	# #214 sends the lobby's name; a stub name here.
	_screen.show_join("K7M2QX", JoinProgress.Step.JOINED)
	_screen.set_lobby("Olena's lobby")
	assert_str(_screen.title_label.text).is_equal("Connecting to “Olena's lobby”…")
	_screen.set_lobby("", "Olena")
	assert_str(_screen.title_label.text).is_equal("Connecting to “Olena's lobby”…")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	assert_str(_screen.title_label.text).is_equal("Підключення до «Olena's lobby»…")
	_screen.set_lobby("", "Олена")
	assert_str(_screen.title_label.text).is_equal("Підключення до «Лобі: Олена»…")
	_screen.set_lobby("")
	assert_str(_screen.title_label.text).is_equal("Підключення…")
	TranslationServer.set_locale(Languages.ENGLISH)
	assert_str(_screen.title_label.text).is_equal("Connecting…")


func test_the_version_lines_show_only_on_fail_version_when_both_are_known() -> void:
	var lines := PackedStringArray(["13 (a1b2c3)", "12 (9f8e7d)"])
	_screen.show_failure(&"fail-version", lines)
	assert_bool(_screen.versions.visible).is_true()
	assert_str(_screen.version_host.text).is_equal("Host: 13 (a1b2c3)")
	assert_str(_screen.version_own.text).is_equal("You: 12 (9f8e7d)")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	assert_str(_screen.version_host.text).is_equal("Хост: 13 (a1b2c3)")
	assert_str(_screen.version_own.text).is_equal("Ти: 12 (9f8e7d)")
	_screen.show_failure(&"fail-version")
	assert_bool(_screen.versions.visible).is_false()
	_screen.show_failure(&"fail-full", lines)
	assert_bool(_screen.versions.visible).is_false()


func test_the_focus_is_on_cancel_the_primary_or_the_lone_back() -> void:
	_screen.show_join("K7M2QX", JoinProgress.Step.FINDING)
	await _frames(2)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_screen.cancel.face)
	_screen.show_failure(&"fail-no-answer")
	await _frames(2)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_screen.primary.face)
	_screen.show_failure(&"fail-no-room")
	await _frames(2)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_screen.back_solo.face)
	# Shown again (GameUi hides the screen between sessions): the focus comes back.
	_screen.visible = false
	_screen.get_viewport().gui_release_focus()
	_screen.visible = true
	await _frames(2)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_screen.back_solo.face)
	# Every button takes the keyboard and the gamepad.
	for button: Button in [
		_screen.cancel.face, _screen.primary.face, _screen.back_ghost, _screen.back_solo.face
	]:
		assert_int(button.focus_mode).is_equal(Control.FOCUS_ALL)


func test_the_loading_lists_the_host_first_the_own_row_you_and_who_has_loaded() -> void:
	var mode := load(MODE) as GameMode
	var model := Preview.fake_model(mode, false)
	model.fold(&"PlayerJoined", {"peer": 7, "name": "Taras", "spot": Vector3.ZERO})
	model.fold(&"PlayerLoaded", {"peer": 1})
	_screen.show_loading("tip.two_hands")
	_screen.set_load_fraction(0.62)
	_screen.refresh_loading(model)
	assert_str(String(_screen.state())).is_equal("load")
	assert_bool(_screen.loading.visible).is_true()
	assert_bool(_screen.tip.visible).is_true()
	assert_bool(_screen.head.visible).is_false()
	assert_float(_screen.bar.value).is_equal_approx(62.0, 0.001)
	assert_str(_screen.tip_label.text).is_equal("tip.two_hands")
	var rows: Array[String] = []
	for row: Node in _screen.players.get_children():
		var name_label := row.get_node(^"Name") as Label
		var state := row.get_node(^"State") as Label
		rows.append(
			"%s %s %s %s" % [row.name, name_label.text, state.text, state.theme_type_variation]
		)
		assert_str(String(row.get_class())).is_equal("HBoxContainer")
		assert_str(String((row as HBoxContainer).theme_type_variation)).is_equal("ToyRowTwelve")
		assert_bool(name_label.clip_text).is_true()
		assert_int(name_label.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
	(
		assert_array(rows)
		. contains_exactly(
			[
				"HostRow Player1 loading.player_ready ToyTextOnDark",
				"Row player.you loading.player_loading ToyTextMutedOnDark",
				"OtherRow Player3 loading.player_loading ToyTextMutedOnDark",
				"OtherRow2 Taras loading.player_loading ToyTextMutedOnDark",
			]
		)
	)
	var host_name := _screen.players.get_child(0).get_node(^"Name") as Label
	assert_int(host_name.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	var own_name := _screen.players.get_child(1).get_node(^"Name") as Label
	assert_int(own_name.auto_translate_mode).is_not_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	# The own load confirmed: its row reads ready, as drawn.
	model.fold(&"PlayerLoaded", {"peer": 2})
	_screen.refresh_loading(model)
	var own_state := _screen.players.get_child(1).get_node(^"State") as Label
	assert_str(own_state.text).is_equal("loading.player_ready")
	assert_str(String(own_state.theme_type_variation)).is_equal("ToyTextOnDark")


func test_a_loading_draws_one_of_the_decks_tips() -> void:
	_screen.show_loading()
	assert_array(ConnectingScreen.TIPS).contains([_screen.tip_label.text])
	# The tips are every tip.* key of the copy deck, no more.
	var deck_tips: Array[String] = []
	for key: String in _deck_keys():
		if key.begins_with("tip."):
			deck_tips.append(key)
	assert_array(ConnectingScreen.TIPS).contains_exactly_in_any_order(deck_tips)


func test_the_card_hook_shows_head_and_card_instead_of_the_players_and_the_tip() -> void:
	# #490 makes the card and #254 picks it; a stand-in here.
	var face := PanelContainer.new()
	face.theme_type_variation = &"ToyPanelHowto"
	var made := UiParts.raised(face)
	_screen.show_loading("tip.two_hands")
	_screen.set_load_fraction(0.5)
	_screen.show_card(made)
	assert_str(String(_screen.state())).is_equal("load-card")
	assert_bool(_screen.head.visible).is_true()
	assert_bool(made.visible).is_true()
	assert_bool(_screen.loading.visible).is_false()
	assert_bool(_screen.tip.visible).is_false()
	assert_float((_screen.head.get_node(^"Bar") as ProgressBar).value).is_equal_approx(50.0, 0.001)
	assert_object(made.get_parent()).is_same(_screen)
	_assert_placed(made, Control.PRESET_CENTER, 40, Control.GROW_DIRECTION_BOTH)
	assert_that(made.custom_minimum_size).is_equal(Vector2(1616, 0))
	_screen.show_loading("tip.two_hands")
	assert_str(String(_screen.state())).is_equal("load")
	assert_object(_screen.card).is_null()
	await _frames(1)
	assert_bool(is_instance_valid(made)).is_false()


func test_the_spinner_turns_once_a_second_and_half_as_fast_under_reduced_motion() -> void:
	_screen.show_join("", JoinProgress.Step.CONNECTING)
	UiPrefs.reduced_motion = false
	_screen.spinner.rotation = 0.0
	_screen._process(0.25)
	assert_float(_screen.spinner.rotation).is_equal_approx(TAU / 4.0, 0.0001)
	UiPrefs.reduced_motion = true
	_screen.spinner.rotation = 0.0
	_screen._process(0.25)
	assert_float(_screen.spinner.rotation).is_equal_approx(TAU / 8.0, 0.0001)
	# Hidden (a failure), it stands still.
	_screen.show_failure(&"lost")
	_screen._process(0.25)
	assert_float(_screen.spinner.rotation).is_equal_approx(TAU / 8.0, 0.0001)


func test_the_keycap_and_the_spinner_take_their_size_from_the_theme_also_large() -> void:
	await _frames(1)
	assert_that(_screen.code_key.custom_minimum_size).is_equal(Vector2(36, 0))
	_screen.theme = GameUi.THEME_LARGE
	await _frames(1)
	assert_that(_screen.code_key.custom_minimum_size).is_equal(Vector2(42, 0))
	assert_that(_screen.spinner.custom_minimum_size).is_equal(Vector2(90, 90))


func test_every_key_the_screen_names_is_in_the_deck() -> void:
	var keys: Array[String] = [
		"common.back",
		"common.cancel",
		"common.code",
		"connect.connecting",
		"connect.connecting_unnamed",
		"connect.fail.version_host",
		"connect.fail.version_own",
		"howto.label",
		"loading.player_loading",
		"loading.player_ready",
		"loading.title",
		"lobby.default_name",
		"player.you",
		"task.delivery",
	]
	keys.append_array(ConnectingScreen.STEP_KEYS.values())
	keys.append_array(ConnectingScreen.ACTION_KEYS.values())
	keys.append_array(ConnectingScreen.TIPS)
	for look: Array in ConnectingScreen.FAILURES.values():
		keys.append(str(look[0]))
		keys.append(str(look[1]))
	var deck := _deck_keys()
	for key: String in keys:
		assert_bool(deck.has(key)).override_failure_message(key).is_true()


func _assert_full_rect(control: Control) -> void:
	assert_float(control.anchor_left).is_equal(0.0)
	assert_float(control.anchor_top).is_equal(0.0)
	assert_float(control.anchor_right).is_equal(1.0)
	assert_float(control.anchor_bottom).is_equal(1.0)
	for offset: float in [
		control.offset_left, control.offset_top, control.offset_right, control.offset_bottom
	]:
		assert_float(offset).is_equal(0.0)


## Anchors of `preset`, offsets 0 across and `top` down, growing both ways across and `grow` down.
func _assert_placed(
	control: Control, preset: Control.LayoutPreset, top: float, grow: Control.GrowDirection
) -> void:
	var probe := Control.new()
	probe.set_anchors_preset(preset)
	var why := String(control.name)
	assert_float(control.anchor_left).override_failure_message(why).is_equal(probe.anchor_left)
	assert_float(control.anchor_top).override_failure_message(why).is_equal(probe.anchor_top)
	assert_float(control.anchor_right).override_failure_message(why).is_equal(probe.anchor_right)
	assert_float(control.anchor_bottom).override_failure_message(why).is_equal(probe.anchor_bottom)
	probe.free()
	assert_float(control.offset_left).override_failure_message(why).is_equal(0.0)
	assert_float(control.offset_right).override_failure_message(why).is_equal(0.0)
	assert_float(control.offset_top).override_failure_message(why).is_equal(top)
	assert_float(control.offset_bottom).override_failure_message(why).is_equal(top)
	assert_int(control.grow_horizontal).override_failure_message(why).is_equal(
		Control.GROW_DIRECTION_BOTH
	)
	assert_int(control.grow_vertical).override_failure_message(why).is_equal(grow)


## The copy deck's keys (its first column; the plural rows have none).
func _deck_keys() -> Array[String]:
	var keys: Array[String] = []
	var file := FileAccess.open(DECK, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if not row.is_empty() and not row[0].is_empty():
			keys.append(row[0])
	return keys


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
