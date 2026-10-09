extends GdUnitTestSuite
## ModeCheck on the tutorial's host-side parts (#599, design §2.3, §2.5), on FixtureStageModes
## (no `content/`, §9.6): a row whose KnockDown without then_die enters a phase with no LifeTicks
## is a warning, not an error (the tutorial's raise_stage wants it); KnockDown's pick within the
## mode's players; PlacePlayers ordered needs no RNG purpose.


func test_a_knock_down_without_then_die_into_no_life_ticks_is_a_warning() -> void:
	var check := ModeCheck.run(FixtureStageModes.staged([FixtureStageModes.knock_down(1)]))
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).contains_exactly(
		[
			(
				"row round, next: KnockDown without then_die enters stage, which lists no"
				+ " LifeTicks: the downed stays downed for good"
			)
		]
	)


func test_no_warning_into_life_ticks_or_with_then_die() -> void:
	var into_life_ticks := FixtureStageModes.staged([], [FixtureStageModes.knock_down(1)])
	var dying := FixtureStageModes.staged([FixtureStageModes.knock_down(0, true)])
	for mode: GameMode in [into_life_ticks, dying, FixtureStageModes.staged()]:
		var check := ModeCheck.run(mode)
		assert_array(Array(check.errors)).is_empty()
		assert_array(Array(check.warnings)).is_empty()


func test_a_row_into_a_missing_phase_is_its_own_error_and_no_crash() -> void:
	var mode := FixtureStageModes.staged([FixtureStageModes.knock_down(1)])
	mode.transitions[-2].to = &"nowhere"
	var check := ModeCheck.run(mode)
	assert_str("\n".join(check.errors)).contains("nowhere")
	assert_str("\n".join(check.warnings)).not_contains("KnockDown")


func test_the_pick_must_be_able_to_name_a_player() -> void:
	# basic()'s 4 players: the host and 3 others, so pick 0 to 3.
	assert_array(Array(FixtureStageModes.knock_down(3).check(FixtureModes.basic()))).is_empty()
	for pick: int in [-1, 4]:
		var mode := FixtureStageModes.staged([FixtureStageModes.knock_down(pick)])
		var errors := "\n".join(ModeCheck.run(mode).errors)
		assert_str(errors).contains("KnockDown pick is %d, outside 0 to 3" % pick)
