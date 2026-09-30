class_name TaskType
extends ContentPart
## How tasks are dealt and done (ARCHITECTURE §9.3): a class with settings, not composed rules,
## because a task type's deal and its check depend on each other. A new task type is one script:
## this class with its TaskState as an inner class. The MVP's is Delivery (2f).
##
## The interface of 2a: DealTasks (2c) calls deal(); Match calls on_fact() for every fact, after
## the mode's reactions and in the mode's order; TaskTicks (2f) calls tick() when has_tick().

@export var id: StringName
@export var display_name: String


## A fresh state for one task of this type.
func new_state() -> TaskState:
	return TaskState.new()


## Deals `per_player` tasks to each present player, in peer-id order, into ctx.state.tasks, with
## a state from new_state(). Draws only from the RNG purposes this type names.
func deal(_ctx: MatchContext, _per_player: int) -> void:
	pass


## This type's check of a fact (Delivery on `item_rested`), for its own tasks.
func on_fact(_ctx: MatchContext) -> void:
	pass


func has_tick() -> bool:
	return false


func tick(_ctx: MatchContext) -> void:
	pass


## What dealing `per_player` tasks to `players` players needs of the map (§9.4).
func add_demands(
	_settings: Dictionary[StringName, int], _players: int, _per_player: int, _into: Demands
) -> void:
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
	return found
