class_name PlayerRules
extends ContentPart
## The numbers of a player's body (ARCHITECTURE §9.3, §9.5): health, stamina, speeds, jump and
## capsule, in whole points, metres and seconds. core/ keeps health and stamina in thousandths
## (§3.3); the movement rule and the stamina ledger (2d, §7.1) read the rest.
##
## The class defaults are 0 on purpose (the engineer's answer (1) on #58): the Godot saver drops
## a property equal to its class default, so with neutral defaults every number of a mode is
## written in its `.tres`, where the designer reviews it. A mode that leaves one out fails the
## mode check (§9.1). The base mode's values are the MVP placeholders, "not a decision".

@export var health := 0
@export var stamina := 0
## Stamina regenerated per second while not spent (§7.1).
@export var stamina_regen_per_s := 0
@export var walk_speed_mps := 0.0
@export var sprint_speed_mps := 0.0
## Stamina spent per second in the sprint state while the player moves itself (§7.1).
@export var sprint_cost_per_s := 0
## Stamina needed to start sprinting (Q7).
@export var sprint_start := 0
## Metres a jump lifts the feet above the floor it started from, at most.
@export var jump_height_m := 0.0
@export var jump_cost := 0
## A ghost walks and sprints at the living's speeds times this factor (the engineer's decision of
## 2026-09-30, #46). Its bounds, 1 to 3, are proposed, not confirmed.
@export var ghost_speed_factor := 0.0
@export var capsule_radius_m := 0.0
@export var capsule_height_m := 0.0
@export var eye_height_m := 0.0
## The tallest ledge a player walks up without a jump.
@export var step_height_m := 0.0


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
			out_of_bounds("ghost_speed_factor", ghost_speed_factor, 1, 3),
			out_of_bounds("capsule_radius_m", capsule_radius_m, 0.1, 1),
			out_of_bounds("capsule_height_m", capsule_height_m, 0.5, 3),
			out_of_bounds("eye_height_m", eye_height_m, 0, capsule_height_m),
			out_of_bounds("step_height_m", step_height_m, 0, 1),
		]
	)
	return found
