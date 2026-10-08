extends GdUnitTestSuite
## ToyBar's health colour (#289; prime-game-ui spec §5): the step is the nearest of 21
## (`floor(hp * 20 + 0.5)`, clamped), the fill takes that stop's colour from the theme as its
## `self_modulate`, the stamina fill keeps its own, and all 21 stops exist in both themes.


func test_the_step_is_the_nearest_stop() -> void:
	assert_int(ToyBar.step_of(0.22)).is_equal(4)
	assert_int(ToyBar.step_of(0.8)).is_equal(16)
	assert_int(ToyBar.step_of(1.0)).is_equal(20)
	# Rounds, not floors: 0.23 x 20 = 4.6.
	assert_int(ToyBar.step_of(0.23)).is_equal(5)
	assert_int(ToyBar.step_of(0.025)).is_equal(1)
	assert_int(ToyBar.step_of(0.0)).is_equal(0)
	assert_int(ToyBar.step_of(-1.0)).is_equal(0)
	assert_int(ToyBar.step_of(2.0)).is_equal(20)


func test_all_21_stops_exist_in_both_themes() -> void:
	for theme: Theme in [GameUi.THEME, GameUi.THEME_LARGE]:
		for step in 21:
			var stop := "ramp_stop_%02d" % step
			(
				assert_bool(theme.has_color(stop, ToyBar.HEALTH))
				. override_failure_message(stop)
				. is_true()
			)
		assert_bool(theme.has_color("ramp_stop_21", ToyBar.HEALTH)).is_false()


func test_the_health_fill_takes_its_stops_colour() -> void:
	var stage: Control = auto_free(Control.new())
	stage.theme = GameUi.THEME
	add_child(stage)
	var bar := ToyBar.new()
	bar.custom_minimum_size.x = 200
	stage.add_child(bar)
	await get_tree().process_frame
	# The track's height from the theme; the length stays the caller's.
	assert_float(bar.custom_minimum_size.x).is_equal(200.0)
	assert_bool(bar.fill.show_percentage).is_false()
	assert_str(str(bar.theme_type_variation)).is_equal("ToyBarTrack")
	assert_float(bar.custom_minimum_size.y).is_equal(16.0)
	for each: Array in [[0.22, "ramp_stop_04"], [0.8, "ramp_stop_16"], [1.0, "ramp_stop_20"]]:
		var hp: float = each[0]
		var stop: StringName = each[1]
		bar.set_fraction(hp)
		assert_that(bar.fill.self_modulate).is_equal(GameUi.THEME.get_color(stop, ToyBar.HEALTH))
	assert_float(bar.fill.value).is_equal(1.0)


func test_the_stamina_fill_keeps_its_colour() -> void:
	var stage: Control = auto_free(Control.new())
	stage.theme = GameUi.THEME
	add_child(stage)
	var bar := ToyBar.new(ToyBar.STAMINA)
	stage.add_child(bar)
	bar.set_fraction(0.18)
	assert_that(bar.fill.self_modulate).is_equal(Color.WHITE)
	assert_float(bar.fill.value).is_equal(0.18)
