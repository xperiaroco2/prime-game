extends GdUnitTestSuite
## ModeCheck on who can win (#1237): two win conditions with one id (MatchEnded's reason, #548)
## and a phase that checks the win conditions in a mode with none are errors; in a mode that
## checks them, a side no win condition names and a win condition whose side no role has are
## warnings. Each found on FixtureModes.basic() with one thing wrong.


func test_two_win_conditions_with_one_id_are_an_error() -> void:
	var mode := FixtureModes.basic()
	mode.win_conditions[1].id = mode.win_conditions[0].id
	assert_array(Array(ModeCheck.run(mode).errors)).contains(
		["two win conditions with the id crew"]
	)


func test_a_phase_that_checks_wins_in_a_mode_with_none_is_an_error() -> void:
	var mode := FixtureModes.basic()
	mode.win_conditions.clear()
	assert_array(Array(ModeCheck.run(mode).errors)).contains(
		["phase round checks the win conditions, but the mode has none"]
	)


func test_a_side_with_no_win_condition_is_a_warning() -> void:
	var mode := FixtureModes.basic()
	mode.win_conditions.remove_at(1)
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).contains(
		["side dissidents has no win condition: its players could never win"]
	)


func test_a_win_condition_whose_side_no_role_has_is_a_warning() -> void:
	var mode := FixtureModes.basic()
	mode.roles.remove_at(1)
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).contains(
		["win condition dissidents names side dissidents, which no role has: it wins for nobody"]
	)


func test_a_mode_where_no_phase_checks_wins_needs_no_win_condition() -> void:
	# The tutorial's shape: no phase checks the win conditions, so no side needs one.
	var mode := FixtureModes.basic()
	mode.win_conditions.clear()
	mode.find_phase(&"round").checks_wins = false
	mode.transitions.erase(mode.find_transition(&"round", Match.WON))
	var check := ModeCheck.run(mode)
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()


func test_the_basic_mode_has_no_finding_on_who_can_win() -> void:
	var check := ModeCheck.run(FixtureModes.basic())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()
