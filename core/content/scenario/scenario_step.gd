class_name ScenarioStep
extends Resource
## One step of a bot's script (ARCHITECTURE §9.7). Steps are a closed list, like parts: the
## engineer adds a step class here and lists it in §9.7. Data only: the runners interpret them.

## For a step that sends an intent: a rejection reason. With it, the step is done when that
## Rejected arrives, and fails when the intent succeeds or is refused with another reason.
@export var expect_rejected: StringName


## The step's name in §9.7 (`WalkTo`).
func step_name() -> StringName:
	return &""


## Whether the step sends an intent, so `expect_rejected` applies.
func sends_intent() -> bool:
	return false


## What makes this step unusable; empty when it is fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if not expect_rejected.is_empty() and not sends_intent():
		found.append("expect_rejected on a step that sends no intent")
	return found


## `target`'s problems, or "no target" when it is missing.
static func target_problems(target: ScenarioTarget, name: String) -> PackedStringArray:
	if target == null:
		return PackedStringArray(["no %s" % name])
	return target.problems()
