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


func test_an_owner_gone_or_a_shared_name_is_neutral() -> void:
	_model.pinball.best = 300
	_model.pinball.best_name = "Cy"
	_display.show_state(_model)
	assert_str(_display.owner_name.text).is_equal("Cy")
	assert_object(_display.owner_name.modulate).is_equal(PinballDisplay.NEUTRAL)
	_member(3, "Ana", 7)
	_model.pinball.best_name = "Ana"
	_display.show_state(_model)
	assert_object(_display.owner_name.modulate).is_equal(PinballDisplay.NEUTRAL)


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
