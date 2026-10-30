class_name Facts
extends RefCounted
## The names of the facts (ARCHITECTURE §9.2): what an effect raises, and a reaction's trigger.
## A fact is handled at once, depth first.

const ITEM_RESTED := &"item_rested"
const PLAYER_DIED := &"player_died"
const PLAYER_LEFT := &"player_left"
const SUBTASK_DONE := &"subtask_done"
const CLOCK_ENDED := &"clock_ended"
## A drink lifted the drinker (Fact.player) from below PlayerRules.drunk_too_much_at to that or
## above (Drink, #1390): the "too much" the limp (#1393) reacts to. Every upward crossing raises it.
const DRUNK_TOO_MUCH := &"drunk_too_much"

const ALL: Array[StringName] = [
	ITEM_RESTED, PLAYER_DIED, PLAYER_LEFT, SUBTASK_DONE, CLOCK_ENDED, DRUNK_TOO_MUCH
]
