extends GdUnitTestSuite
## ClientPinball through ClientModel (#1398, E25): a PinballState is folded whole; clear_match
## (LoadMatch, entering the lobby) forgets the game and keeps the lobby's best score and its name.
## The snapshot's ball (#1399) is folded by tick.


func test_a_pinball_state_is_folded_and_clear_match_keeps_only_the_best() -> void:
	var model := ClientModel.new(FixturePinball.mode())
	var state := PinballStateEvent.new()
	state.game = 2
	state.player = 3
	state.left = true
	state.in_play = true
	state.score = 600
	state.balls_left = 1
	state.best = 1200
	state.best_name = "Діма"
	model.fold(&"PinballState", state.to_dict())
	assert_int(model.pinball.game).is_equal(2)
	assert_int(model.pinball.player).is_equal(3)
	assert_bool(model.pinball.left).is_true()
	assert_bool(model.pinball.right).is_false()
	assert_bool(model.pinball.in_play).is_true()
	assert_int(model.pinball.score).is_equal(600)
	assert_int(model.pinball.balls_left).is_equal(1)
	model.clear_match()
	assert_int(model.pinball.game).is_equal(0)
	assert_int(model.pinball.player).is_equal(-1)
	assert_bool(model.pinball.left).is_false()
	assert_bool(model.pinball.in_play).is_false()
	assert_int(model.pinball.score).is_equal(0)
	assert_int(model.pinball.balls_left).is_equal(0)
	assert_int(model.pinball.best).is_equal(1200)
	assert_str(model.pinball.best_name).is_equal("Діма")


func test_another_event_changes_nothing() -> void:
	var pinball := ClientPinball.new()
	pinball.fold(&"OfferMade", {"giver": 1, "target": 2})
	assert_int(pinball.player).is_equal(-1)
	assert_str(pinball.best_name).is_empty()


## The snapshot's ball (#1399): a newer snapshot's ball replaces the last, one without a ball takes
## it away, an older or equal tick changes nothing, clear_match forgets it.
func test_the_snapshots_ball_is_folded_by_tick() -> void:
	var model := ClientModel.new(FixturePinball.mode())
	var place := Vector3(0.25, 0, -0.5)
	model.fold_snapshot({"tick": 5, "ball": place, "avatars": {}})
	assert_bool(model.pinball.ball_shown).is_true()
	assert_that(model.pinball.ball).is_equal(place)
	assert_int(model.pinball.ball_tick).is_equal(5)
	model.fold_snapshot({"tick": 4, "ball": Vector3.ONE, "avatars": {}})
	model.fold_snapshot({"tick": 5, "avatars": {}})
	assert_that(model.pinball.ball).is_equal(place)
	assert_bool(model.pinball.ball_shown).is_true()
	model.fold_snapshot({"tick": 6, "avatars": {}})
	assert_bool(model.pinball.ball_shown).is_false()
	model.fold_snapshot({"tick": 7, "ball": place, "avatars": {}})
	model.clear_match()
	assert_bool(model.pinball.ball_shown).is_false()
	assert_int(model.pinball.ball_tick).is_equal(0)
