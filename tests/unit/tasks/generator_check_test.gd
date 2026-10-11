extends GdUnitTestSuite
## The Generator's checks and declarations (the Generator ADR's GE6, GE10, GE14; ARCHITECTURE
## §5, §9.5): ModeCheck refuses a Generator without its parts; use_emits() names every event a use
## sends; both leak lists name every event emits() returns; and "nobody is told who switched" is
## held apart from the declarations: the keys of SwitchChanged and ButtonPressed and their wire
## rows' fields are the lists written here. Fixture values only.

const P1 := 1
const P2 := 2


func test_the_fixture_modes_pass_the_mode_check() -> void:
	assert_array(Array(ModeCheck.run(FixtureGeneratorModes.basic()).errors)).is_empty()
	assert_array(Array(ModeCheck.run(FixtureGeneratorModes.winning()).errors)).is_empty()


func test_the_mode_check_refuses_a_generator_without_its_parts() -> void:
	var mode := FixtureGeneratorModes.basic()
	var type := FixtureGeneratorModes.type_of(mode)
	type.generator = null
	type.switch = null
	type.switches = 0
	type.subtasks_setting = &""
	type.switches_rng = &""
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Generator generator has no generator station kind")
	assert_str(errors).contains("Generator generator has no switch station kind")
	assert_str(errors).contains("Generator generator has 0 switches, fewer than 1")
	assert_str(errors).contains("Generator generator has no subtasks_setting")
	assert_str(errors).contains("Generator generator has an empty RNG purpose")


func test_the_mode_check_refuses_shared_tags_and_a_kind_without_its_use() -> void:
	var mode := FixtureGeneratorModes.basic()
	var type := FixtureGeneratorModes.type_of(mode)
	type.switch.spawn_tag = &"generator"
	type.generator.actions = []
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("its two station kinds share the spawn tag generator")
	assert_str(errors).contains("station kind generator has no Interact rule with UseStation")


func test_the_subtasks_setting_must_stay_within_0_and_the_switches() -> void:
	var mode := FixtureGeneratorModes.basic()
	var spec := mode.find_setting(&"active_switches")
	spec.min_value = -1
	spec.max_value = 5
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("setting active_switches goes below 0")
	assert_str(errors).contains("setting active_switches goes up to 5, above its 4 switches")


func test_seconds_must_be_within_bounds_and_default_outside_them() -> void:
	assert_float(Generator.new().seconds).is_equal(0.0)
	assert_int(Generator.new().switches).is_equal(0)
	for seconds: float in [0.0, 601.0]:
		var mode := FixtureGeneratorModes.basic()
		FixtureGeneratorModes.type_of(mode).seconds = seconds
		var errors := "\n".join(ModeCheck.run(mode).errors)
		assert_str(errors).contains("Generator generator seconds")
	for seconds: float in [0.05, 600.0]:
		var mode := FixtureGeneratorModes.basic()
		FixtureGeneratorModes.type_of(mode).seconds = seconds
		assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_use_emits_names_every_event_a_use_sends() -> void:
	var game := FixtureGeneratorModes.in_round(FixtureGeneratorModes.basic(2), [P1, P2])
	var declared := _names(FixtureGeneratorModes.type_of(game.mode).use_emits())
	var seen: Dictionary[StringName, bool] = {}
	var button := FixtureGeneratorModes.button_of(game)
	var uses: Array[int] = [
		button,
		FixtureGeneratorModes.switch_of(game, 0),
		FixtureGeneratorModes.switch_of(game, 1),
		button,
		button,
		FixtureGeneratorModes.switch_of(game, 0),
	]
	for i in uses.size():
		var mark := game.emitted().size()
		FixtureGeneratorModes.use(game, P1, uses[i], i)
		for emitted: EmittedEvent in game.emitted().slice(mark):
			seen[emitted.event.event_name()] = true
		FixtureModes.run_ticks(game, Generator.WINDOW_TICKS)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	var names: Array[StringName] = seen.keys()
	names.sort()
	declared.sort()
	assert_array(names).is_equal(declared)


func test_both_leak_lists_name_every_event_the_generator_emits() -> void:
	for name: StringName in _names(Generator.new().emits()):
		assert_bool(LeakCheck.TASK_EVENTS.has(name)).override_failure_message(name).is_true()
		(
			assert_bool(ScenarioInvariants.TASK_EVENTS.has(name))
			. override_failure_message(name)
			. is_true()
		)


func test_nobody_is_told_who_switched() -> void:
	assert_array(SwitchChangedEvent.new(3, true).to_dict().keys()).is_equal(["station", "on"])
	assert_array(ButtonPressedEvent.new(3).to_dict().keys()).is_equal(["station"])
	var schema := WireSchema.game(false)
	assert_array(_fields(schema.row_named(&"SwitchChanged"))).is_equal(["station", "on"])
	assert_array(_fields(schema.row_named(&"ButtonPressed"))).is_equal(["station"])


func test_it_ticks_and_converts_its_time_once() -> void:
	var type := FixtureGeneratorModes.generator_type()
	assert_bool(type.has_tick()).is_true()
	var cases := {1.0: 20, 0.05: 1, 0.04: 1, 600.0: 12000}
	for seconds: float in cases:
		type.seconds = seconds
		assert_int(type.needed_ticks()).override_failure_message(str(seconds)).is_equal(
			cases[seconds]
		)


## The event names of `scripts` (each class's global name without its `Event`).
func _names(scripts: Array[Script]) -> Array[StringName]:
	var found: Array[StringName] = []
	for script: Script in scripts:
		found.append(StringName(String(script.get_global_name()).trim_suffix("Event")))
	return found


## The payload field names of `row`, in order.
func _fields(row: WireRow) -> Array[String]:
	var found: Array[String] = []
	for field: WireField in row.fields:
		if field.slot == WireField.Slot.FIELD:
			found.append(field.name)
	return found
