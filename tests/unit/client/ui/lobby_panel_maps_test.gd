extends GdUnitTestSuite
## The lobby's task type chips follow the map (DE16 of the delivery-by-meaning ADR, #828): the
## host's ban chips and a player's plates show only the types that play on the picked map
## (TaskType.maps; the mode's default map before a Welcome names one), and a ban on a type the
## picked map hides stays in the setting when the host toggles a shown chip. On
## FixtureMapTaskModes: `anywhere` plays on both maps, `map_only` on FixtureBaseMode.MAP alone.

const BANNED := &"banned_task_types"

var _panel: LobbyPanel
var _sent: Array[PackedStringArray] = []


func before_test() -> void:
	_sent.clear()


func test_the_chips_and_plates_show_the_picked_maps_types() -> void:
	var model := _start(FixtureMapTaskModes.mode())
	model.map = FixtureBaseMode.MAP
	_panel.refresh(model, -1, true)
	assert_bool(_chip(&"anywhere").visible).is_true()
	assert_bool(_chip(&"map_only").visible).is_true()
	assert_bool(_plate(&"map_only").visible).is_true()
	model.map = FixtureBaseMode.SMALL_MAP
	_panel.refresh(model, -1, false)
	assert_bool(_chip(&"anywhere").visible).is_true()
	assert_bool(_plate(&"anywhere").visible).is_true()
	assert_bool(_chip(&"map_only").visible).is_false()
	assert_bool(_plate(&"map_only").visible).is_false()
	# Back on the map that plays it: shown again.
	model.map = FixtureBaseMode.MAP
	_panel.refresh(model, -1, true)
	assert_bool(_chip(&"map_only").visible).is_true()


func test_before_a_map_is_known_the_chips_follow_the_modes_default_map() -> void:
	var mode := FixtureMapTaskModes.mode()
	mode.maps = PackedStringArray([FixtureBaseMode.SMALL_MAP, FixtureBaseMode.MAP])
	var model := _start(mode)
	model.map = ""
	_panel.refresh(model, -1, true)
	assert_bool(_chip(&"anywhere").visible).is_true()
	assert_bool(_chip(&"map_only").visible).is_false()


func test_a_ban_on_a_type_the_map_hides_stays_when_a_shown_chip_is_toggled() -> void:
	var model := _start(FixtureMapTaskModes.mode())
	model.map = FixtureBaseMode.SMALL_MAP
	model.id_sets[BANNED] = PackedStringArray(["map_only"])
	_panel.refresh(model, -1, true)
	_chip(&"anywhere").button_pressed = false
	_chip(&"anywhere").pressed.emit()
	assert_int(_sent.size()).is_equal(1)
	assert_array(Array(_sent[0])).contains_exactly_in_any_order(["map_only", "anywhere"])
	# Allowed again: the hidden ban still stays.
	model.id_sets[BANNED] = _sent[0]
	_panel.refresh(model, -1, true)
	_chip(&"anywhere").button_pressed = true
	_chip(&"anywhere").pressed.emit()
	assert_array(Array(_sent[1])).contains_exactly(["map_only"])


func _start(mode: GameMode) -> ClientModel:
	_panel = auto_free(LobbyPanel.new())
	add_child(_panel)
	_panel.set_mode(mode)
	_panel.setting_changed.connect(
		func(id: StringName, value: Variant) -> void:
			if id == BANNED:
				_sent.append(value as PackedStringArray)
	)
	return ClientModel.new(mode)


func _chip(task: StringName) -> Button:
	return _panel.get(&"_bans")[BANNED][task] as Button


func _plate(task: StringName) -> PanelContainer:
	return _panel.get(&"_plates")[BANNED][task] as PanelContainer
