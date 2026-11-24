extends GdUnitTestSuite
## The pinball machine's display (#1400, ARCHITECTURE §4.7.63): the best score and its owner's
## name in the owner's roster colour (neutral for an owner gone or a name two members share), the
## game's score and balls while one is on, the deck keys' captions (raw until the deck has them),
## re-texted when the best is beaten.

var _display: PinballDisplay
var _model: ClientModel


func before_test() -> void:
	TranslationServer.set_locale("en")
	_display = auto_free(PinballDisplay.new())
	_model = ClientModel.new(FixturePinball.mode())
	_model.own_peer = 1
	_member(1, "Ana", 3)
	_member(2, "Bo", 5)


func after_test() -> void:
	TranslationServer.set_locale("en")


func test_the_best_and_its_owner_in_the_owner_s_colour() -> void:
	_model.pinball.best = 1200
	_model.pinball.best_name = "Bo"
	_display.show_state(_model)
	assert_str(_display.best.text).is_equal("%s 1200" % tr(&"pinball.best"))
	assert_str(_display.owner_name.text).is_equal("Bo")
	assert_object(_display.owner_name.modulate).is_equal(BodyColours.of(5))
	assert_bool(_display.game.visible).is_false()


## #1721: every line lies on the art cabinet's screen (PinballDisplay.SCREEN_M, centred on the
## Display marker), nothing over the trim under it: the worst case, a seven-digit best, a long
## wide name and a long game line, each drawn within the screen's rect.
func test_every_line_lies_inside_the_cabinet_s_screen() -> void:
	add_child(_display)
	_member(3, "WWWWWWWWWWWWWWWW", 2)
	_model.pinball.best = 9999999
	_model.pinball.best_name = "WWWWWWWWWWWWWWWW"
	_model.pinball.player = 1
	_model.pinball.in_play = true
	_model.pinball.score = 9999999
	_model.pinball.balls_left = 3
	_display.show_state(_model)
	await get_tree().process_frame
	var inner := PinballDisplay.inner_screen()
	# Inside the screen's margin: the trim stays clear.
	var screen := Rect2(-PinballDisplay.SCREEN_M * 0.5, PinballDisplay.SCREEN_M)
	assert_bool(screen.grow(-PinballDisplay.SCREEN_MARGIN_M + 0.0001).encloses(inner)).is_true()
	var lines: Array[Label3D] = [_display.best, _display.owner_name, _display.game]
	for i in lines.size():
		var line := lines[i]
		var row := _display.row_of(i)
		assert_bool(inner.grow(0.0001).encloses(row)).override_failure_message(line.name).is_true()
		if i > 0:
			# Top to bottom, no two rows overlapping.
			assert_float(row.end.y).is_less_equal(_display.row_of(i - 1).position.y + 0.0001)
		var box := line.transform * line.get_aabb()
		var drawn := Rect2(box.position.x, box.position.y, box.size.x, box.size.y)
		(
			assert_float(drawn.size.x)
			. override_failure_message("%s draws nothing" % line.name)
			. is_greater(0.0)
		)
		(
			assert_bool(row.grow(0.001).encloses(drawn))
			. override_failure_message("%s %s leaves its row %s" % [line.name, drawn, row])
			. is_true()
		)
		# Drawn smaller than the shared size only to fit its width: then it fills the row's width.
		if line.pixel_size < _display.shared_pixel - 1e-7:
			(
				assert_float(drawn.size.x)
				. override_failure_message("%s shrunk but does not fill its row" % line.name)
				. is_equal_approx(row.size.x, row.size.x * 0.03)
			)


## #1721: an everyday game keeps the lines' sizes in ratio, in both languages: all three draw at
## the one shared pixel size (none shrunk for its width), so the best's line stays the largest,
## the game's the smallest.
func test_an_everyday_game_keeps_the_sizes_in_ratio() -> void:
	add_child(_display)
	_model.pinball.best = 120
	_model.pinball.best_name = "Bo"
	_model.pinball.player = 1
	_model.pinball.in_play = true
	_model.pinball.score = 12340
	_model.pinball.balls_left = 3
	for locale: String in ["en", Languages.UKRAINIAN]:
		TranslationServer.set_locale(locale)
		_display.show_state(_model)
		await get_tree().process_frame
		var shared := _display.shared_pixel
		assert_float(shared).is_greater(0.0)
		assert_float(shared).is_less_equal(PinballDisplay.PIXEL_M)
		for line: Label3D in [_display.best, _display.owner_name, _display.game]:
			(
				assert_float(line.pixel_size)
				. override_failure_message("%s (%s): %s" % [line.name, locale, line.text])
				. is_equal_approx(shared, 1e-7)
			)
	var tall := func(line: Label3D) -> float: return line.get_aabb().size.y
	assert_float(tall.call(_display.best) as float).is_greater(
		tall.call(_display.owner_name) as float
	)
	assert_float(tall.call(_display.owner_name) as float).is_greater(
		tall.call(_display.game) as float
	)


## #1721, the engineer's (a): the lines draw in the game's UI font and colours (the UI pack's, the
## shared theme's): the best in its display style, the owner and the game in its line style, light
## on the dark screen with no outline; the owner's name keeps the owner's colour.
func test_the_lines_wear_the_ui_pack_s_font_and_colours() -> void:
	var theme := GameUi.THEME
	# The looks are the UI pack's own: a missing variation would fall back to the theme's default
	# font and a stock colour on both sides of the asserts below.
	for look: StringName in [PinballDisplay.BEST_LOOK, PinballDisplay.LINE_LOOK]:
		assert_bool(theme.has_font(&"font", look)).override_failure_message(look).is_true()
		assert_bool(theme.has_color(&"font_color", look)).override_failure_message(look).is_true()
	if not PinballDisplay.has_ui_fonts():
		# CI's Git LFS stand-in fonts map no character: the engine's fallback draws instead.
		for line: Label3D in [_display.best, _display.owner_name, _display.game]:
			assert_object(line.font).is_same(ThemeDB.fallback_font)
	else:
		assert_object(_display.best.font).is_not_same(_display.game.font)
		assert_object(_display.best.font).is_same(theme.get_font(&"font", PinballDisplay.BEST_LOOK))
	assert_object(_display.best.modulate).is_equal(
		theme.get_color(&"font_color", PinballDisplay.BEST_LOOK)
	)
	for line: Label3D in [_display.owner_name, _display.game]:
		if PinballDisplay.has_ui_fonts():
			assert_object(line.font).is_same(theme.get_font(&"font", PinballDisplay.LINE_LOOK))
	assert_object(_display.game.modulate).is_equal(
		theme.get_color(&"font_color", PinballDisplay.LINE_LOOK)
	)
	assert_object(PinballDisplay.neutral()).is_equal(
		theme.get_color(&"font_color", PinballDisplay.LINE_LOOK)
	)
	for line: Label3D in [_display.best, _display.owner_name, _display.game]:
		assert_int(line.outline_size).override_failure_message(line.name).is_equal(0)


func test_an_owner_gone_or_a_shared_name_is_neutral() -> void:
	_model.pinball.best = 300
	_model.pinball.best_name = "Cy"
	_display.show_state(_model)
	assert_str(_display.owner_name.text).is_equal("Cy")
	assert_object(_display.owner_name.modulate).is_equal(PinballDisplay.neutral())
	_member(3, "Ana", 7)
	_model.pinball.best_name = "Ana"
	_display.show_state(_model)
	assert_object(_display.owner_name.modulate).is_equal(PinballDisplay.neutral())


func test_a_new_best_re_texts_the_display() -> void:
	_model.pinball.best = 300
	_model.pinball.best_name = "Ana"
	_display.show_state(_model)
	_model.pinball.best = 450
	_model.pinball.best_name = "Bo"
	_display.show_state(_model)
	assert_str(_display.best.text).ends_with(" 450")
	assert_str(_display.owner_name.text).is_equal("Bo")
	assert_object(_display.owner_name.modulate).is_equal(BodyColours.of(5))


func test_a_game_on_shows_its_score_and_balls_left() -> void:
	_model.pinball.player = 1
	_model.pinball.in_play = true
	_model.pinball.score = 70
	_model.pinball.balls_left = 2
	_display.show_state(_model)
	assert_bool(_display.game.visible).is_true()
	assert_str(_display.game.text).is_equal(
		"%s 70   %s 2" % [tr(&"pinball.score"), tr(&"pinball.balls")]
	)
	_model.pinball.clear_match()
	_display.show_state(_model)
	assert_bool(_display.game.visible).is_false()


func test_a_seated_player_s_score_shows_before_the_launch_and_between_balls() -> void:
	_model.pinball.player = 1
	_model.pinball.in_play = false
	_model.pinball.balls_left = 3
	_display.show_state(_model)
	assert_bool(_display.game.visible).is_true()
	# Nobody seated and no ball: the line is hidden.
	_model.pinball.player = -1
	_display.show_state(_model)
	assert_bool(_display.game.visible).is_false()


func test_the_captions_are_deck_keys_shown_raw_until_the_deck_has_them() -> void:
	_display.show_state(_model)
	# The deck lacks the keys yet (requested on #150): tr() gives the key back, the number after.
	assert_str(_display.best.text).starts_with(tr(&"pinball.best"))
	assert_str(_display.best.text).ends_with(" 0")
	assert_bool(_display.best.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED).is_true()


func test_no_model_shows_nothing() -> void:
	_display.show_state(null)
	assert_bool(_display.visible).is_false()


func _member(peer: int, member_name: String, colour: int) -> void:
	var member := ClientModel.Member.new()
	member.name = member_name
	member.colour = colour
	_model.roster[peer] = member
