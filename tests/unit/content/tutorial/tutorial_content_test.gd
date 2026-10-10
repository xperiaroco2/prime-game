extends GdUnitTestSuite
## The nine lessons in content/tutorial/tutorial.tres (provisional; docs/design/tutorial.md §1, §3
## and the engineer's D29 to D36 answers; #602): they load with no problem, follow §1's table in
## order with the action each one detects, name only deck keys of client/i18n/strings.csv and
## InputMap actions, ask for a stage only as lessons 6 and 7 start, and hold no step nothing can
## complete. Loads `content/` on purpose, as the mode check does (§9.6).

const LESSONS := "res://content/tutorial/tutorial.tres"
const DECK := "res://client/i18n/strings.csv"
const TUTORIAL_MODE := "res://content/modes/tutorial_mode.tres"


func test_the_lessons_load_with_no_problem() -> void:
	var lessons := _lessons()
	assert_object(lessons).is_not_null()
	(
		assert_array(lessons.problems())
		. override_failure_message("\n".join(lessons.problems()))
		. is_empty()
	)


func test_the_nine_lessons_detect_the_actions_of_the_design() -> void:
	# §1's table, one row per step: title, how, keys, then the parts (D29 (a), D31 (a), D36 (a)).
	var expected := [
		(
			"move | move.title | - | move_forward move_left move_back move_right sprint jump"
			+ " | trigger ClientSeen moved 1"
		),
		(
			"pick_up | pick_up.title | pick_up.how | interact"
			+ " | trigger EventSeen ItemPickedUp peer=own | condition ItemKindIs package"
		),
		(
			"pick_up | put_down.title | press | put_down"
			+ " | trigger EventSeen ItemPlaced cause=put_down item=held"
		),
		"hand_belt | hand_belt.title | press | swap | trigger EventSeen Swapped peer=own",
		(
			"deliver | deliver.title | - | - | done_when TasksDone"
			+ " | trigger EventSeen PackageDelivered"
		),
		"map | map.title | press | map | trigger ClientSeen map_opened",
		"map | howto.title | howto.how | howto_glyph | trigger ClientSeen howto_opened",
		(
			"downed | downed.title | downed.how | interact | on_start RequestStage"
			+ " | trigger EventSeen Revived peer=other"
		),
		(
			"death | death.title | death.how | spectate_next | on_start RequestStage"
			+ " | trigger ClientSeen spectate_switched | trigger EventSeen Respawned peer=own"
		),
		(
			"voice | voice.title | voice.how | - | starts_when OwnLife alive"
			+ " | trigger ClientSeen voice_sent 3 | condition OtherWithin 0"
		),
		"menu | menu.title | press | ui_cancel | trigger ClientSeen esc_opened",
	]
	var rows: Array[String] = []
	for lesson: TutorialLesson in _lessons().lessons:
		for step: TutorialStep in lesson.steps:
			rows.append(_row(lesson, step))
	assert_array(rows).is_equal(expected)
	assert_str(String(_lessons().lessons[4].list_action)).is_equal("map")


func test_every_key_is_in_the_deck_and_every_action_in_the_input_map() -> void:
	var deck := _deck_keys()
	var found: Array[String] = []
	for lesson: TutorialLesson in _lessons().lessons:
		if not deck.has(String(lesson.list_key)):
			found.append("no deck key %s" % lesson.list_key)
		if not lesson.list_action.is_empty() and not InputMap.has_action(lesson.list_action):
			found.append("no action %s" % lesson.list_action)
		for step: TutorialStep in lesson.steps:
			for key: StringName in [step.title_key, step.how_key]:
				if not key.is_empty() and not deck.has(String(key)):
					found.append("no deck key %s" % key)
			for action: StringName in step.keys:
				if action != TutorialStep.HOWTO_GLYPH and not InputMap.has_action(action):
					found.append("no action %s" % action)
	assert_array(found).is_empty()


func test_only_lessons_6_and_7_ask_for_a_stage() -> void:
	var asking: Array[int] = []
	var lessons := _lessons().lessons
	for i in lessons.size():
		for step: TutorialStep in lessons[i].steps:
			for action: TutorialAction in step.on_start:
				if action is RequestStage:
					asking.append(i + 1)
	assert_array(asking).is_equal([6, 7])


func test_no_stage_request_follows_the_spectate_switch() -> void:
	# Completing a step starts the next, and a RequestStage sends NextStage: the host would learn when
	# the dead player switched targets (ARCHITECTURE §5: whom it watches never leaves its client).
	var steps: Array[TutorialStep] = []
	for lesson: TutorialLesson in _lessons().lessons:
		steps.append_array(lesson.steps)
	var switched := 0
	for i in steps.size():
		var seen_switch := false
		for trigger: TutorialTrigger in steps[i].triggers:
			var seen := trigger as ClientSeen
			seen_switch = (
				seen_switch or (seen != null and seen.signal_name == ClientSeen.SPECTATE_SWITCHED)
			)
		if not seen_switch:
			continue
		switched += 1
		if i + 1 < steps.size():
			for action: TutorialAction in steps[i + 1].on_start:
				assert_bool(action is RequestStage).is_false()
	assert_int(switched).is_equal(1)


func test_no_step_waits_for_what_nothing_can_complete() -> void:
	# Lesson 5's second step (`howto_opened`) needs a how-to card of a task the room plays (#254).
	var mode := load(TUTORIAL_MODE) as GameMode
	var carded := 0
	for type: TaskType in mode.task_types:
		if HowtoCards.of_task(type.id) != null:
			carded += 1
	for lesson: TutorialLesson in _lessons().lessons:
		for step: TutorialStep in lesson.steps:
			for trigger: TutorialTrigger in step.triggers:
				var seen := trigger as ClientSeen
				if seen != null and seen.signal_name == ClientSeen.HOWTO_OPENED:
					assert_int(carded).override_failure_message("no how-to card").is_greater(0)


## One step as a row: the list key, the title and how keys without `tutorial.step.`, the keys,
## then each part.
func _row(lesson: TutorialLesson, step: TutorialStep) -> String:
	var cells: Array[String] = [
		String(lesson.list_key).trim_prefix("tutorial.list."),
		_short(step.title_key),
		_short(step.how_key),
		" ".join(step.keys) if not step.keys.is_empty() else "-",
	]
	for condition: TutorialCondition in step.starts_when:
		cells.append("starts_when " + _part(condition))
	for action: TutorialAction in step.on_start:
		cells.append("on_start " + _part(action))
	for condition: TutorialCondition in step.done_when:
		cells.append("done_when " + _part(condition))
	for trigger: TutorialTrigger in step.triggers:
		cells.append("trigger " + _part(trigger))
	for condition: TutorialCondition in step.conditions:
		cells.append("condition " + _part(condition))
	return " | ".join(cells)


func _short(key: StringName) -> String:
	return String(key).trim_prefix("tutorial.step.") if not key.is_empty() else "-"


func _part(part: TutorialPart) -> String:
	var words: Array[String] = [String(part.part_name())]
	if part is EventSeen:
		var seen := part as EventSeen
		words.append(String(seen.event))
		var names: Array = seen.fields.keys()
		names.sort()
		for field: Variant in names:
			words.append("%s=%s" % [field, seen.fields[field]])
	elif part is ClientSeen:
		var seen := part as ClientSeen
		words.append(String(seen.signal_name))
		if seen.amount > 0.0:
			words.append(ContentPart.number(seen.amount))
	elif part is OwnLife:
		words.append(String((part as OwnLife).life))
	elif part is OtherWithin:
		words.append(ContentPart.number((part as OtherWithin).metres))
	elif part is ItemKindIs:
		words.append(String((part as ItemKindIs).kind))
	return " ".join(words)


func _lessons() -> TutorialLessons:
	return load(LESSONS) as TutorialLessons


func _deck_keys() -> Array[String]:
	var keys: Array[String] = []
	var file := FileAccess.open(DECK, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if not row.is_empty() and not row[0].is_empty():
			keys.append(row[0])
	return keys
