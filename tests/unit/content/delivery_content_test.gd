extends GdUnitTestSuite
## The base mode's tasks in `content/` (ARCHITECTURE §9.5; the engineer's decision of 2026-09-30,
## #79): the settings `tasks`, `banned_task_types` and Delivery's `packages` with their numbers;
## Delivery's circle (radius 1 m, height 2 m) and a palette with a colour for every package the
## `packages` setting allows, so `all_ready`'s fit check never refuses a setting for want of
## colours; and Round runs TaskTicks. Like the mode check, this test loads `content/` on purpose
## (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_task_settings_and_their_numbers() -> void:
	var mode := load(BASE_MODE) as GameMode
	var tasks := mode.find_setting(&"tasks")
	assert_bool(tasks.is_number()).is_true()
	assert_array([tasks.default_value, tasks.min_value, tasks.max_value]).is_equal([1, 1, 1])
	var banned := mode.find_setting(&"banned_task_types")
	assert_int(banned.kind).is_equal(SettingSpec.Kind.TASK_TYPES)
	var packages := mode.find_setting(&"packages")
	assert_bool(packages.is_number()).is_true()
	assert_array([packages.default_value, packages.min_value, packages.max_value]).is_equal(
		[6, 1, 10]
	)
	assert_object(mode.find_setting(&"tasks_per_player")).is_null()
	assert_object(mode.find_setting(&"subtasks_per_task")).is_null()
	assert_dict(mode.default_id_sets()).is_equal({&"banned_task_types": PackedStringArray()})


func test_the_circle_and_a_palette_for_the_most_packages() -> void:
	var mode := load(BASE_MODE) as GameMode
	var delivery := _delivery(mode)
	assert_str(delivery.subtasks_setting).is_equal("packages")
	assert_float(delivery.circle.radius_m).is_equal(1.0)
	assert_float(delivery.circle.height_m).is_equal(2.0)
	assert_int(delivery.circle.palette.size()).is_equal(10)
	var most := mode.find_setting(&"packages").max_value
	var demands := Demands.new(mode)
	delivery.add_demands({&"packages": most}, mode.max_players, demands)
	assert_dict(demands.colours).is_equal({&"circle": most})
	assert_int(demands.palettes[&"circle"]).is_greater_equal(most)


func test_round_runs_life_ticks_then_task_ticks_and_the_mode_deals_delivery() -> void:
	var mode := load(BASE_MODE) as GameMode
	var round_spec := mode.find_phase(&"round")
	assert_int(round_spec.tick_systems.size()).is_equal(2)
	assert_bool(round_spec.tick_systems[0] is LifeTicks).is_true()
	assert_bool(round_spec.tick_systems[1] is TaskTicks).is_true()
	# LifeTicks holds the Round's Respawn (M4-3): a Respawn is optional to the mode check.
	var respawn := (round_spec.tick_systems[0] as LifeTicks).respawn
	assert_object(respawn).is_not_null()
	if respawn != null:
		assert_str(String(respawn.tag)).is_equal("respawn")
		assert_str(String(respawn.rng_purpose)).is_equal("respawn")
	assert_int(mode.task_types.size()).is_equal(1)
	assert_object(_delivery(mode).package).is_same(mode.find_item_kind(&"package"))


func _delivery(mode: GameMode) -> Delivery:
	for type: TaskType in mode.task_types:
		if type is Delivery:
			return type as Delivery
	return null
