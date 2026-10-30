class_name PlayerTuning
extends Resource
## The client's feel of the local player in one data place: `player_tuning.tres`. Game numbers
## (speeds, jump height, capsule, eye and step height, stamina) are not here: they come from the
## client's own copy of the mode's PlayerRules, which the content hash makes the host's (M4-7,
## ARCHITECTURE §4.7). What stays is what only this client feels: how it pushes and is pushed
## (§7.1 "Pushing apart"; the host tolerates any overlap), how its view and its move ease, and how
## it feels drunk (the sway and the drift, #1391). The defaults are 0 on purpose, so the numbers
## live only in the `.tres` (placeholders, "not a decision").

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

@export_group("Moving")
## Seconds the own move takes to reach a new speed and direction, from rest to a run and back to
## rest alike (#1334, art #196: about 0.2 s). Feel only: it never moves faster than the mode's
## speeds, which the host checks; 0 is at once.
@export var accel_seconds: float = 0.0

@export_group("Drunk")
## The drunk feel (#1391; GDD §3 Base mode, "The bar"; DrunkFeel): its strength runs 0..1 with the
## own drunk value, full at the mode's PlayerRules.drunk_too_much_at. Every number of this group is
## PROVISIONAL, "not a decision": the engineer's taste on the PR (#1391's "Needs the engineer").
## The strength's curve: an exponent of the value's share of drunk_too_much_at (1 linear).
@export var drunk_curve: float = 0.0
## Seconds the strength takes to cross 0..1 as the value rises or decays (the ease-out).
@export var drunk_ease_seconds: float = 0.0
## The camera's largest roll at full strength, in degrees (own view only; no yaw ever).
@export var sway_roll_max_deg: float = 0.0
## The camera's largest pitch at full strength, in degrees: it moves the view's centre off the
## claimed facing (the head's), so it stays small.
@export var sway_pitch_max_deg: float = 0.0
## The sway's first period in seconds (0: that sine off); two sines mixed make it irregular.
@export var sway_period_s: float = 0.0
## The sway's second period in seconds (0: that sine off).
@export var sway_second_period_s: float = 0.0
## The walk's wander at full strength: the keys' direction turned by up to this many degrees.
@export var drift_wander_deg: float = 0.0
## A steady lean to one side (the peer id's) at full strength, in degrees, on top of the wander.
@export var drift_lean_deg: float = 0.0
## The wander's first period in seconds (0: that sine off).
@export var drift_period_s: float = 0.0
## The wander's second period in seconds (0: that sine off).
@export var drift_second_period_s: float = 0.0
