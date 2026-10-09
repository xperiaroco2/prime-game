extends GdUnitTestSuite
## #488 rule 4, per screen: the lobby HUD, the round HUD and the life panel (downed, spectating)
## take no mouse, so the captured mouse and the keys stay the game's; the pregame takes no input.
## The connecting screen's backdrop stopping the mouse: connecting_screen_test.gd; the post game:
## end_screen_test.gd; the name plates: name_plate_test.gd.


func test_the_huds_take_no_mouse_and_no_focus() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	for screen: Control in [ui.lobby_hud, ui.hud, ui.life, ui.pregame]:
		var controls: Array[Control] = [screen]
		for node: Node in screen.find_children("*", "Control", true, false):
			controls.append(node as Control)
		for control: Control in controls:
			var where := "%s/%s" % [screen.name, screen.get_path_to(control)]
			(
				assert_int(control.mouse_filter)
				. override_failure_message("%s takes the mouse" % where)
				. is_equal(Control.MOUSE_FILTER_IGNORE)
			)
			(
				assert_int(control.focus_mode)
				. override_failure_message("%s takes the focus" % where)
				. is_equal(Control.FOCUS_NONE)
			)
			assert_bool(control is BaseButton).override_failure_message(where).is_false()
