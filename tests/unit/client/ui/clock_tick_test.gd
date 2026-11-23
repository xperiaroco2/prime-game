extends GdUnitTestSuite
## The match clock's tick (#1674, GameUi.tick_due): once at each of its last
## UiSounds.TICK_SECONDS seconds while the HUD shows the clock (hidden for the downed and the dead),
## never at 0 (End's outro follows) and never twice for one second.


func test_it_ticks_once_at_each_of_the_last_seconds() -> void:
	var ticks: Array[int] = []
	var last := -1
	for left: int in [15, 11, 10, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 1, 0]:
		if GameUi.tick_due(true, left, last):
			ticks.append(left)
		last = left
	assert_array(ticks).contains_exactly([10, 9, 8, 7, 6, 5, 4, 3, 2, 1])


func test_no_clock_shown_no_tick() -> void:
	assert_bool(GameUi.tick_due(false, 5, 6)).is_false()
	# Shown again (raised) within the last seconds: the next second ticks.
	assert_bool(GameUi.tick_due(true, 4, 5)).is_true()
	# No clock running (seconds_left -1).
	assert_bool(GameUi.tick_due(true, -1, 3)).is_false()
