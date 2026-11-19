extends GdUnitTestSuite
## SettingEquals (ARCHITECTURE §9.4; #1627): passes exactly when the match setting holds its value,
## reads no actor, and names a setting of the mode. The base mode's "time up with no humans" that it
## makes up is played whole in content_modes_test.gd.

const P1 := 1
const P2 := 2


func test_it_passes_only_on_the_settings_value() -> void:
	var game := FixtureWinModes.in_round(FixtureWinModes.basic(1), [P1, P2])
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	game.state.settings[&"dissidents"] = 0
	assert_bool(SettingEquals.of(&"dissidents", 0).passes(ctx)).is_true()
	assert_bool(SettingEquals.of(&"dissidents", 1).passes(ctx)).is_false()
	game.state.settings[&"dissidents"] = 2
	assert_bool(SettingEquals.of(&"dissidents", 0).passes(ctx)).is_false()
	assert_bool(SettingEquals.of(&"dissidents", 2).passes(ctx)).is_true()
	var negated := SettingEquals.of(&"dissidents", 0)
	negated.negate = true
	assert_bool(negated.passes(ctx)).is_true()
	assert_bool(SettingEquals.new().reads_actor_state()).is_false()


func test_it_names_a_setting_of_the_mode() -> void:
	var mode := FixtureWinModes.basic(1)
	assert_array(SettingEquals.of(&"dissidents", 0).check(mode)).is_empty()
	assert_array(SettingEquals.new().check(mode)).contains_exactly(["SettingEquals has no setting"])
	assert_array(SettingEquals.of(&"nope", 0).check(mode)).contains_exactly(
		["SettingEquals names setting nope, which the mode does not declare"]
	)
	# A value the setting can never hold is refused.
	var spec := mode.find_setting(&"dissidents")
	var over := SettingEquals.of(&"dissidents", spec.max_value + 1).check(mode)
	assert_int(over.size()).is_equal(1)
	assert_str(over[0]).contains("SettingEquals dissidents value")


func test_a_win_condition_may_name_no_side() -> void:
	# #1627: a win condition with no side ends the match with no side winning; one naming a side the
	# mode does not declare is still an error.
	var mode := FixtureWinModes.basic(1)
	var none := WinCondition.new()
	none.id = &"x"
	none.conditions = [SettingEquals.of(&"dissidents", 0)]
	assert_array(none.check(mode)).is_empty()
	none.side = &"nobody"
	assert_array(none.check(mode)).contains_exactly(
		["win condition x names side nobody, which the mode does not declare"]
	)
	# With no side its id is the only thing MatchEnded tells: it must have one.
	none.side = &""
	none.id = &""
	assert_array(none.check(mode)).contains_exactly(["a win condition with no side has no id"])
