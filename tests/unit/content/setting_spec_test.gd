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
