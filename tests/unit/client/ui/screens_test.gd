extends GdUnitTestSuite
## The screens' texts and controls (client/ui/, ARCHITECTURE §4.7), from a ClientModel and the
## client's own mode only. How they look: the `shot`s of client/dev/*_preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"


func test_the_roster_names_the_host_the_own_player_and_who_is_ready() -> void:
	var mode := load(MODE) as GameMode
	var model := Preview.fake_model(mode, false)
	assert_str(LobbyPanel.roster_text(model)).is_equal(
		"Player1 (host)  ready\nPlayer2 (you)  ready\nPlayer3  not ready"
	)


func test_the_lobby_panel_shows_the_settings_to_the_host_only_and_sends_one_setting() -> void:
	var mode := load(MODE) as GameMode
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	# A Range emits value_changed only inside the tree.
	add_child(panel)
	panel.set_mode(mode)
	var sent: Array = []
	panel.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	panel.refresh(Preview.fake_model(mode, false), -1)
	assert_bool(panel.settings_box.visible).is_false()
	panel.refresh(Preview.fake_model(mode, true), -1)
	assert_bool(panel.settings_box.visible).is_true()
	assert_str(panel.shortfalls_label.text).contains("4 to 10")
	assert_str(panel.countdown_label.text).is_equal("Waiting for everyone")
	var boxes := panel.settings_box.find_children("*", "SpinBox", true, false)
	assert_int(boxes.size()).is_equal(5)
	(boxes[0] as SpinBox).value = 3
	assert_array(sent).is_equal([[&"match_duration", 3]])


func test_the_end_screen_names_the_side_by_its_display_name_only() -> void:
	var mode := load(MODE) as GameMode
	assert_str(EndScreen.winner_text(&"crew", mode)).is_equal(
		"The %s won" % mode.find_side(&"crew").display_name
	)
	assert_str(EndScreen.winner_text(&"", mode)).is_equal("The match is over")
