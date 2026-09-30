class_name Facts
extends RefCounted
## The names of the facts (ARCHITECTURE §9.2): what an effect raises, and a reaction's trigger.
## A fact is handled at once, depth first.

const ITEM_RESTED := &"item_rested"
const PLAYER_DIED := &"player_died"
const PLAYER_LEFT := &"player_left"
const SUBTASK_DONE := &"subtask_done"
const CLOCK_ENDED := &"clock_ended"

const ALL: Array[StringName] = [ITEM_RESTED, PLAYER_DIED, PLAYER_LEFT, SUBTASK_DONE, CLOCK_ENDED]
