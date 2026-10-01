class_name PlayerTuning
extends Resource
## The client's feel of the local player in one data place: `player_tuning.tres`. Game numbers
## (speeds, jump height, capsule, eye and step height, stamina) are not here: they come from the
## client's own copy of the mode's PlayerRules, which the content hash makes the host's (M4-7,
## ARCHITECTURE §4.7). What stays is what only this client feels: how it pushes and is pushed
## (§7.1 "Pushing apart"; the host tolerates any overlap) and how its view eases. The defaults are
## 0 on purpose, so the numbers live only in the `.tres` (placeholders, "not a decision").

@export_group("Pushing")
## Walking into another living player pushes them: the part of the pusher's motion into them
## slows to this factor, and they are pushed at that reduced speed (the engineer's decision of
## 2026-09-30, #46; the value is a placeholder).
@export var push_speed_factor: float = 0.0
## A pusher also drifts to its own right at this fraction of its push speed, so two players
## pushing each other exactly head-on slide apart instead of freezing.
@export var push_side_bias: float = 0.0
## How deep, in metres, a pusher may sink into a player who does not give way (head-on, or a
## client whose motion arrives late) before it stops advancing into them.
@export var push_max_overlap: float = 0.0

@export_group("View")
## Seconds the view takes to catch up with the body after a step-up lifts it at once.
@export var view_catch_up_seconds: float = 0.0
