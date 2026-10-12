extends GdUnitTestSuite
## The car repair's mode check (the car repair ADR's RE14; ARCHITECTURE §9.5): ModeCheck refuses a
## CarRepair without its kinds, with a picture that is not a display kind, a kind on the `car_end`
## tag, parts that are missing, repeated, not the mode's or capped too low, a bin without its
## Cooldown or its part, a car or panel without the right HoldStation, a number out of bounds and
## a car kind wider or taller than the footprint box. Fixture values only.


func test_the_fixture_modes_pass_the_mode_check() -> void:
	assert_array(Array(ModeCheck.run(FixtureCarRepairModes.basic()).errors)).is_empty()
	assert_array(Array(ModeCheck.run(FixtureCarRepairModes.winning()).errors)).is_empty()


func test_the_mode_check_refuses_a_car_repair_without_its_parts() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	type.car = null
	type.lift_panel = null
	type.picture = null
	type.car_end_tag = &""
	type.parts = []
	type.subtasks_setting = &""
	type.parts_rng = &""
	var errors := _errors(mode)
	for label: String in ["car", "lift_panel", "picture"]:
		assert_str(errors).contains("CarRepair car_repair has no %s station kind" % label)
	assert_str(errors).contains("CarRepair car_repair has no car_end_tag")
	assert_str(errors).contains("CarRepair car_repair has no parts")
	assert_str(errors).contains("CarRepair car_repair: bin bin_spark_plug gives none of its parts")
	assert_str(errors).contains("CarRepair car_repair has no subtasks_setting")
	assert_str(errors).contains("CarRepair car_repair has an empty RNG purpose")


func test_only_the_picture_is_a_display_kind() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	type.picture.display = false
	type.car.display = true
	var errors := _errors(mode)
	assert_str(errors).contains(
		"CarRepair car_repair: station kind part_picture (picture) is not a display kind"
	)
	assert_str(errors).contains("CarRepair car_repair: station kind car (car) is a display kind")


func test_no_station_kind_stands_on_the_car_end_tag() -> void:
	var mode := FixtureCarRepairModes.basic()
	FixtureCarRepairModes.type_of(mode).lift_panel.spawn_tag = &"car_end"
	assert_str(_errors(mode)).contains(
		"CarRepair car_repair: station kind lift_panel has the car_end tag car_end"
	)


func test_each_part_once_from_one_bin_among_the_item_kinds() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	type.parts.append(type.parts[0])
	type.parts.append(FixtureCarRepairModes.part(&"gasket"))
	type.parts.append(null)
	type.bins.append(null)
	var errors := _errors(mode)
	assert_str(errors).contains("CarRepair car_repair lists the part spark_plug twice")
	assert_str(errors).contains(
		"CarRepair car_repair: part gasket is given by 0 bins, not exactly 1"
	)
	assert_str(errors).contains(
		"CarRepair car_repair: part gasket is not one of the mode's item_kinds"
	)
	assert_str(errors).contains("CarRepair car_repair has an empty part")
	assert_str(errors).contains("CarRepair car_repair has an empty bin")


func test_two_bins_of_one_part_are_refused() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	var second := FixtureCarRepairModes.bin(type.parts[1])
	second.id = &"bin_filter_2"
	second.spawn_tag = &"bin_filter_2"
	type.bins.append(second)
	assert_str(_errors(mode)).contains(
		"CarRepair car_repair: part filter is given by 2 bins, not exactly 1"
	)


func test_a_part_is_capped_at_twice_the_players_the_subtasks_and_one() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	var most := 2 * mode.max_players + FixtureCarRepairModes.MAX_PARTS + 1
	type.parts[0].max_items = most
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	type.parts[0].max_items = most - 1
	assert_str(_errors(mode)).contains(
		(
			"CarRepair car_repair: part spark_plug has max_items %d, below %d (twice the players,"
			% [most - 1, most]
		)
	)


func test_a_bin_needs_its_cooldown_and_its_part() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	var take := type.bins[0].actions[0]
	take.conditions = take.conditions.filter(func(c: Condition) -> bool: return not c is Cooldown)
	type.bins[1].actions[0].effects = []
	var errors := _errors(mode)
	assert_str(errors).contains(
		"CarRepair car_repair: bin bin_spark_plug has no Interact rule with a Cooldown"
	)
	assert_str(errors).contains("CarRepair car_repair: bin bin_filter gives none of its parts")
	assert_str(errors).contains(
		"CarRepair car_repair: part filter is given by 0 bins, not exactly 1"
	)


func test_a_cooldown_on_another_rule_than_the_give_does_not_count() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	var give: Rule = type.bins[0].actions[0]
	var cooled := give.duplicate() as Rule
	cooled.effects = []
	give.conditions = give.conditions.filter(func(c: Condition) -> bool: return not c is Cooldown)
	type.bins[0].actions = [cooled, give]
	assert_str(_errors(mode)).contains(
		"CarRepair car_repair: bin bin_spark_plug has no Interact rule with a Cooldown"
	)


func test_the_car_holds_for_a_time_and_the_panel_without_end() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	type.car.actions = [FixtureStationModes.hold_rule(FixtureStationModes.hold(0.0, true, false))]
	type.lift_panel.actions = []
	var errors := _errors(mode)
	assert_str(errors).contains(
		"CarRepair car_repair: the car's Interact rule does not end in a timed HoldStation"
	)
	(
		assert_str(errors)
		. contains(
			"CarRepair car_repair: the lift_panel's Interact rule does not end in an endless HoldStation"
		)
	)


func test_a_hold_without_station_usable_or_with_the_wrong_hit_rule_is_refused() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	var car_rule := FixtureStationModes.hold_rule(FixtureStationModes.hold(1.0, false, false))
	car_rule.conditions = car_rule.conditions.filter(
		func(c: Condition) -> bool: return not c is StationUsable
	)
	type.car.actions = [car_rule]
	type.lift_panel.actions = [FixtureStationModes.hold_rule(FixtureStationModes.hold(0.0, true))]
	var errors := _errors(mode)
	assert_str(errors).contains(
		"CarRepair car_repair: the car's Interact rule has no StationUsable"
	)
	assert_str(errors).contains("CarRepair car_repair: the car's HoldStation must stop when hit")
	assert_str(errors).contains(
		"CarRepair car_repair: the lift_panel's HoldStation must go on when hit"
	)
	assert_str(errors).not_contains("the lift_panel's Interact rule has no StationUsable")


func test_the_numbers_must_be_within_bounds_and_default_outside_them() -> void:
	var fresh := CarRepair.new()
	assert_float(fresh.rise_seconds).is_less(0.0)
	assert_float(fresh.half_width_m).is_less(CarRepair.MIN_HALF_WIDTH_M)
	assert_float(fresh.clearance_m).is_less(CarRepair.MIN_CLEARANCE_M)
	var refused: Dictionary[String, Array] = {
		"rise_seconds": [-0.05, 60.05],
		"half_width_m": [0.15, 10.05],
		"clearance_m": [0.45, 10.05],
	}
	for field: String in refused:
		for value: float in refused[field]:
			var mode := FixtureCarRepairModes.basic()
			FixtureCarRepairModes.type_of(mode).set(field, value)
			assert_str(_errors(mode)).override_failure_message("%s %s" % [field, value]).contains(
				"CarRepair car_repair %s is %s, outside" % [field, value]
			)
	var accepted: Dictionary[String, Array] = {
		"rise_seconds": [0.0, 60.0],
		"half_width_m": [1.0, 10.0],
		"clearance_m": [1.0, 10.0],
	}
	for field: String in accepted:
		for value: float in accepted[field]:
			var mode := FixtureCarRepairModes.basic()
			FixtureCarRepairModes.type_of(mode).set(field, value)
			(
				assert_array(Array(ModeCheck.run(mode).errors))
				. override_failure_message("%s %s" % [field, value])
				. is_empty()
			)


func test_the_car_kind_fits_inside_the_footprint_box() -> void:
	var mode := FixtureCarRepairModes.basic()
	var type := FixtureCarRepairModes.type_of(mode)
	type.car.radius_m = 1.5
	type.car.height_m = 1.25
	var errors := _errors(mode)
	assert_str(errors).contains("the car's radius_m 1.5 is above half_width_m 1.2")
	assert_str(errors).contains("the car's height_m 1.25 is above clearance_m 1")


func test_the_subtasks_setting_never_goes_below_0() -> void:
	var mode := FixtureCarRepairModes.basic()
	mode.find_setting(&"car_parts").min_value = -1
	assert_str(_errors(mode)).contains("CarRepair car_repair: setting car_parts goes below 0")


## Every error ModeCheck finds in `mode`, one per line.
func _errors(mode: GameMode) -> String:
	return "\n".join(ModeCheck.run(mode).errors)
