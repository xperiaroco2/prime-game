class_name PlayerTuning
extends Resource
## The player's movement and stamina numbers in one data place: `player_tuning.tres`. They are
## the placeholders of `docs/decisions/2026-09-29-mvp-rules.md` ("not a decision"). The defaults
## here are 0 on purpose, so the numbers live only in the `.tres`. `core/`'s stamina and movement
## rules (stage 2d in #30) and later the designer's content take them over from here.

@export_group("Movement")
## Metres per second on the ground, not sprinting.
@export var walk_speed: float = 0.0
## Metres per second on the ground while in the sprint state.
@export var sprint_speed: float = 0.0
## Metres a jump lifts the feet above the floor it started from, at most.
@export var jump_height: float = 0.0
## Metres per second a ghost flies, in any direction.
@export var ghost_speed: float = 0.0
## The tallest ledge a player walks up without a jump, in metres.
@export var step_height: float = 0.0

@export_group("Body")
## The capsule of a living player and of a ghost (Q6), in metres.
@export var capsule_radius: float = 0.0
@export var capsule_height: float = 0.0
## Height of the eyes above the feet: the camera, and later the start of a hit's line of sight.
@export var eye_height: float = 0.0

@export_group("Stamina")
@export var max_stamina: float = 0.0
## Spent per second in the sprint state while moving horizontally.
@export var sprint_cost_per_second: float = 0.0
## The stamina a sprint needs to start (Q7: one second of sprint).
@export var sprint_start_stamina: float = 0.0
## Spent at once by an accepted jump; a jump needs at least this much (Q7).
@export var jump_cost: float = 0.0
## Regained per second while not spent.
@export var regen_per_second: float = 0.0


## The take-off speed that lifts the feet exactly `jump_height` at the top of the jump, for a
## physics step of `delta` seconds under `gravity` (m/s², positive). The body moves by its
## velocity after each step's gravity, so the discrete peak is
## v²/(2g) + v·dt/2 + g·dt²/8; solving that for `jump_height` gives the formula below, and the
## peak never overshoots the height the host will bound a jump by (§7.1).
func jump_velocity(gravity: float, delta: float) -> float:
	return sqrt(2.0 * gravity * jump_height) - gravity * delta * 0.5
