extends GdUnitTestSuite
## The pinball in the bots (#1510; ARCHITECTURE §4.6, §7.1.22, §9.7): the cross-bot ball check
## (LeakCheck.check_ball) on hand-built views, each planted difference failing it.

const AT := Vector3(0.25, 0.0, -0.5)


func test_the_same_ball_or_none_in_every_view_passes() -> void:
	var views := _views({10: AT, 11: null}, {10: AT, 11: null, 12: AT})
	assert_array(Array(LeakCheck.check_ball(views))).is_empty()
	# Tick 10 alone holds a ball both views decoded; tick 12 is one view's.
	assert_int(LeakCheck.shared_ball_ticks(views)).is_equal(1)


func test_another_ball_on_a_shared_tick_fails() -> void:
	var views := _views({10: AT, 11: AT}, {10: AT, 11: AT + Vector3(1, 0, 0)})
	var found := LeakCheck.check_ball(views)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("leak: bot 1 and bot 2 decoded another ball at tick 11")


func test_a_ball_one_view_has_and_another_lacks_on_a_shared_tick_fails() -> void:
	var found := LeakCheck.check_ball(_views({10: AT}, {10: null}))
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("decoded another ball at tick 10")
	found = LeakCheck.check_ball(_views({10: null}, {10: AT}))
	assert_int(found.size()).is_equal(1)


func test_a_tick_only_one_view_holds_compares_nothing() -> void:
	var views := _views({10: AT}, {11: AT + Vector3(1, 0, 0)})
	assert_array(Array(LeakCheck.check_ball(views))).is_empty()
	assert_int(LeakCheck.shared_ball_ticks(views)).is_equal(0)


func test_many_ticks_with_another_ball_are_listed_up_to_the_cap() -> void:
	var mine: Dictionary[int, Variant] = {}
	var theirs: Dictionary[int, Variant] = {}
	for at_tick in 20:
		mine[at_tick] = AT
		theirs[at_tick] = AT + Vector3(0, 0, 1)
	var found := LeakCheck.check_ball(_views(mine, theirs))
	assert_int(found.size()).is_equal(LeakCheck.MAX_LISTED + 1)
	assert_str(found[found.size() - 1]).contains("and %d more" % (20 - LeakCheck.MAX_LISTED))


## Two views, bot 1's and bot 2's: tick -> the ball decoded (null: a snapshot with no ball).
static func _views(first: Dictionary, second: Dictionary) -> Dictionary[String, DecodedView]:
	var views: Dictionary[String, DecodedView] = {}
	views["bot 1"] = _view(first)
	views["bot 2"] = _view(second)
	return views


static func _view(balls: Dictionary) -> DecodedView:
	var view := DecodedView.new()
	for at_tick: int in balls:
		var snapshot := {"tick": at_tick, "avatars": {}}
		if balls[at_tick] != null:
			snapshot["ball"] = balls[at_tick]
		view.snapshots[at_tick] = snapshot
	return view
