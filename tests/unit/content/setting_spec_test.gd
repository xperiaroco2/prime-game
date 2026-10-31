extends GdUnitTestSuite
## SettingSpec's two kinds (ARCHITECTURE §9.1; #79): a whole number with bounds, and a set of the
## mode's task type ids (the host's bans), whose default is the empty set and which has no
## numbers.


func test_a_set_of_task_types_has_no_numbers_and_needs_task_types() -> void:
	var mode := GameMode.new()
	var spec := FixtureDealModes.banned_setting()
	assert_array(Array(spec.check(mode))).is_equal(
		["setting banned_task_types is a set of task types, but the mode has none"]
	)
	mode.task_types = [FixtureTaskType.new()]
	assert_array(Array(spec.check(mode))).is_empty()
	spec.max_value = 3
	assert_array(Array(spec.check(mode))).is_equal(
		["setting banned_task_types is a set of task types and has no numbers"]
	)


func test_the_defaults_split_by_kind() -> void:
	var mode := GameMode.new()
	mode.task_types = [FixtureTaskType.new()]
	mode.settings = [FixtureModes.setting(&"knives", 2, 0, 5), FixtureDealModes.banned_setting()]
	assert_dict(mode.default_settings()).is_equal({&"knives": 2})
	assert_dict(mode.default_id_sets()).is_equal({&"banned_task_types": PackedStringArray()})
	assert_bool(mode.find_setting(&"knives").is_number()).is_true()
	assert_bool(mode.find_setting(&"banned_task_types").is_number()).is_false()
	assert_object(mode.find_task_type(&"fixture_task")).is_same(mode.task_types[0])
	assert_object(mode.find_task_type(&"other")).is_null()


func test_a_default_can_follow_the_player_count() -> void:
	# The default humans by player count (#1492): the entry with the highest key at or below the
	# players present; fewer than the lowest key, or no table, keep default_value.
	var spec := FixtureModes.setting(&"dissidents", 1, 0, 9)
	var plain: Array[int] = []
	for players in range(1, 13):
		plain.append(spec.default_for(players))
	assert_array(plain).is_equal([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	spec.defaults_by_players = {4: 1, 6: 2, 9: 3}
	var followed: Array[int] = []
	for players in range(1, 13):
		followed.append(spec.default_for(players))
	assert_array(followed).is_equal([1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3])
	var low := FixtureModes.setting(&"knives", 0, 0, 5)
	low.defaults_by_players = {3: 2}
	assert_int(low.default_for(2)).is_equal(0)
	assert_int(low.default_for(3)).is_equal(2)


func test_a_player_count_table_is_checked() -> void:
	var mode := GameMode.new()
	mode.max_players = 10
	var spec := FixtureModes.setting(&"dissidents", 1, 0, 9)
	spec.defaults_by_players = {4: 1, 6: 2, 9: 3}
	assert_array(Array(spec.check(mode))).is_empty()
	spec.defaults_by_players = {0: 1, 6: 12, 11: 3}
	(
		assert_array(Array(spec.check(mode)))
		. is_equal(
			[
				"setting dissidents: defaults_by_players key 0 is below 1 player",
				"setting dissidents defaults_by_players[6] is 12, outside 0 to 9",
				"setting dissidents: defaults_by_players key 11 is above max_players 10",
			]
		)
	)
	var banned := FixtureDealModes.banned_setting()
	mode.task_types = [FixtureTaskType.new()]
	banned.defaults_by_players = {4: 1}
	assert_array(Array(banned.check(mode))).is_equal(
		["setting banned_task_types is a set of task types and has no numbers"]
	)
