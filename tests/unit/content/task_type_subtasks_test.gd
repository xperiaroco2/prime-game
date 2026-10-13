extends GdUnitTestSuite
## TaskType.subtasks_setting (#256's shared part, the Generator ADR's G0, #795): every task type
## names its subtasks setting in TaskType, and TaskType.check refuses it empty or going below 0,
## naming the type's class as each type's own checks do. ModeCheck checks it names a declared
## whole-number setting, as every `*_setting` property.

const BELOW := "%s %s: setting %s goes below 0"


## A task type with no class name, as a test or a mod could write.
class Nameless:
	extends TaskType

	func _init() -> void:
		description = "A nameless task."


func test_the_mode_check_refuses_a_type_without_a_subtasks_setting() -> void:
	var mode := FixtureModes.basic()
	_expect_none(mode)
	(mode.task_types[0] as TaskType).subtasks_setting = &""
	_expect(mode, "mode.task_types[0]: FixtureTaskType fixture_task has no subtasks_setting")


func test_the_mode_check_refuses_a_subtasks_setting_that_goes_below_0() -> void:
	var mode := FixtureModes.basic()
	mode.find_setting(FixtureModes.SUBTASKS_SETTING).min_value = -1
	_expect(mode, BELOW % ["FixtureTaskType", "fixture_task", FixtureModes.SUBTASKS_SETTING])
	mode.find_setting(FixtureModes.SUBTASKS_SETTING).min_value = 0
	_expect_none(mode)


func test_the_mode_check_refuses_an_undeclared_or_set_subtasks_setting() -> void:
	var mode := FixtureModes.basic()
	var type := mode.task_types[0] as TaskType
	type.subtasks_setting = &"parcels"
	_expect(
		mode,
		"mode.task_types[0].subtasks_setting names setting parcels, which the mode does not declare"
	)
	mode.settings.append(FixtureDealModes.banned_setting())
	type.subtasks_setting = &"banned_task_types"
	_expect(mode, "names setting banned_task_types, which is a set of ids, not a whole number")


func test_every_task_type_of_the_engine_gets_the_shared_check() -> void:
	var mode := GameMode.new()
	mode.settings = [FixtureModes.setting(&"count", 1, -1, 2)]
	for type: TaskType in _engine_types():
		var label := (type.get_script() as Script).get_global_name()
		type.id = &"type_a"
		type.subtasks_setting = &""
		var errors := type.check(mode)
		assert_array(Array(errors)).contains(["%s type_a has no subtasks_setting" % label])
		type.subtasks_setting = &"count"
		errors = type.check(mode)
		assert_array(Array(errors)).contains([BELOW % [label, "type_a", "count"]])
		assert_array(Array(errors)).not_contains(["%s type_a has no subtasks_setting" % label])
		mode.find_setting(&"count").min_value = 0
		assert_array(Array(type.check(mode))).not_contains([BELOW % [label, "type_a", "count"]])
		mode.find_setting(&"count").min_value = -1


func test_a_type_without_a_class_name_is_a_task_type_and_no_mode_is_no_bound() -> void:
	var nameless := Nameless.new()
	nameless.id = &"nameless"
	assert_array(Array(nameless.check(null))).contains(
		["task type nameless has no subtasks_setting"]
	)
	nameless.subtasks_setting = &"count"
	assert_array(Array(nameless.check(null))).is_empty()


## One of each task type the engine has, fresh.
func _engine_types() -> Array[TaskType]:
	return [
		Delivery.new(),
		ZoneTask.new(),
		Generator.new(),
		Cooking.new(),
		CarRepair.new(),
		PhotoTask.new(),
	]


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
