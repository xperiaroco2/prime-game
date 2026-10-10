extends GdUnitTestSuite
## The tutorial's data classes in core/content/tutorial/ (docs/design/tutorial.md §3, E64; #602):
## the closed list of parts with their names, and what each part, step, lesson and the lessons
## report as unusable.


func test_the_parts_are_the_closed_list_of_the_design() -> void:
	var names: Array[StringName] = []
	for part: TutorialPart in [
		EventSeen.new(),
		ClientSeen.new(),
		OwnLife.new(),
		OtherWithin.new(),
		ItemKindIs.new(),
		TasksDone.new(),
		RequestStage.new(),
	]:
		names.append(part.part_name())
	(
		assert_array(names)
		. is_equal(
			[
				&"EventSeen",
				&"ClientSeen",
				&"OwnLife",
				&"OtherWithin",
				&"ItemKindIs",
				&"TasksDone",
				&"RequestStage",
			]
		)
	)
	assert_bool(EventSeen.new() is TutorialTrigger).is_true()
	assert_bool(ClientSeen.new() is TutorialTrigger).is_true()
	for condition: TutorialPart in [OwnLife.new(), OtherWithin.new(), ItemKindIs.new()]:
		assert_bool(condition is TutorialCondition).is_true()
	assert_bool(TasksDone.new() is TutorialCondition).is_true()
	assert_bool(RequestStage.new() is TutorialAction).is_true()
	(
		assert_array(ClientSeen.SIGNALS)
		. is_equal(
			[
				&"moved",
				&"map_opened",
				&"howto_opened",
				&"spectate_switched",
				&"voice_sent",
				&"esc_opened",
			]
		)
	)


func test_each_part_reports_its_problems() -> void:
	assert_array(EventSeen.new().problems()).has_size(1)
	assert_array(_event(&"Swapped", {"peer": EventSeen.OWN}).problems()).is_empty()
	assert_array(_event(&"Swapped", {1: 2}).problems()).has_size(1)
	assert_array(_seen(&"no_such_signal").problems()).has_size(1)
	assert_array(_seen(&"moved", 1.0).problems()).is_empty()
	assert_array(_seen(&"voice_sent", 3.0).problems()).is_empty()
	assert_array(_seen(&"moved", -1.0).problems()).has_size(1)
	assert_array(_seen(&"map_opened", 1.0).problems()).has_size(1)
	var life := OwnLife.new()
	assert_array(life.problems()).is_empty()
	life.life = &"undead"
	assert_array(life.problems()).has_size(1)
	var within := OtherWithin.new()
	assert_array(within.problems()).is_empty()
	within.metres = -1.0
	assert_array(within.problems()).has_size(1)
	var kind := ItemKindIs.new()
	assert_array(kind.problems()).has_size(1)
	kind.kind = &"package"
	assert_array(kind.problems()).is_empty()
	assert_array(TasksDone.new().problems()).is_empty()
	assert_array(RequestStage.new().problems()).is_empty()


func test_own_life_names_the_client_models_lives_in_their_order() -> void:
	var names: Array[String] = []
	for life: StringName in OwnLife.LIVES:
		names.append(String(life).to_upper())
	assert_array(names).is_equal(Array(ClientModel.Life.keys(), TYPE_STRING, &"", null))
	for i in names.size():
		assert_int(ClientModel.Life[names[i]]).is_equal(i)


func test_a_step_needs_a_title_and_something_that_completes_it() -> void:
	var step := TutorialStep.new()
	assert_array(step.problems()).has_size(2)
	step.title_key = &"tutorial.step.move.title"
	assert_array(step.problems()).has_size(1)
	step.triggers = [_seen(&"moved", 1.0)]
	assert_array(step.problems()).is_empty()
	# done_when alone completes it too (the check on entry).
	var on_entry := TutorialStep.new()
	on_entry.title_key = &"t"
	on_entry.done_when = [TasksDone.new()]
	assert_array(on_entry.problems()).is_empty()


func test_a_step_reports_its_parts_problems_and_misplaced_parts() -> void:
	var step := TutorialStep.new()
	step.title_key = &"t"
	step.triggers = [_seen(&"no_such_signal"), null]
	var problems := step.problems()
	assert_array(problems).has_size(2)
	assert_str(problems[0]).contains("unknown signal")
	assert_str(problems[1]).contains("an empty part")
	# ItemKindIs reads the fired event: never in starts_when or done_when.
	var kind := ItemKindIs.new()
	kind.kind = &"package"
	var placed := TutorialStep.new()
	placed.title_key = &"t"
	placed.triggers = [_seen(&"moved")]
	placed.conditions = [kind]
	assert_array(placed.problems()).is_empty()
	placed.starts_when = [kind]
	placed.done_when = [kind]
	assert_array(placed.problems()).has_size(2)
	placed.starts_when = []
	placed.done_when = []
	placed.keys = [&""]
	assert_array(placed.problems()).has_size(1)


func test_a_lesson_has_one_or_two_steps_and_a_list_key() -> void:
	var lesson := TutorialLesson.new()
	assert_array(lesson.problems()).has_size(2)
	lesson.list_key = &"tutorial.list.move"
	lesson.steps = [_step()]
	assert_array(lesson.problems()).is_empty()
	lesson.steps = [_step(), _step()]
	assert_array(lesson.problems()).is_empty()
	lesson.steps = [_step(), _step(), _step()]
	assert_array(lesson.problems()).has_size(1)
	lesson.steps = [null]
	assert_array(lesson.problems()).has_size(1)
	var broken := _step()
	broken.title_key = &""
	lesson.steps = [broken]
	assert_array(lesson.problems()).has_size(1)


func test_the_lessons_report_each_lessons_problems_by_number() -> void:
	var lessons := TutorialLessons.new()
	assert_array(lessons.problems()).contains_exactly(["no lessons"])
	var good := TutorialLesson.new()
	good.list_key = &"a"
	good.steps = [_step()]
	var bad := TutorialLesson.new()
	bad.list_key = &"b"
	lessons.lessons = [good, bad, null]
	var problems := lessons.problems()
	assert_array(problems).has_size(2)
	assert_str(problems[0]).starts_with("lesson 2: ")
	assert_str(problems[1]).is_equal("lesson 3 is empty")


func _event(event: StringName, fields: Dictionary) -> EventSeen:
	var part := EventSeen.new()
	part.event = event
	part.fields = fields
	return part


func _seen(signal_name: StringName, amount := 0.0) -> ClientSeen:
	var part := ClientSeen.new()
	part.signal_name = signal_name
	part.amount = amount
	return part


func _step() -> TutorialStep:
	var step := TutorialStep.new()
	step.title_key = &"t"
	step.triggers = [_seen(&"moved")]
	return step
