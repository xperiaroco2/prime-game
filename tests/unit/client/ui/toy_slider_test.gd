extends GdUnitTestSuite
## ToySlider (#289): the code-drawn focus ring shows for keyboard or gamepad focus only, from the
## theme's ToySlider `focus` StyleBox.


func test_the_ring_shows_for_visible_focus_only() -> void:
	var stage: Control = auto_free(Control.new())
	stage.theme = GameUi.THEME
	add_child(stage)
	var slider := ToySlider.new()
	stage.add_child(slider)
	assert_bool(slider.shows_ring()).is_false()
	slider.grab_focus()
	assert_bool(slider.shows_ring()).is_true()
	slider.release_focus()
	assert_bool(slider.shows_ring()).is_false()
	# Focus the mouse gives is hidden: no ring.
	slider.grab_focus(true)
	assert_bool(slider.has_focus()).is_true()
	assert_bool(slider.shows_ring()).is_false()
	assert_object(slider.get_theme_stylebox(&"focus")).is_same(
		GameUi.THEME.get_stylebox(&"focus", &"ToySlider")
	)
