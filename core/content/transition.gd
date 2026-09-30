class_name Transition
extends ContentPart
## One row of a game mode's transition table (ARCHITECTURE §3.1): from phase, outcome -> to phase,
## and the actions to run, in order, before the phase is left. Rows are keyed by an outcome, so a
## transition without a trigger cannot be written. The actions are effects with no actor; they
## see the outcome and its argument (EndMatch reads the side of `won`).

@export var from: StringName
@export var outcome: StringName
@export var to: StringName
@export var actions: Array[RuleEffect] = []
