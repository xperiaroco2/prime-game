class_name TutorialLesson
extends Resource
## One of the tutorial's lessons (docs/design/tutorial.md §1, §3): its row in the lesson list and
## one or two steps, the second swapping the instruction within the same lesson number.

## The most steps a lesson has (the screens draw two instructions at most).
const MAX_STEPS := 2

## The list's row, a deck key (`tutorial.list.move`).
@export var list_key: StringName = &""
## The InputMap action that fills the row's `{key}` (`map` for `tutorial.list.map`); empty: none.
@export var list_action: StringName = &""
@export var steps: Array[TutorialStep] = []


## What makes this lesson unusable; empty when it is fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if list_key.is_empty():
		found.append("a lesson with no list_key")
	if steps.is_empty() or steps.size() > MAX_STEPS:
		found.append("%s: %d steps, 1 to %d" % [list_key, steps.size(), MAX_STEPS])
	for step: TutorialStep in steps:
		if step == null:
			found.append("%s: an empty step" % list_key)
			continue
		for problem: String in step.problems():
			found.append("%s: %s" % [list_key, problem])
	return found
