extends GdUnitTestSuite
## The downed, dead and respawn screen (client/ui/LifeScreen, #497; ARCHITECTURE §4.7.44) under the
## shared theme: the UI handoff's plates node for node (prime-game-ui `ui-0.4.0`
## `docs/handoff/s09-downed.md`: names, classes, variations, anchors, offsets, grow directions, size
## flags and minimum sizes), no node taking the mouse or focus, each state the handoff draws (down,
## down-holding, raise, dead, back) in English and Ukrainian, the give-up line's keycap following a
## rebind through the life view, the keycap's large-text width and nothing outside the screen.

const OWN := 1
const MATE := 3

var _locale := ""


func before_test() -> void:
	# The deck's words: English unless a test switches, whatever the machine's language is.
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	# The InputMap is global: every later suite reads the project's bindings.
	Controls.new().apply()


func test_the_tree_is_the_handoffs_node_for_node() -> void:
	var screen := await _screen()
	# [path, class, variation] of every node the handoff adds to the HUD.
	var nodes: Array[Array] = [
		["Downed", "PanelContainer", &"ToyPlate"],
		["Downed/V", "VBoxContainer", &"ToyColumnEight"],
		["Downed/V/Title", "Label", &"ToyTitleOnDark"],
		["Downed/V/Bleed", "PanelContainer", &"ToyBarTrack"],
		["Downed/V/Bleed/Fill", "ProgressBar", &"ToyBarHealth"],
		["Downed/V/Left", "Label", &"ToyTextMutedOnDark"],
		["Downed/V/Raise", "ProgressBar", &"ToyBarProgress"],
		["Downed/V/Pad", "Control", &""],
		["GiveUp", "PanelContainer", &"ToyPlate"],
		["GiveUp/V", "VBoxContainer", &"ToyColumnEight"],
		["GiveUp/V/Line", "HBoxContainer", &"ToyRowFour"],
		["GiveUp/V/Line/Before", "Label", &"ToyTextOnDark"],
		["GiveUp/V/Line/Key", "PanelContainer", &"ToyKeyOnDark"],
		["GiveUp/V/Line/Key/Text", "Label", &"ToyKeyText"],
		["GiveUp/V/Line/After", "Label", &"ToyTextOnDark"],
		["GiveUp/V/Hold", "ProgressBar", &"ToyBarProgress"],
		["GiveUp/V/Pad", "Control", &""],
		["Spectate", "PanelContainer", &"ToyPlate"],
		["Spectate/V", "VBoxContainer", &"ToyColumnFour"],
		["Spectate/V/Respawn", "Label", &"ToyTextMutedOnDark"],
		["Spectate/V/Watching", "Label", &"ToyTitleOnDark"],
		["Protect", "PanelContainer", &"ToyChipLight"],
		["Protect/Text", "Label", &"ToyChipLightText"],
	]
	for node: Array in nodes:
		var path := node[0] as String
		var found := screen.get_node_or_null(path) as Control
		assert_object(found).override_failure_message(path).is_not_null()
		assert_str(found.get_class()).override_failure_message(path).is_equal(node[1])
		assert_str(found.theme_type_variation).override_failure_message(path).is_equal(node[2])
	var order: Array[String] = []
	for child: Node in screen.get_node("Downed/V").get_children():
		order.append(child.name)
	assert_array(order).contains_exactly(["Title", "Bleed", "Left", "Raise", "Pad"])
	assert_int(screen.get_child_count()).is_equal(4)
	# Every text here holds data or is drawn in pieces: set from code, never translated again.
	for label: Node in screen.find_children("*", "Label", true, false):
		(
			assert_int((label as Label).auto_translate_mode)
			. override_failure_message(label.name)
			. is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
		)
	for bar: ProgressBar in [screen.bleed.fill, screen.raise_bar, screen.hold_bar]:
		assert_float(bar.max_value).is_equal(1.0)
		assert_bool(bar.show_percentage).is_false()


func test_anchors_offsets_grow_and_sizes_are_the_handoffs() -> void:
	var screen := await _screen()
	var both := Control.GROW_DIRECTION_BOTH
	var begin := Control.GROW_DIRECTION_BEGIN
	var end := Control.GROW_DIRECTION_END
	# [node, anchors (left, top, right, bottom), offsets, grow h, grow v]
	var placed: Array[Array] = [
		[screen.downed, Vector4(0.5, 0, 0.5, 0), Vector4(0, 152, 0, 152), both, end],
		[screen.give_up, Vector4(0.5, 1, 0.5, 1), Vector4(0, -128, 0, -128), both, begin],
		[screen.spectate, Vector4(0.5, 0, 0.5, 0), Vector4(0, 40, 0, 40), both, end],
		[screen.protect, Vector4(0.5, 0, 0.5, 0), Vector4(0, 144, 0, 144), both, end],
	]
	for row: Array in placed:
		var node: Control = row[0]
		var anchors := Vector4(
			node.anchor_left, node.anchor_top, node.anchor_right, node.anchor_bottom
		)
		var offsets := Vector4(
			node.offset_left, node.offset_top, node.offset_right, node.offset_bottom
		)
		assert_vector(anchors).override_failure_message(node.name).is_equal(row[1])
		assert_vector(offsets).override_failure_message(node.name).is_equal(row[2])
		assert_int(node.grow_horizontal).is_equal(row[3])
		assert_int(node.grow_vertical).is_equal(row[4])
	assert_vector(screen.downed.custom_minimum_size).is_equal(Vector2(688, 0))
	assert_vector(screen.title_label.custom_minimum_size).is_equal(Vector2(600, 0))
	assert_int(screen.title_label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_vector(screen.bleed.custom_minimum_size).is_equal(Vector2(600, 16))
	assert_vector(screen.bleed.fill.custom_minimum_size).is_equal(Vector2(0, 10))
	assert_vector(screen.raise_bar.custom_minimum_size).is_equal(Vector2(600, 16))
	assert_vector(screen.raise_pad.custom_minimum_size).is_equal(Vector2(0, 4))
	assert_vector(screen.key.custom_minimum_size).is_equal(Vector2(36, 0))
	assert_vector(screen.hold_bar.custom_minimum_size).is_equal(Vector2(360, 10))
	assert_int(screen.hold_bar.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_CENTER)
	var pad := screen.get_node("GiveUp/V/Pad") as Control
	assert_vector(pad.custom_minimum_size).is_equal(Vector2(0, 4))
	var line := screen.get_node("GiveUp/V/Line") as HBoxContainer
	assert_int(line.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	for piece: Label in [screen.before_label, screen.after_label]:
		assert_int(piece.size_flags_vertical).is_equal(Control.SIZE_SHRINK_CENTER)
	for centred: Label in [
		screen.title_label,
		screen.left_label,
		screen.key_label,
		screen.respawn_label,
		screen.watching_label
	]:
		assert_int(centred.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)


func test_no_node_takes_the_mouse_or_focus() -> void:
	var screen := await _screen()
	screen.show_hud(_down())
	var all: Array[Node] = screen.find_children("*", "Control", true, false)
	all.append(screen)
	for node: Node in all:
		var control := node as Control
		assert_int(control.mouse_filter).override_failure_message(str(control.get_path())).is_equal(
			Control.MOUSE_FILTER_IGNORE
		)
		assert_int(control.focus_mode).is_equal(Control.FOCUS_NONE)


func test_nothing_shows_by_default() -> void:
	var screen := await _screen()
	for plate: Control in [screen.downed, screen.give_up, screen.spectate, screen.protect]:
		assert_bool(plate.visible).override_failure_message(plate.name).is_false()


func test_down_shows_the_bleed_out_and_the_give_up_line() -> void:
	var screen := await _screen()
	screen.show_hud(_down())
	await get_tree().process_frame
	assert_bool(screen.downed.visible).is_true()
	assert_bool(screen.give_up.visible).is_true()
	assert_bool(screen.spectate.visible).is_false()
	assert_bool(screen.protect.visible).is_false()
	assert_bool(screen.raise_bar.visible).is_false()
	assert_bool(screen.raise_pad.visible).is_false()
	assert_str(screen.title_label.text).is_equal("You're down")
	assert_str(screen.left_label.text).is_equal("0:07 left")
	assert_float(screen.bleed.fill.value).is_equal_approx(0.7, 1e-4)
	# Coloured with the health ramp as the HUD's health: 0.7 is stop 14.
	assert_object(screen.bleed.fill.self_modulate).is_equal(
		GameUi.THEME.get_color(&"ramp_stop_14", &"ToyBarHealth")
	)
	assert_str(screen.before_label.text).is_equal("Hold")
	assert_str(screen.key_label.text).is_equal("F")
	assert_str(screen.after_label.text).is_equal("to give up")
	assert_str(screen.give_up_text()).is_equal("Hold F to give up")
	assert_float(screen.hold_bar.value).is_equal(0.0)
	assert_bool(screen.hold_bar.visible).is_true()


func test_holding_fills_the_bar_and_the_plate_keeps_its_size() -> void:
	var screen := await _screen()
	screen.show_hud(_down())
	var rest := screen.give_up.get_combined_minimum_size()
	var holding := _down()
	holding.give_up = 0.45
	screen.show_hud(holding)
	assert_float(screen.hold_bar.value).is_equal_approx(0.45, 1e-4)
	assert_vector(screen.give_up.get_combined_minimum_size()).is_equal(rest)


func test_raise_replaces_the_bleed_out_and_hides_giving_up() -> void:
	var screen := await _screen()
	var raised := LifeHud.Shown.new()
	raised.state = LifeHud.State.RAISE
	raised.raiser = "Olena"
	raised.raise = 0.6
	screen.show_hud(raised)
	assert_bool(screen.downed.visible).is_true()
	assert_str(screen.title_label.text).is_equal("Olena is raising you")
	for hidden: Control in [screen.bleed, screen.left_label, screen.give_up]:
		assert_bool(hidden.visible).override_failure_message(hidden.name).is_false()
	assert_bool(screen.raise_bar.visible).is_true()
	assert_bool(screen.raise_pad.visible).is_true()
	assert_float(screen.raise_bar.value).is_equal_approx(0.6, 1e-4)
	# The teammate stops: the bleed-out bar and the time return.
	screen.show_hud(_down())
	assert_bool(screen.bleed.visible).is_true()
	assert_bool(screen.raise_bar.visible).is_false()


func test_dead_shows_the_spectate_plate_only() -> void:
	var screen := await _screen()
	var dead := LifeHud.Shown.new()
	dead.state = LifeHud.State.DEAD
	dead.respawn = "0:24"
	dead.watching = "Olena"
	screen.show_hud(dead)
	assert_bool(screen.spectate.visible).is_true()
	for hidden: Control in [screen.downed, screen.give_up, screen.protect]:
		assert_bool(hidden.visible).override_failure_message(hidden.name).is_false()
	assert_str(screen.respawn_label.text).is_equal("Back in 0:24")
	assert_str(screen.watching_label.text).is_equal("Watching: Olena")
	# Nobody to watch: the time alone.
	dead.watching = ""
	screen.show_hud(dead)
	assert_bool(screen.watching_label.visible).is_false()
	assert_bool(screen.respawn_label.visible).is_true()


func test_back_counts_the_protection_down_then_hides_it() -> void:
	var screen := await _screen()
	var back := LifeHud.Shown.new()
	back.protected = 3
	screen.show_hud(back)
	assert_bool(screen.protect.visible).is_true()
	# The deck keeps the count and its unit together with a no-break space (U+00A0).
	assert_str(screen.protect_label.text).is_equal("Protected 3" + char(0xA0) + "s")
	for hidden: Control in [screen.downed, screen.give_up, screen.spectate]:
		assert_bool(hidden.visible).override_failure_message(hidden.name).is_false()
	back.protected = 0
	screen.show_hud(back)
	assert_bool(screen.protect.visible).is_false()


func test_ukrainian_puts_the_key_at_the_end_and_a_switch_rewrites_every_text() -> void:
	var screen := await _screen()
	screen.show_hud(_down())
	TranslationServer.set_locale("uk")
	screen.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(screen.title_label.text).is_equal("Тебе повалено")
	assert_str(screen.left_label.text).is_equal("Лишилось 0:07")
	assert_str(screen.before_label.text).is_equal("Щоб здатися, утримуй")
	assert_bool(screen.after_label.visible).is_false()
	assert_str(screen.give_up_text()).is_equal("Щоб здатися, утримуй F")
	var dead := LifeHud.Shown.new()
	dead.state = LifeHud.State.DEAD
	dead.respawn = "0:24"
	dead.watching = "Олена"
	screen.show_hud(dead)
	assert_str(screen.respawn_label.text).is_equal("Повернення через 0:24")
	assert_str(screen.watching_label.text).is_equal("Дивишся: Олена")
	var back := LifeHud.Shown.new()
	back.protected = 2
	screen.show_hud(back)
	assert_str(screen.protect_label.text).is_equal("Захист 2" + char(0xA0) + "с")
	var raised := LifeHud.Shown.new()
	raised.state = LifeHud.State.RAISE
	raised.raiser = "Олена"
	screen.show_hud(raised)
	assert_str(screen.title_label.text).is_equal("Тебе піднімає Олена")


func test_the_keycap_follows_a_rebind_through_the_life_view() -> void:
	# #211: the life view reads the give_up binding every frame (LifeHud.Local.read_keys).
	var screen := await _screen()
	var view := auto_free(LifeView.new()) as LifeView
	var mode := FixtureBaseMode.mode()
	view.model = ClientModel.new(mode)
	view.model.own_peer = OWN
	view.countdowns = LifeCountdowns.new(FixtureModes.player_rules(), 3.0)
	var knocked := {"peer": OWN, "position": Vector3.ZERO}
	view.model.fold(&"KnockedDown", knocked)
	view.countdowns.on_event(&"KnockedDown", knocked, OWN, 0.0)
	screen.show_hud(view.hud(0.0))
	assert_str(screen.key_label.text).is_equal("F")
	var controls := Controls.new()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	controls.bind(&"give_up", key)
	controls.apply()
	screen.show_hud(view.hud(0.0))
	assert_str(screen.key_label.text).is_equal("K")
	assert_str(screen.give_up_text()).is_equal("Hold K to give up")


func test_a_wide_key_widens_the_keycap_on_both_themes() -> void:
	# §4.7.30 rule 7: Space, Shift, Tab and Esc take the theme's `wide_min_width`; a narrow key
	# bound again takes `min_width` back.
	var screen := await _screen()
	var holder := screen.get_parent() as Control
	var view := _downed_view()
	screen.show_hud(view.hud(0.0))
	assert_float(screen.key.custom_minimum_size.x).is_equal(36.0)
	_bind_give_up(KEY_SPACE)
	screen.show_hud(view.hud(0.0))
	assert_float(screen.key.custom_minimum_size.x).is_equal(96.0)
	holder.theme = GameUi.THEME_LARGE
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(screen.key.custom_minimum_size.x).is_equal(96.0)
	_bind_give_up(KEY_K)
	screen.show_hud(view.hud(0.0))
	assert_float(screen.key.custom_minimum_size.x).is_equal(42.0)
	holder.theme = GameUi.THEME
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(screen.key.custom_minimum_size.x).is_equal(36.0)


func test_large_text_widens_the_keycap_and_keeps_every_plate_on_screen() -> void:
	var screen := await _screen()
	var holder := screen.get_parent() as Control
	TranslationServer.set_locale("uk")
	holder.theme = GameUi.THEME_LARGE
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(screen.key.custom_minimum_size).is_equal(Vector2(42, 0))
	var raised := LifeHud.Shown.new()
	raised.state = LifeHud.State.RAISE
	raised.raiser = "Олександра-Вікторія"
	for shown: LifeHud.Shown in [_down(), raised]:
		screen.show_hud(shown)
		await get_tree().process_frame
		_assert_on_screen(screen, holder)
	holder.theme = GameUi.THEME
	await get_tree().process_frame
	await get_tree().process_frame
	assert_vector(screen.key.custom_minimum_size).is_equal(Vector2(36, 0))


func test_the_ui_shows_it_in_the_round_only_with_the_shared_theme() -> void:
	var ui := auto_free(GameUi.new()) as GameUi
	assert_object(ui.life.theme).is_same(GameUi.THEME)
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.life.visible).is_true()
	ui.show_screen(GameFlow.Screen.LOBBY)
	assert_bool(ui.life.visible).is_false()


## Every visible plate and label lies inside the 1920x1080 screen, at least its minimum size.
func _assert_on_screen(screen: LifeScreen, holder: Control) -> void:
	var bounds := Rect2(Vector2.ZERO, holder.size)
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		var where := "%s %s" % [control.get_path(), rect]
		assert_bool(bounds.encloses(rect)).override_failure_message(where).is_true()
		var least := control.get_combined_minimum_size()
		(
			assert_bool(rect.size.x >= least.x - 0.5 and rect.size.y >= least.y - 0.5)
			. override_failure_message(where)
			. is_true()
		)


## The handoff's `down` sample: 7 s of 10 left, the hold at rest, the default key.
static func _down() -> LifeHud.Shown:
	var shown := LifeHud.Shown.new()
	shown.state = LifeHud.State.DOWN
	shown.bleed = 0.7
	shown.time_left = "0:07"
	shown.give_up_key = "F"
	return shown


## A LifeScreen under the shared theme at the 1920x1080 base, after its sizes were read.
## A life view whose own player is downed, at tick 0.
func _downed_view() -> LifeView:
	var view := auto_free(LifeView.new()) as LifeView
	view.model = ClientModel.new(FixtureBaseMode.mode())
	view.model.own_peer = OWN
	view.countdowns = LifeCountdowns.new(FixtureModes.player_rules(), 3.0)
	var knocked := {"peer": OWN, "position": Vector3.ZERO}
	view.model.fold(&"KnockedDown", knocked)
	view.countdowns.on_event(&"KnockedDown", knocked, OWN, 0.0)
	return view


## Binds give_up to the physical key `physical` (after_test() restores the project's bindings).
func _bind_give_up(physical: Key) -> void:
	var controls := Controls.new()
	var key := InputEventKey.new()
	key.physical_keycode = physical
	controls.bind(&"give_up", key)
	controls.apply()


func _screen() -> LifeScreen:
	var holder: Control = auto_free(Control.new())
	holder.theme = GameUi.THEME
	holder.size = Vector2(1920, 1080)
	add_child(holder)
	var screen := LifeScreen.new()
	holder.add_child(screen)
	await get_tree().process_frame
	return screen
