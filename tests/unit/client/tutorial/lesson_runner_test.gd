extends GdUnitTestSuite
## The lesson runner (client/tutorial/lesson_runner.gd, docs/design/tutorial.md §3; #602) fed by
## hand: hand-built lessons over a real ClientModel of the tutorial mode, each event folded into
## the model before the runner sees it, as ClientSession does. Every trigger and condition, the
## step flow (starts_when, on_start, done_when, two steps), and the end after the Esc menu closes.

const MODE := "res://content/modes/tutorial_mode.tres"
const OWN := 1
const TWO := 2
const THREE := 3
## In no roster.
const STRANGER := 4
const PACKAGE := 10
const KNIFE := 11
## The tutorial mode's voice radius in the lesson phases (RoundVoice living_m).
const RADIUS := 8.0

var _model: ClientModel
var _runner: LessonRunner
## Signal name -> how often the runner emitted it.
var _emitted: Dictionary[StringName, int] = {}


func before_test() -> void:
	_model = ClientModel.new(load(MODE) as GameMode)
	_model.own_peer = OWN
	for peer: int in [OWN, TWO, THREE]:
		_model.roster[peer] = ClientModel.Member.new()
	_model.phase = &"lessons"
	_fold(&"ItemSpawned", {"item": PACKAGE, "kind": &"package", "position": Vector3.ZERO})
	_fold(&"ItemSpawned", {"item": KNIFE, "kind": &"knife", "position": Vector3.ZERO})
	_emitted = {&"changed": 0, &"next_stage_requested": 0, &"finished": 0}


func test_event_seen_matches_name_fields_and_the_own_and_other_markers() -> void:
	_play([_lesson([_step([_event(&"Swapped", {"peer": EventSeen.OWN})])]), _lesson([_any()])])
	_event_in(&"Swapped", {"peer": TWO})
	_event_in(&"Revived", {"peer": OWN})
	assert_int(_runner.lesson()).is_equal(1)
	_event_in(&"Swapped", {"peer": OWN})
	assert_int(_runner.lesson()).is_equal(2)
	assert_bool(_runner.is_done(1)).is_true()
	# OTHER: any peer but the own; a plain value matches equal, a name as text.
	_play([_lesson([_step([_event(&"Revived", {"peer": EventSeen.OTHER})])]), _lesson([_any()])])
	_event_in(&"Revived", {"peer": OWN})
	assert_int(_runner.lesson()).is_equal(1)
	_event_in(&"Revived", {"peer": 0})
	assert_int(_runner.lesson()).is_equal(1)
	_event_in(&"Revived", {"peer": THREE})
	assert_int(_runner.lesson()).is_equal(2)
	_play([_lesson([_step([_event(&"ItemPlaced", {"cause": &"put_down"})])]), _lesson([_any()])])
	_event_in(&"ItemPlaced", {"item": KNIFE, "position": Vector3.ZERO, "cause": &"swap"})
	_event_in(&"ItemPlaced", {"item": KNIFE, "position": Vector3.ZERO})
	assert_int(_runner.lesson()).is_equal(1)
	_event_in(&"ItemPlaced", {"item": KNIFE, "position": Vector3.ZERO, "cause": "put_down"})
	assert_int(_runner.lesson()).is_equal(2)


func test_held_is_the_item_in_the_own_hand_as_the_step_started() -> void:
	var picked := _step([_event(&"ItemPickedUp", {"peer": EventSeen.OWN})], [_kind(&"package")])
	var placed := _step([_event(&"ItemPlaced", {"item": EventSeen.HELD, "cause": &"put_down"})])
	_play([_lesson([picked, placed]), _lesson([_any()])])
	# The knife is no package: that firing is ignored.
	_event_in(&"ItemPickedUp", {"peer": OWN, "item": KNIFE})
	assert_int(_runner.step()).is_equal(1)
	_event_in(&"ItemPlaced", {"item": KNIFE, "position": Vector3.ZERO, "cause": &"put_down"})
	# Another player's package pickup does not count either.
	_event_in(&"ItemPickedUp", {"peer": TWO, "item": PACKAGE})
	_event_in(&"ItemPlaced", {"item": PACKAGE, "position": Vector3.ZERO, "cause": &"put_down"})
	assert_int(_runner.step()).is_equal(1)
	_event_in(&"ItemPickedUp", {"peer": OWN, "item": PACKAGE})
	assert_int(_runner.lesson()).is_equal(1)
	assert_int(_runner.step()).is_equal(2)
	assert_str(String(_runner.current_step().title_key)).is_equal("step2")
	# Another item put down is not the held one; the held one put down by a swap is no put_down.
	_event_in(&"ItemPlaced", {"item": KNIFE, "position": Vector3.ZERO, "cause": &"put_down"})
	_event_in(&"ItemPlaced", {"item": PACKAGE, "position": Vector3.ZERO, "cause": &"swap"})
	assert_int(_runner.step()).is_equal(2)
	_event_in(&"ItemPickedUp", {"peer": OWN, "item": PACKAGE})
	_event_in(&"ItemPlaced", {"item": PACKAGE, "position": Vector3.ZERO, "cause": &"put_down"})
	assert_int(_runner.lesson()).is_equal(2)
	assert_bool(_runner.is_done(1)).is_true()


func test_an_event_before_the_start_or_an_unknown_item_never_counts() -> void:
	_build([_lesson([_step([_event(&"Swapped", {"peer": EventSeen.OWN})])]), _lesson([_any()])])
	_event_in(&"Swapped", {"peer": OWN})
	assert_int(_runner.lesson()).is_equal(0)
	_runner.start()
	assert_int(_runner.lesson()).is_equal(1)
	_play(
		[
			_lesson(
				[_step([_event(&"ItemPickedUp", {"peer": EventSeen.OWN})], [_kind(&"package")])]
			),
			_lesson([_any()]),
		]
	)
	_runner.on_event(&"ItemPickedUp", {"peer": OWN, "item": 999})
	_runner.on_event(&"ItemPickedUp", {"peer": OWN})
	assert_int(_runner.lesson()).is_equal(1)


func test_moved_counts_the_ticks_of_the_claims_that_moved_itself() -> void:
	_play([_lesson([_step([_seen(&"moved", 1.0)])]), _lesson([_any()])])
	_runner.on_claim(Ticks.RATE, false)
	_runner.on_claim(Ticks.RATE - 1, true)
	assert_int(_runner.lesson()).is_equal(1)
	_runner.on_claim(1, true)
	assert_int(_runner.lesson()).is_equal(2)


func test_each_client_signal_completes_its_step() -> void:
	for signal_name: StringName in [
		&"map_opened", &"howto_opened", &"spectate_switched", &"voice_sent", &"esc_opened"
	]:
		_play([_lesson([_step([_seen(signal_name)])]), _lesson([_any()])])
		for other: StringName in ClientSeen.SIGNALS:
			if other != signal_name:
				_runner.see(other)
		assert_int(_runner.lesson()).override_failure_message(signal_name).is_equal(1)
		_runner.see(signal_name)
		assert_int(_runner.lesson()).override_failure_message(signal_name).is_equal(2)


func test_the_first_trigger_wins_and_the_other_does_nothing_after() -> void:
	var either := _step(
		[_seen(&"spectate_switched"), _event(&"Respawned", {"peer": EventSeen.OWN})]
	)
	_play([_lesson([either]), _lesson([_step([_seen(&"map_opened")])]), _lesson([_any()])])
	_event_in(&"Respawned", {"peer": OWN, "position": Vector3.ZERO})
	assert_int(_runner.lesson()).is_equal(2)
	_runner.see(&"spectate_switched")
	assert_int(_runner.lesson()).is_equal(2)
	_play([_lesson([either]), _lesson([_any()])])
	_runner.see(&"spectate_switched")
	assert_int(_runner.lesson()).is_equal(2)


func test_a_voice_frame_counts_only_with_another_living_player_within_the_radius() -> void:
	_play([_lesson([_step([_seen(&"voice_sent")], [OtherWithin.new()])]), _lesson([_any()])])
	_snapshot({TWO: Vector3(RADIUS + 0.5, 0, 0)})
	_runner.advance(0.1, Vector3.ZERO, true)
	_runner.see(&"voice_sent")
	assert_int(_runner.lesson()).is_equal(1)
	# An avatar of nobody in the roster (it reads as alive) is no one to talk to either.
	_snapshot({TWO: Vector3(RADIUS + 0.5, 0, 0), STRANGER: Vector3(1, 0, 0)})
	_runner.see(&"voice_sent")
	assert_int(_runner.lesson()).is_equal(1)
	# The own peer in a snapshot, or a downed player within it, is nobody to talk to.
	_snapshot({OWN: Vector3.ZERO, TWO: Vector3(1, 0, 0)})
	_model.lives[TWO] = ClientModel.Life.DOWNED
	_runner.see(&"voice_sent")
	assert_int(_runner.lesson()).is_equal(1)
	# The edge counts (a radius includes its edge).
	_model.lives.erase(TWO)
	_snapshot({TWO: Vector3(0, 0, RADIUS)})
	_runner.see(&"voice_sent")
	assert_int(_runner.lesson()).is_equal(2)


func test_other_within_reads_its_metres_or_the_phases_radius() -> void:
	var near := OtherWithin.new()
	near.metres = 2.0
	_play([_lesson([_step([_seen(&"map_opened")], [near])]), _lesson([_any()])])
	_snapshot({THREE: Vector3(2.5, 0, 0)})
	_runner.advance(0.1, Vector3.ZERO, false)
	_runner.see(&"map_opened")
	assert_int(_runner.lesson()).is_equal(1)
	_runner.advance(0.1, Vector3(0.5, 0, 0), false)
	_runner.see(&"map_opened")
	assert_int(_runner.lesson()).is_equal(2)
	# A phase whose voice rule hears nobody: nobody is within 0 metres.
	_play([_lesson([_step([_seen(&"map_opened")], [OtherWithin.new()])]), _lesson([_any()])])
	_model.phase = &"gather"
	_snapshot({THREE: Vector3(0.1, 0, 0)})
	_runner.advance(0.1, Vector3.ZERO, false)
	_runner.see(&"map_opened")
	assert_int(_runner.lesson()).is_equal(1)


func test_with_no_open_microphone_three_seconds_in_a_row_within_the_radius_complete_it() -> void:
	_play([_lesson([_step([_seen(&"voice_sent", 3.0)], [OtherWithin.new()])]), _lesson([_any()])])
	var inside := Vector3(1, 0, 0)
	var outside := Vector3(RADIUS + 1.0, 0, 0)
	_snapshot({TWO: Vector3.ZERO})
	# 2 s in, 2 s out, 2 s in: not three in a row.
	_for_seconds(2.0, inside, false)
	_for_seconds(2.0, outside, false)
	_for_seconds(2.0, inside, false)
	assert_int(_runner.lesson()).is_equal(1)
	# A microphone opening mid-count starts it again.
	_for_seconds(0.5, inside, true)
	_for_seconds(2.9, inside, false)
	assert_int(_runner.lesson()).is_equal(1)
	_for_seconds(0.2, inside, false)
	assert_int(_runner.lesson()).is_equal(2)


func test_own_life_holds_a_step_back_until_it_holds() -> void:
	var alive := OwnLife.new()
	var waiting := _step([_seen(&"map_opened")])
	waiting.starts_when = [alive]
	_play([_lesson([_step([_seen(&"esc_opened")])]), _lesson([waiting]), _lesson([_any()])])
	_fold(&"Died", {"peer": OWN, "position": Vector3.ZERO})
	_runner.see(&"esc_opened")
	# Lesson 1 is done, lesson 2 waits: nothing current, and its trigger does nothing yet.
	assert_bool(_runner.is_done(1)).is_true()
	assert_int(_runner.lesson()).is_equal(0)
	assert_int(_runner.step()).is_equal(0)
	assert_object(_runner.current_step()).is_null()
	assert_array(_runner.keys()).is_empty()
	_runner.see(&"map_opened")
	assert_bool(_runner.is_done(2)).is_false()
	# The respawn's event starts it, and does not count as its trigger.
	_event_in(&"Respawned", {"peer": OWN, "position": Vector3.ZERO})
	assert_int(_runner.lesson()).is_equal(2)
	_runner.see(&"map_opened")
	assert_int(_runner.lesson()).is_equal(3)
	# Each life by its name.
	for life: StringName in OwnLife.LIVES:
		var condition := OwnLife.new()
		condition.life = life
		var step := _step([_seen(&"map_opened")])
		step.starts_when = [condition]
		_play([_lesson([step]), _lesson([_any()])])
		var expected := 1 if life == &"alive" else 0
		assert_int(_runner.lesson()).override_failure_message(life).is_equal(expected)


func test_done_when_completes_on_entry_and_needs_a_task() -> void:
	var deliver := _step([_event(&"PackageDelivered", {})])
	deliver.done_when = [TasksDone.new()]
	_play([_lesson([_step([_seen(&"map_opened")])]), _lesson([deliver]), _lesson([_any()])])
	# 0 of 0 tasks is no task done.
	_runner.see(&"map_opened")
	assert_int(_runner.lesson()).is_equal(2)
	# Delivered while lesson 2 runs: its trigger.
	_fold(&"TaskProgress", {"done": 1, "total": 1})
	_event_in(&"PackageDelivered", {"item": PACKAGE, "station": 0})
	assert_int(_runner.lesson()).is_equal(3)
	# Already done as it starts (the package put down in its circle in an earlier lesson): at once.
	_play([_lesson([_step([_seen(&"map_opened")])]), _lesson([deliver]), _lesson([_any()])])
	_event_in(&"PackageDelivered", {"item": PACKAGE, "station": 0})
	assert_int(_runner.lesson()).is_equal(1)
	_runner.see(&"map_opened")
	assert_bool(_runner.is_done(2)).is_true()
	assert_int(_runner.lesson()).is_equal(3)


func test_request_stage_asks_once_as_its_step_starts() -> void:
	var staged := _step([_seen(&"map_opened")])
	staged.on_start = [RequestStage.new()]
	_play([_lesson([_step([_seen(&"esc_opened")])]), _lesson([staged]), _lesson([_any()])])
	assert_int(_emitted[&"next_stage_requested"]).is_equal(0)
	_runner.see(&"esc_opened")
	assert_int(_emitted[&"next_stage_requested"]).is_equal(1)
	_runner.see(&"esc_opened")
	_runner.see(&"map_opened")
	assert_int(_emitted[&"next_stage_requested"]).is_equal(1)
	# start() again keeps the progress and asks nothing more.
	_runner.start()
	assert_int(_runner.lesson()).is_equal(3)
	assert_int(_emitted[&"next_stage_requested"]).is_equal(1)


func test_after_the_last_lesson_the_esc_menu_closing_finishes() -> void:
	_play([_lesson([_step([_seen(&"map_opened")])]), _lesson([_step([_seen(&"esc_opened")])])])
	# The menu opened during lesson 1 and closed: nothing.
	_runner.esc_closed()
	_runner.see(&"map_opened")
	assert_int(_runner.lesson()).is_equal(2)
	_runner.esc_closed()
	assert_int(_emitted[&"finished"]).is_equal(0)
	_runner.see(&"esc_opened")
	assert_bool(_runner.is_done(2)).is_true()
	assert_int(_runner.lesson()).is_equal(0)
	assert_int(_emitted[&"finished"]).is_equal(0)
	# Waiting for the close, the runner is not running, yet a second start() does nothing: it
	# would play lesson 1 again over every lesson done.
	assert_bool(_runner.is_running()).is_false()
	assert_bool(_runner.is_started()).is_true()
	_runner.start()
	assert_int(_runner.lesson()).is_equal(0)
	assert_bool(_runner.is_running()).is_false()
	_runner.esc_closed()
	assert_int(_emitted[&"finished"]).is_equal(1)
	assert_bool(_runner.is_finished()).is_true()
	_runner.esc_closed()
	_runner.see(&"esc_opened")
	_runner.start()
	assert_int(_emitted[&"finished"]).is_equal(1)
	assert_bool(_runner.is_running()).is_false()


func test_a_menu_open_from_before_the_last_lesson_does_not_finish_it() -> void:
	_play([_lesson([_step([_seen(&"voice_sent")])]), _lesson([_step([_seen(&"esc_opened")])])])
	# The menu opens during lesson 1, which completes under it: lesson 2 starts with it open.
	_runner.see(&"esc_opened")
	_runner.see(&"voice_sent")
	assert_int(_runner.lesson()).is_equal(2)
	_runner.esc_closed()
	assert_int(_emitted[&"finished"]).is_equal(0)
	assert_int(_runner.lesson()).is_equal(2)
	_runner.see(&"esc_opened")
	_runner.esc_closed()
	assert_int(_emitted[&"finished"]).is_equal(1)


func test_the_menu_opening_in_a_last_lesson_it_does_not_complete_finishes_nothing() -> void:
	# Step 1 of the last lesson completes on the menu opening, step 2 is still to do.
	_play([_lesson([_step([_seen(&"esc_opened")]), _step([_seen(&"map_opened")])])])
	_runner.see(&"esc_opened")
	assert_int(_runner.step()).is_equal(2)
	_runner.esc_closed()
	assert_int(_emitted[&"finished"]).is_equal(0)
	assert_int(_runner.lesson()).is_equal(1)
	# Done by something else later, it finishes at once, not on another menu closing.
	_runner.see(&"map_opened")
	assert_int(_emitted[&"finished"]).is_equal(1)
	# The same with a condition that fails: the opening is ignored and the menu closing is too.
	var dead := OwnLife.new()
	dead.life = &"dead"
	_play([_lesson([_step([_seen(&"esc_opened")], [dead])])])
	_runner.see(&"esc_opened")
	_runner.esc_closed()
	assert_int(_emitted[&"finished"]).is_equal(0)
	assert_int(_runner.lesson()).is_equal(1)


func test_a_last_lesson_done_by_anything_else_finishes_at_once() -> void:
	_play([_lesson([_step([_seen(&"map_opened")])])])
	_runner.see(&"map_opened")
	assert_int(_emitted[&"finished"]).is_equal(1)


func test_changed_follows_each_change_and_nothing_else() -> void:
	_build(
		[_lesson([_step([_seen(&"map_opened")]), _step([_seen(&"esc_opened")])]), _lesson([_any()])]
	)
	_runner.start()
	assert_int(_emitted[&"changed"]).is_equal(1)
	_runner.see(&"voice_sent")
	_runner.advance(0.1, Vector3.ZERO, false)
	_event_in(&"Swapped", {"peer": OWN})
	assert_int(_emitted[&"changed"]).is_equal(1)
	_runner.see(&"map_opened")
	assert_int(_runner.lesson()).is_equal(1)
	assert_int(_runner.step()).is_equal(2)
	assert_int(_emitted[&"changed"]).is_equal(2)
	_runner.see(&"esc_opened")
	assert_int(_emitted[&"changed"]).is_equal(3)
	assert_int(_runner.lesson_count()).is_equal(2)


## Builds and starts a runner over `lessons`.
func _play(lessons: Array[TutorialLesson]) -> void:
	_build(lessons)
	_runner.start()


func _build(lessons: Array[TutorialLesson]) -> void:
	var data := TutorialLessons.new()
	data.lessons = lessons
	assert_array(data.problems()).is_empty()
	_runner = LessonRunner.new()
	_runner.setup(data, _model)
	for key: StringName in _emitted:
		_emitted[key] = 0
	_runner.changed.connect(func() -> void: _emitted[&"changed"] += 1)
	_runner.next_stage_requested.connect(func() -> void: _emitted[&"next_stage_requested"] += 1)
	_runner.finished.connect(func() -> void: _emitted[&"finished"] += 1)


func _lesson(steps: Array[TutorialStep]) -> TutorialLesson:
	var lesson := TutorialLesson.new()
	lesson.list_key = &"list"
	lesson.steps = steps
	for i in steps.size():
		steps[i].title_key = StringName("step%d" % (i + 1))
	return lesson


func _step(
	triggers: Array[TutorialTrigger], conditions: Array[TutorialCondition] = []
) -> TutorialStep:
	var step := TutorialStep.new()
	step.title_key = &"step"
	step.triggers = triggers
	step.conditions = conditions
	return step


## A step nothing in these tests sends (the lesson after the one under test).
func _any() -> TutorialStep:
	return _step([_event(&"NeverSent", {})])


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


func _kind(kind: StringName) -> ItemKindIs:
	var part := ItemKindIs.new()
	part.kind = kind
	return part


## Folds the event into the model, then hands it to the runner, as ClientSession does.
func _event_in(event_name: StringName, fields: Dictionary) -> void:
	_fold(event_name, fields)
	_runner.on_event(event_name, fields)


func _fold(event_name: StringName, fields: Dictionary) -> void:
	_model.fold(event_name, fields)


func _snapshot(at: Dictionary) -> void:
	var avatars := {}
	for peer: int in at:
		avatars[peer] = {"position": at[peer]}
	_model.avatars = avatars


## Frames of 0.1 s for `seconds`, the own player at `at`.
func _for_seconds(seconds: float, at: Vector3, mic_live: bool) -> void:
	for i in roundi(seconds / 0.1):
		_runner.advance(0.1, at, mic_live)
