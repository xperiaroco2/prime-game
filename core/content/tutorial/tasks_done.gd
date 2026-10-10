class_name TasksDone
extends TutorialCondition
## Condition: every task is done, as the own model's tasks_done and tasks_total tell it, with at
## least one task (docs/design/tutorial.md §3). No settings.


func part_name() -> StringName:
	return &"TasksDone"
