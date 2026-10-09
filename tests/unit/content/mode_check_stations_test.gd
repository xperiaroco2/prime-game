extends GdUnitTestSuite
## ModeCheck's station kinds and ticking task types (ZE3 of the zone task ADR, ARCHITECTURE §9.1):
## two station kinds of the mode's task types with one id or one spawn tag are refused, one kind
## held by two task types too; a task type that ticks where no phase lists TaskTicks is refused.
## Two Delivery types stand in for any two task types holding station kinds.


func test_station_kinds_with_their_own_ids_and_tags_pass() -> void:
	_expect_none(_two_deliveries(&"circle_b", &"circle_b"))


func test_two_station_kinds_with_one_id_are_refused() -> void:
	_expect(
		_two_deliveries(&"circle", &"circle_b"),
		(
			"mode.task_types[0].circle and mode.task_types[1].circle:"
			+ " two station kinds with the id circle"
		)
	)


func test_two_station_kinds_with_one_spawn_tag_are_refused() -> void:
	_expect(
		_two_deliveries(&"circle_b", &"circle"),
		"station kinds circle and circle_b share spawn tag circle"
	)


func test_one_station_kind_held_by_two_task_types_is_refused() -> void:
	var mode := _two_deliveries(&"circle_b", &"circle_b")
	var second := mode.task_types[1] as Delivery
	second.circle = FixtureDeliveryModes.delivery_of(mode).circle
	_expect(
		mode,
		"mode.task_types[0].circle and mode.task_types[1].circle hold one station kind, circle"
	)


func test_a_ticking_task_type_needs_a_phase_that_lists_task_ticks() -> void:
	var mode := FixtureModes.basic()
	mode.task_types = [FixtureTaskType.new(), FixtureTickingTaskType.of(&"ticking")]
	_expect(mode, "task type ticking ticks, but no phase lists TaskTicks: it would never run")
	mode.find_phase(&"end").tick_systems = [TaskTicks.new()]
	_expect_none(mode)


func test_task_ticks_without_a_ticking_task_type_and_neither_pass() -> void:
	var mode := FixtureModes.basic()
	_expect_none(mode)
	mode.find_phase(&"round").tick_systems.append(TaskTicks.new())
	_expect_none(mode)


## Delivery's fixture mode with a second Delivery, `delivery_b`, of its own packages setting, whose
## circle kind has the id `circle_id` and the spawn tag `tag`.
func _two_deliveries(circle_id: StringName, tag: StringName) -> GameMode:
	var mode := FixtureDeliveryModes.basic()
	mode.settings.append(FixtureModes.setting(&"packages_b", 1, 0, 12))
	var second := FixtureDeliveryModes.delivery(mode.find_item_kind(&"package"))
	second.id = &"delivery_b"
	second.subtasks_setting = &"packages_b"
	second.circle.id = circle_id
	second.circle.spawn_tag = tag
	mode.task_types.append(second)
	return mode


func _expect(mode: GameMode, fragment: String) -> void:
	var errors := ModeCheck.run(mode).errors
	var found := false
	for error: String in errors:
		found = found or error.contains(fragment)
	(
		assert_bool(found)
		. override_failure_message("no error contains '%s' in %s" % [fragment, errors])
		. is_true()
	)


func _expect_none(mode: GameMode) -> void:
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
