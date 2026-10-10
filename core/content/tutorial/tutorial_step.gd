class_name TutorialStep
extends Resource
## One instruction of a tutorial lesson (docs/design/tutorial.md §3): the plate's words and keys,
## then the content API's shape, trigger -> conditions -> the next step. Data only: the client's
## LessonRunner plays it.

## In `keys`, the «?» keycap of the map's task rows (lesson 5's second step), not an InputMap
## action (#492 draws it).
const HOWTO_GLYPH := &"howto_glyph"

## The plate's title, a deck key of client/i18n/strings.csv (`tutorial.step.move.title`).
@export var title_key: StringName = &""
## The plate's instruction, a deck key; empty: none (lesson 1 shows its key row instead).
@export var how_key: StringName = &""
## The InputMap actions the plate shows (the first fills the how text's `{key}`), or HOWTO_GLYPH.
@export var keys: Array[StringName] = []
## Must hold before the step shows; until then the previous lesson stays done and nothing is
## current.
@export var starts_when: Array[TutorialCondition] = []
## Run once as the step starts.
@export var on_start: Array[TutorialAction] = []
## Complete the step at once when they all hold as it starts (the check on entry).
@export var done_when: Array[TutorialCondition] = []
## Any one of them completes the step, matched only from the step's start.
@export var triggers: Array[TutorialTrigger] = []
## Must hold when a trigger fires; the first that fails ignores that firing.
@export var conditions: Array[TutorialCondition] = []


## What makes this step unusable; empty when it is fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if title_key.is_empty():
		found.append("no title_key")
	if triggers.is_empty() and done_when.is_empty():
		found.append("%s: nothing completes it (no triggers, no done_when)" % title_key)
	var parts: Array[TutorialPart] = []
	parts.append_array(starts_when)
	parts.append_array(on_start)
	parts.append_array(done_when)
	parts.append_array(triggers)
	parts.append_array(conditions)
	for part: TutorialPart in parts:
		if part == null:
			found.append("%s: an empty part" % title_key)
			continue
		for problem: String in part.problems():
			found.append("%s: %s" % [title_key, problem])
	for list: Array[TutorialCondition] in [starts_when, done_when]:
		for condition: TutorialCondition in list:
			if condition != null and condition.reads_event():
				found.append(
					"%s: %s reads an event, only in conditions" % [title_key, condition.part_name()]
				)
	for key: StringName in keys:
		if key.is_empty():
			found.append("%s: an empty key" % title_key)
	return found
