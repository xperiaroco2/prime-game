class_name TaskState
extends RefCounted
## The state of one task in a match (ARCHITECTURE §9.1): created by its task type in its deal,
## kept in MatchState, read and written only by that task type (Delivery: which subtasks are
## done; #36: the time in the zone per subtask). A task type subclasses it as an inner class.


## Subtasks done.
func done_count() -> int:
	return 0


## Subtasks in total.
func total() -> int:
	return 0


## Done when every subtask is: a task with no subtasks is done (the engineer's rule, #79).
func is_done() -> bool:
	return done_count() >= total()
