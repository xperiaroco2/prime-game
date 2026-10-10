class_name LessonRunner
extends RefCounted
## Plays the tutorial's lessons (docs/design/tutorial.md §1, §3: E63, E64; ARCHITECTURE §4.7): a
## pure RefCounted fed what the own client already knows, the own session's events (on_event),
## the own claims (on_claim), the client's own signals (see, esc_closed) and, every frame, the
## local player's position and whether a microphone is open (advance). It reads the own
## ClientModel and the client's own copy of the mode, and sends nothing: `next_stage_requested`
## (a RequestStage as lessons 6 and 7 start) is the one thing the game turns into an intent
## (NextStage), and `finished` ends the session.
##
## A step starts once its `starts_when` holds (until then the previous lesson stays done and
## nothing is current), runs its `on_start`, and completes at once when its `done_when` holds;
## else any of its triggers firing from then on, its `conditions` holding, completes it. After the
## last lesson, a completion by the Esc menu opening waits for the menu to close (D32 (b)).

## The current lesson, step or the done set changed (the screens redraw, #492).
signal changed
## A RequestStage ran: the game sends NextStage.
signal next_stage_requested
## Every lesson is done: the game ends the session.
signal finished

var _lessons: TutorialLessons
var _model: ClientModel
## Index of the lesson and step under way; -1 before start() and after the last.
var _lesson := -1
var _step := 0
## The step waits for its starts_when.
var _pending := false
var _done: Array[bool] = []
var _running := false
var _finished := false
## start() ran; a second one does nothing.
var _started := false
## The last lesson was completed by the Esc menu opening: its close finishes.
var _awaiting_close := false
## As the step started: the item in the own hand, or -1.
var _held := -1
## Seconds of own claims moving itself since the step started.
var _moved_s := 0.0
## Seconds in a row with the step's conditions holding and no microphone open (D31 (a)).
var _quiet_s := 0.0
## The local player's position, from the latest advance().
var _own_position := Vector3.INF


## The lessons to play, over the own model (its own copy of the mode gives the phase's voice
## radius).
func setup(lessons: TutorialLessons, model: ClientModel) -> void:
	_lessons = lessons
	_model = model
	_done.clear()
	_done.resize(lessons.lessons.size())
	_done.fill(false)
	_started = false


## Begins lesson 1; once only.
func start() -> void:
	if _started or _lessons == null:
		return
	_started = true
	_running = true
	var before := _state()
	_enter(0, 0)
	_changed_since(before)


## start() ran: lesson 1 began (the tutorial may still wait for the Esc menu to close).
func is_started() -> bool:
	return _started


func is_running() -> bool:
	return _running


func is_finished() -> bool:
	return _finished


func lesson_count() -> int:
	return _done.size()


## The current lesson, 1 to lesson_count(); 0 when none is current (not started, a step waiting for
## its starts_when, or all done).
func lesson() -> int:
	return _lesson + 1 if _running and not _pending and _lesson >= 0 else 0


## The current step within the lesson, 1 or 2; 0 when no lesson is current.
func step() -> int:
	return _step + 1 if lesson() != 0 else 0


func current_step() -> TutorialStep:
	return _lessons.lessons[_lesson].steps[_step] if lesson() != 0 else null


## The current step's InputMap actions (or TutorialStep.HOWTO_GLYPH); empty with none current.
func keys() -> Array[StringName]:
	var current := current_step()
	var none: Array[StringName] = []
	return current.keys if current != null else none


## Whether lesson `number` (1-based) is done.
func is_done(number: int) -> bool:
	return number >= 1 and number <= _done.size() and _done[number - 1]


## An event the own session decoded, after the model folded it.
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if not _running:
		return
	var before := _state()
	if _pending:
		_try_start()
	else:
		var current := current_step()
		if current != null and _event_fires(current, event_name, fields):
			_fire(fields)
	_changed_since(before)


## A claim went out (ClientSession.claim_sent): the client ticks it covers and whether it moved
## itself.
func on_claim(covered: int, moved_itself: bool) -> void:
	if not _running or _pending or not moved_itself:
		return
	_moved_s += float(covered) / Ticks.RATE
	var trigger := _seen_trigger(ClientSeen.MOVED)
	if trigger != null and _moved_s >= trigger.amount:
		_signal_fired()


## One of the client's signals (ClientSeen.SIGNALS) but `moved`, which on_claim counts.
func see(signal_name: StringName) -> void:
	if not _running or _pending or signal_name == ClientSeen.MOVED:
		return
	if _seen_trigger(signal_name) == null:
		return
	if signal_name == ClientSeen.ESC_OPENED and _lesson == _done.size() - 1:
		_awaiting_close = true
	_signal_fired()
	if not _finished and _lesson >= 0:
		_awaiting_close = false


## Every frame: the local player's position and whether a microphone is open (VoiceSender.live),
## for OtherWithin and D31 (a)'s fallback; a waiting step's starts_when is checked again.
func advance(delta_s: float, own_position: Vector3, mic_live: bool) -> void:
	_own_position = own_position
	if not _running:
		return
	if _pending:
		var before := _state()
		_try_start()
		_changed_since(before)
		return
	var trigger := _seen_trigger(ClientSeen.VOICE_SENT)
	if trigger == null or trigger.amount <= 0.0:
		return
	if mic_live or not _holds(current_step().conditions, {}):
		_quiet_s = 0.0
		return
	_quiet_s += delta_s
	if _quiet_s >= trigger.amount:
		_signal_fired()


## The Esc menu closed (Resume or Esc): after the last lesson completed by its opening, the
## tutorial is finished (D32 (b)).
func esc_closed() -> void:
	if _awaiting_close and not _finished:
		_awaiting_close = false
		_finish()


## [lesson, step, pending, done count, running]: what `changed` reports a change of.
func _state() -> Array:
	return [_lesson, _step, _pending, _done.count(true), _running]


func _changed_since(before: Array) -> void:
	if _state() != before:
		changed.emit()


## Lesson `lesson_i`, step `step_i` is next: it starts when its starts_when holds.
func _enter(lesson_i: int, step_i: int) -> void:
	_lesson = lesson_i
	_step = step_i
	_pending = true
	_try_start()


func _try_start() -> void:
	var next: TutorialStep = _lessons.lessons[_lesson].steps[_step]
	if not _holds(next.starts_when, {}):
		return
	_pending = false
	_held = _model.hand_item(_model.own_peer)
	_moved_s = 0.0
	_quiet_s = 0.0
	for action: TutorialAction in next.on_start:
		if action is RequestStage:
			next_stage_requested.emit()
	if not next.done_when.is_empty() and _holds(next.done_when, {}):
		_complete()


## A trigger of the current step fired with `fields` (empty for a client signal).
func _fire(fields: Dictionary) -> void:
	if _holds(current_step().conditions, fields):
		_complete()


func _signal_fired() -> void:
	var before := _state()
	_fire({})
	_changed_since(before)


func _complete() -> void:
	var lesson_steps := _lessons.lessons[_lesson].steps
	if _step + 1 < lesson_steps.size():
		_enter(_lesson, _step + 1)
		return
	_done[_lesson] = true
	if _lesson + 1 < _done.size():
		_enter(_lesson + 1, 0)
		return
	_lesson = -1
	_step = 0
	_running = false
	if not _awaiting_close:
		_finish()


func _finish() -> void:
	_finished = true
	_running = false
	finished.emit()


## The current step's ClientSeen trigger on `signal_name`, or null.
func _seen_trigger(signal_name: StringName) -> ClientSeen:
	var current := current_step()
	if current == null:
		return null
	for trigger: TutorialTrigger in current.triggers:
		var seen := trigger as ClientSeen
		if seen != null and seen.signal_name == signal_name:
			return seen
	return null


func _event_fires(current: TutorialStep, event_name: StringName, fields: Dictionary) -> bool:
	for trigger: TutorialTrigger in current.triggers:
		var seen := trigger as EventSeen
		if seen != null and seen.event == event_name and _fields_match(seen.fields, fields):
			return true
	return false


func _fields_match(wanted: Dictionary, fields: Dictionary) -> bool:
	for key: Variant in wanted:
		var name := str(key)
		if not fields.has(name):
			return false
		var got: Variant = fields[name]
		var value: Variant = wanted[key]
		if value is StringName and value == EventSeen.OWN:
			if not (got is int and got == _model.own_peer):
				return false
		elif value is StringName and value == EventSeen.OTHER:
			if not (got is int and got != _model.own_peer and got != 0):
				return false
		elif value is StringName and value == EventSeen.HELD:
			if not (got is int and _held != -1 and got == _held):
				return false
		elif not _same(value, got):
			return false
	return true


## Equal as data: names compare as text (a decoded StringName may arrive as a String), numbers as
## numbers.
static func _same(a: Variant, b: Variant) -> bool:
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	if (a is int or a is float) and (b is int or b is float):
		return a == b
	return typeof(a) == typeof(b) and a == b


func _holds(conditions: Array[TutorialCondition], fields: Dictionary) -> bool:
	for condition: TutorialCondition in conditions:
		if not _condition_holds(condition, fields):
			return false
	return true


func _condition_holds(condition: TutorialCondition, fields: Dictionary) -> bool:
	if condition is OwnLife:
		var wanted := String((condition as OwnLife).life).to_upper()
		return (
			ClientModel.Life.has(wanted)
			and _model.life_of(_model.own_peer) == ClientModel.Life[wanted]
		)
	if condition is OtherWithin:
		return _other_within((condition as OtherWithin).metres)
	if condition is ItemKindIs:
		var item_id: Variant = fields.get("item")
		var item: ClientModel.Item = _model.items.get(item_id) if item_id is int else null
		return item != null and item.kind == (condition as ItemKindIs).kind
	if condition is TasksDone:
		return _model.tasks_total > 0 and _model.tasks_done >= _model.tasks_total
	return false


## Another living player of the roster stands within `metres` (0: the current phase's voice
## radius) of the local player, in the latest snapshot.
func _other_within(metres: float) -> bool:
	if _own_position == Vector3.INF:
		return false
	var radius := metres
	if radius <= 0.0:
		var phase := _model.phase_spec()
		radius = VoiceRule.radius_of(phase.voice_rule) if phase != null else 0.0
	if radius <= 0.0:
		return false
	for peer: int in _model.avatars:
		if peer == _model.own_peer or not _model.roster.has(peer):
			continue
		if _model.life_of(peer) != ClientModel.Life.ALIVE:
			continue
		var avatar: Dictionary = _model.avatars[peer]
		var at: Variant = avatar.get("position")
		if at is Vector3 and _own_position.distance_to(at as Vector3) <= radius:
			return true
	return false
