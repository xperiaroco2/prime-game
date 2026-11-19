extends GdUnitTestSuite
## The lobby HUD over the pinball's close-up (#1400; the engineer's M8 review, #1095 c7021998428,
## answer 7; ARCHITECTURE §4.7.47): GameUi.refresh_round on the lobby screen hands
## HudText.Local.close_up to LobbyHud.set_close_up, so only the mic shows while the view is up.

const MODE := "res://content/modes/base_mode.tres"


func test_the_lobby_hud_shows_only_the_mic_while_the_close_up_is_up() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	ui.show_screen(GameFlow.Screen.LOBBY)
	var mode := load(MODE) as GameMode
	var model := ClientModel.new(mode)
	var local := HudText.Local.new()
	ui.refresh_round(model, mode, 0.0, local)
	assert_bool(ui.lobby_hud.close_up_shown()).is_false()
	assert_bool(ui.lobby_hud.cross.visible).is_true()
	local.close_up = true
	ui.refresh_round(model, mode, 0.0, local)
	assert_bool(ui.lobby_hud.close_up_shown()).is_true()
	assert_bool(ui.lobby_hud.cross.visible).is_false()
	assert_bool(ui.lobby_hud.mic.visible).is_true()
	local.close_up = false
	ui.refresh_round(model, mode, 0.0, local)
	assert_bool(ui.lobby_hud.cross.visible).is_true()
	await get_tree().process_frame
