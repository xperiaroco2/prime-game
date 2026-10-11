extends GdUnitTestSuite
## The Lobby tab's presets (client/ui/lobby_presets.gd and the cards of lobby_panel.gd, #491): a
## card applies its values in one ChangeSettings, the pressed card follows the model (any other
## change deselects every card and a player reads "Custom"), Save keeps the own preset.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_a_preset_is_the_modes_defaults_with_its_own_changes_and_no_ban() -> void:
	var standard := LobbyPresets.values_of(LobbyPresets.STANDARD, _mode)
	for spec: SettingSpec in _mode.settings:
		if spec.is_number():
			assert_int(standard[spec.id] as int).is_equal(spec.default_value)
		else:
			assert_array(Array(standard[spec.id] as PackedStringArray)).is_empty()
	(
		assert_int(LobbyPresets.values_of(LobbyPresets.QUICK, _mode)[&"match_duration"] as int)
		. is_equal(5)
	)
	assert_int(LobbyPresets.values_of(LobbyPresets.NO_KNIVES, _mode)[&"knives"] as int).is_equal(0)


func test_a_mode_without_a_presets_setting_has_no_such_card_and_gets_none_of_it() -> void:
	var lean := _mode.duplicate() as GameMode
	var kept: Array[SettingSpec] = []
	for spec: SettingSpec in _mode.settings:
		if spec.id != &"knives":
			kept.append(spec)
	lean.settings = kept
	assert_array(LobbyPresets.shown(lean)).contains_exactly(
		[LobbyPresets.STANDARD, LobbyPresets.QUICK]
	)
	assert_bool(LobbyPresets.values_of(LobbyPresets.NO_KNIVES, lean).has(&"knives")).is_false()


func test_a_card_sends_every_change_in_one_change_settings() -> void:
	var panel := _panel()
	var host := Preview.fake_model(_mode, true)
	host.settings[&"knives"] = 3
	host.id_sets[&"banned_task_types"] = PackedStringArray(["delivery"])
	panel.refresh(host, -1, true)
	var one: Array = []
	var many: Array[Dictionary] = []
	panel.setting_changed.connect(func(id: StringName, value: Variant) -> void: one.append(id))
	panel.settings_changed.connect(func(values: Dictionary) -> void: many.append(values))
	panel.cards[LobbyPresets.NO_KNIVES].pressed.emit()
	assert_array(one).is_empty()
	assert_int(many.size()).is_equal(1)
	assert_int(many[0][&"knives"] as int).is_equal(0)
	assert_array(Array(many[0][&"banned_task_types"] as PackedStringArray)).is_empty()
	assert_bool(many[0].has(&"match_duration")).is_false()


func test_the_pressed_card_follows_the_model_and_any_other_change_drops_it() -> void:
	var panel := _panel()
	var host := Preview.fake_model(_mode, true)
	for id: Variant in LobbyPresets.values_of(LobbyPresets.QUICK, _mode):
		var value: Variant = LobbyPresets.values_of(LobbyPresets.QUICK, _mode)[id]
		if value is int:
			host.settings[id] = value
	panel.refresh(host, -1, true)
	assert_str(String(panel.applied_preset())).is_equal(String(LobbyPresets.QUICK))
	assert_bool(panel.cards[LobbyPresets.QUICK].button_pressed).is_true()
	assert_bool(panel.cards[LobbyPresets.STANDARD].button_pressed).is_false()
	host.settings[&"packages"] = int(host.settings[&"packages"]) + 1
	panel.refresh(host, -1, true)
	for preset: StringName in panel.cards:
		assert_bool(panel.cards[preset].button_pressed).override_failure_message(preset).is_false()
	# A player reads the preset by name: Custom now.
	var guest := Preview.fake_model(_mode, false)
	guest.settings = host.settings.duplicate()
	panel.refresh(guest, -1, false)
	assert_str(panel.preset_label.text).is_equal(
		tr("esc.lobby.preset").format({"preset": tr("preset.custom")})
	)


func test_save_keeps_the_own_preset_and_shows_its_card() -> void:
	var panel := _panel()
	var host := Preview.fake_model(_mode, true)
	host.settings[&"knives"] = 3
	panel.refresh(host, -1, true)
	var own := panel.cards[LobbyPresets.OWN].get_parent() as Control
	assert_bool(own.visible).is_false()
	var saved: Array[Dictionary] = []
	panel.preset_saved.connect(func(values: Dictionary) -> void: saved.append(values))
	panel.cards[&"save"].pressed.emit()
	assert_int(saved.size()).is_equal(1)
	assert_int(saved[0][&"knives"] as int).is_equal(3)
	assert_bool(own.visible).is_true()
	panel.refresh(host, -1, true)
	assert_str(String(panel.applied_preset())).is_equal(String(LobbyPresets.OWN))


func _panel() -> LobbyPanel:
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	add_child(panel)
	panel.set_mode(_mode)
	return panel
