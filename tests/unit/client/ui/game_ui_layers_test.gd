extends GdUnitTestSuite
## GameUi's canvas layers (#656): every black screen on one shared layer, 6 as prime-game-ui
## `ui-0.4.0`'s layer table says, the other screens under it, and the Esc menu above it (the
## engineer's answer (b) on #656), so Esc over a hung loading opens a menu the player sees.

const S := GameFlow.Screen


func test_the_black_screens_share_layer_6_over_the_others_and_under_the_esc_menu() -> void:
	var ui := _ui()
	assert_int(ui.black.layer).is_equal(6)
	assert_int(GameUi.BLACK_LAYER).is_equal(6)
	# Connecting, failure and loading are one screen; the pregame over it, the post game on top.
	assert_array(ui.black.get_children()).is_equal([ui.connecting, ui.pregame, ui.end])
	for under: Control in [ui.plates, ui.menu, ui.lobby_hud, ui.hud, ui.life, ui.tutorial, ui.map]:
		assert_object(under.get_parent()).override_failure_message(under.name).is_same(ui)
		assert_int(_layer(under)).override_failure_message(under.name).is_less(ui.black.layer)
	assert_object(ui.esc.get_parent()).is_same(ui.above)
	assert_int(_layer(ui.esc)).is_greater(ui.black.layer)
	# Every screen is in screens(), each once.
	var all := ui.screens()
	assert_int(all.size()).is_equal(11)
	for each: Control in [ui.connecting, ui.pregame, ui.end, ui.esc, ui.hud, ui.map]:
		assert_int(all.count(each)).override_failure_message(each.name).is_equal(1)


func test_esc_over_each_black_screen_shows_the_menu_above_it() -> void:
	var ui := _ui()
	var black: Dictionary[S, Control] = {
		S.LOADING: ui.connecting, S.PREGAME: ui.pregame, S.END: ui.end
	}
	for which: S in black:
		ui.show_screen(which)
		ui.open_esc(false, null)
		var shown := black[which]
		var label := str(S.find_key(which))
		assert_bool(shown.visible).override_failure_message(label).is_true()
		assert_bool(ui.esc_open()).override_failure_message(label).is_true()
		assert_bool(ui.esc.visible).override_failure_message(label).is_true()
		assert_int(_layer(ui.esc)).override_failure_message(label).is_greater(_layer(shown))
		assert_str(String(ui.overlays.top())).override_failure_message(label).is_equal("esc_menu")
		# Esc again is the menu's Resume: the black screen stays.
		assert_str(String(ui.overlays.close_top())).is_equal("esc_menu")
		assert_bool(ui.esc_open()).override_failure_message(label).is_false()
		assert_bool(shown.visible).override_failure_message(label).is_true()


## #726's rule stands over the black layer: a new screen closes a menu opened over another.
func test_a_new_screen_closes_the_menu_opened_over_loading() -> void:
	var ui := _ui()
	ui.show_screen(S.LOADING)
	ui.open_esc(false, null)
	assert_bool(ui.close_esc_left(S.LOADING)).is_false()
	assert_bool(ui.esc_open()).is_true()
	ui.show_screen(S.PREGAME)
	assert_bool(ui.close_esc_left(S.PREGAME)).is_true()
	assert_bool(ui.esc_open()).is_false()


## The tutorial's invite and lesson plates (#492) stay on the Ui layer, the table's HUD layer:
## after the life plates, under the map, and under the Esc menu on the layer above. The invite
## still takes the focus there, and Esc on it is its Skip, not the menu.
func test_the_tutorial_stays_on_the_ui_layer_its_invite_focused_under_the_esc_menu() -> void:
	var ui := _ui()
	var order := ui.get_children()
	assert_int(order.find(ui.tutorial)).is_greater(order.find(ui.life))
	assert_int(order.find(ui.tutorial)).is_less(order.find(ui.map))
	ui.set_tutorial(true)
	ui.show_screen(S.ROUND)
	ui.tutorial.open_invite()
	await get_tree().process_frame
	assert_bool(ui.tutorial.visible).is_true()
	assert_bool(ui.tutorial.invite_shown()).is_true()
	assert_bool(ui.tutorial.start_button.has_focus()).is_true()
	assert_str(String(ui.overlays.top())).is_equal("tutorial_invite")
	ui.open_esc(false, null)
	assert_bool(ui.esc.visible).is_true()
	assert_int(_layer(ui.esc)).is_greater(_layer(ui.tutorial))
	ui.close_esc()
	ui.set_tutorial(false)


func test_a_control_added_to_a_layer_later_gets_the_shared_theme() -> void:
	var ui := _ui()
	var late := Label.new()
	ui.above.add_child(late)
	assert_object(late.theme).is_same(GameUi.THEME)
	ui.set_large_text(true)
	assert_object(late.theme).is_same(GameUi.THEME_LARGE)
	assert_object(ui.end.theme).is_same(GameUi.THEME_LARGE)
	assert_object(ui.esc.theme).is_same(GameUi.THEME_LARGE)


func _ui() -> GameUi:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	return ui


## The layer `control` draws on: its parent CanvasLayer's.
func _layer(control: Control) -> int:
	return (control.get_parent() as CanvasLayer).layer
