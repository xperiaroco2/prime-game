class_name TaskType
extends ContentPart
## How tasks are dealt and done (ARCHITECTURE §9.3): a class with settings, not composed rules,
## because a task type's deal and its check depend on each other. A new task type is one script:
## this class with its TaskState as an inner class. The MVP's is Delivery (2f); ZoneTask
## (#647) is the second, and the first that ticks.
##
## Tasks are shared (the engineer's decision of 2026-09-30, #79): nobody owns a task, and any
## living player does any subtask. A match deals at most one task of each type: DealTasks draws
## the types and calls deal() once per drawn type, in the mode's order; Match calls on_fact() for
## every fact, after the mode's reactions and in the mode's order; TaskTicks (2f) calls tick()
## when has_tick(). Each type reads its own subtasks setting (Delivery: `packages`).

@export var id: StringName
@export var display_name: String
## What a player does for a task of this type, in a sentence or two: the task screen shows it
## (vision revision 1, the Tab task screen) with the task's shared progress (TaskState). Every
## client reads it from its own copy of the mode, so it never travels. Empty fails the mode check.
@export_multiline var description: String


## A fresh state for one task of this type.
func new_state() -> TaskState:
	return TaskState.new()


## Deals one shared task of this type into ctx.state.tasks (MatchState.add_task), with a state
## from new_state(), and places what it needs. Draws only from the RNG purposes this type names.
func deal(_ctx: MatchContext) -> void:
	pass


## This type's check of a fact (Delivery on `item_rested`), for its own tasks.
func on_fact(_ctx: MatchContext) -> void:
	pass


func has_tick() -> bool:
	return false


func tick(_ctx: MatchContext) -> void:
	pass


## What dealing one task of this type with these settings and `players` players needs of the map
## (§9.4); DealTasks sums these over the types a draw could pick.
func add_demands(_settings: Dictionary[StringName, int], _players: int, _into: Demands) -> void:
	pass


## The event classes this type can emit (§9.2).
func emits() -> Array[Script]:
	return []


## The outcomes on_fact() or tick() can report through MatchContext.report_outcome: ModeCheck
## requires a row for each from every phase (on_fact runs in all of them, §9.1).
func reported_outcomes() -> Array[StringName]:
	return []


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a task type has no id")
	if description.strip_edges().is_empty():
		found.append("task type %s has no description" % id)
	return found
