class_name PinballTableSpec
extends Resource
## The pinball table's physics numbers (#1399; ARCHITECTURE §7.1.22, §9.5.28), PinballTable's data:
## every one provisional, "not a decision", the engineer tunes them on the greybox
## (levels/pinball/pinball_table_spec.tres). Metres, seconds and kilograms in the table's own
## frame: the table lies in its XZ plane, -Z up the table, +Z toward the drain.

## The ball's radius (a sphere) and its mass.
@export var ball_radius_m := 0.03
@export var ball_mass_kg := 0.08
## How much of its speed the ball keeps off a wall or a flipper (the engine combines two bodies'
## bounce by their maximum), and its friction (0: it slides).
@export_range(0.0, 1.0) var ball_bounce := 0.4
@export_range(0.0, 1.0) var wall_bounce := 0.4
@export_range(0.0, 1.0) var ball_friction := 0.0
## How much speed the ball loses each second rolling (linear damping, 1/s).
@export var ball_damp := 0.5
## The table's slope as the pull down the table (+Z), m/s².
@export var slope_mps2 := 1.5
## The ball's speed at its launch, along BallStart's -Z, and the wait before it (after a game
## starts or a ball is lost).
@export var launch_mps := 2.5
@export var launch_delay_s := 1.0
## How far a held flipper turns up from its rest, and how fast it turns (up and back).
@export var flipper_swing_deg := 50.0
@export var flipper_speed_deg_s := 1500.0
## The push a target with no `kick` of its own gives the ball away from its centre, m/s.
@export var kick_mps := 0.0
## A ball slower than `stuck_mps` for `stuck_s` while no flipper is held is lost (no nudge frees
## it); 0 s: never.
@export var stuck_mps := 0.02
@export var stuck_s := 8.0
## How close the ball comes to a target to touch it (beyond its radius), and how far past the
## walls it may go before it is lost (the catch).
@export var touch_m := 0.004
@export var bounds_margin_m := 0.05
