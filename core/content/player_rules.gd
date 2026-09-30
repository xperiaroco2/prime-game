class_name PlayerRules
extends ContentPart
## The numbers of a player's body (ARCHITECTURE §9.3, §9.5): health, stamina, speeds, jump and
## capsule, in whole points, metres and seconds. core/ keeps health and stamina in thousandths
## (§3.3); the movement rule (2d) reads the rest. Defaults are the MVP placeholders, "not a
## decision".

@export var health := 100
@export var stamina := 100
## Stamina regenerated per second while not sprinting.
@export var stamina_regen_per_s := 15
@export var walk_speed_mps := 4.5
@export var sprint_speed_mps := 7.0
@export var sprint_cost_per_s := 20
## Stamina needed to start sprinting.
@export var sprint_start := 20
@export var jump_height_m := 1.0
@export var jump_cost := 10
@export var ghost_speed_mps := 8.0
@export var capsule_radius_m := 0.4
@export var capsule_height_m := 1.8
@export var eye_height_m := 1.6
@export var step_height_m := 0.3


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(
		found,
		[
			out_of_bounds("health", health, 1, 1000),
			out_of_bounds("stamina", stamina, 1, 1000),
			out_of_bounds("stamina_regen_per_s", stamina_regen_per_s, 0, 1000),
			out_of_bounds("walk_speed_mps", walk_speed_mps, 0.5, 20),
			out_of_bounds("sprint_speed_mps", sprint_speed_mps, walk_speed_mps, 30),
			out_of_bounds("sprint_cost_per_s", sprint_cost_per_s, 0, 1000),
			out_of_bounds("sprint_start", sprint_start, 0, stamina),
			out_of_bounds("jump_height_m", jump_height_m, 0, 5),
			out_of_bounds("jump_cost", jump_cost, 0, stamina),
			out_of_bounds("ghost_speed_mps", ghost_speed_mps, 0.5, 30),
			out_of_bounds("capsule_radius_m", capsule_radius_m, 0.1, 1),
			out_of_bounds("capsule_height_m", capsule_height_m, 0.5, 3),
			out_of_bounds("eye_height_m", eye_height_m, 0, capsule_height_m),
			out_of_bounds("step_height_m", step_height_m, 0, 1),
		]
	)
	return found
