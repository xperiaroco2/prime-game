extends GdUnitTestSuite
## The round HUD under the photo camera's viewfinder (#786; ARCHITECTURE §4.7.56): while the view
## is up (HudText.Local.viewing) the crosshair and the aim line under it are hidden, the lens's
## frame being the aim; closing the view gives them back.

const C := preload("res://tests/fixtures/client/fixture_photo_client.gd")


func test_the_crosshair_hides_while_the_view_is_up() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	ui.show_screen(GameFlow.Screen.ROUND)
	var model := C.dealt()
	var mode := FixturePhotoModes.basic()
	var local := HudText.Local.new()
	ui.refresh_round(model, mode, 0.0, local)
	assert_bool(ui.hud.aiming).is_true()
	local.viewing = true
	ui.refresh_round(model, mode, 0.0, local)
	assert_bool(ui.hud.aiming).is_false()
	local.viewing = false
	ui.refresh_round(model, mode, 0.0, local)
	assert_bool(ui.hud.aiming).is_true()
	await get_tree().process_frame
