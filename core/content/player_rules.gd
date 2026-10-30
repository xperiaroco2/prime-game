class_name PlayerRules
extends ContentPart
## The numbers of a player's body (ARCHITECTURE §9.3, §9.5): health, stamina, speeds, jump,
## capsule and the life times, in whole points, metres and seconds. core/ keeps health and stamina
## in thousandths (§3.3); the movement rule and the stamina ledger (2d, §7.1) read the speeds, the
## life rule (§3.4, M4-2, M4-3) the knockdown, respawn and invulnerability times and a respawn
## marker's free radius. The client reads the same numbers for its own movement and countdowns
## (E27). A downed player has no speed: it cannot move (the knockdown rework's KE4).
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
## Seconds a knocked-down player stays downed before it dies (vision revision 1). Its bounds, 1 to
## 120, are placeholders, "not a decision".
@export var knockdown_s := 0.0
## Seconds from a death to the respawn (vision revision 1, V6; LifeTicks with a Respawn). Its
## bounds, 1 to 300, are placeholders, "not a decision".
@export var respawn_s := 0.0
## Seconds a revived or respawned player is invulnerable: strikes skip it, and nothing ends it
## early (V8; the engineer's answer 3 on PR #133). Its bounds, 0 to 30, are placeholders.
@export var invulnerable_s := 0.0
## A respawn marker is free when no living or downed player stands within this many metres of it
## (V6; from its feet). Its bounds, 0 to 5, are placeholders, "not a decision".
@export var respawn_free_m := 0.0
@export var capsule_radius_m := 0.0
@export var capsule_height_m := 0.0
@export var eye_height_m := 0.0
## The tallest ledge a player walks up without a jump.
@export var step_height_m := 0.0
## The crouch (the crouch ADR, KE2): the crouched capsule's height and eye, which the host reads
## for a crouched player's eye (Items.eye_of) and capsule (Strike, the throw's contact and radius
## bound), and the crouch walk's speeds without and with Shift, which only the client moves at (KE3
## (a): the host checks a crouched claim with the walk's and the sprint's bounds). Placeholders,
## "not a decision", as are their bounds. The crouch plays everywhere, the lobby included, with no
## per-map option (the engineer, #989/#991: the crouch ADR's KE10 amendment). On the client a step
## at or below `crouch_speed_mps` is quiet and one at `crouch_fast_speed_mps` a walk's (KD1 (b)).
@export var crouch_height_m := 0.0
@export var crouch_eye_height_m := 0.0
@export var crouch_speed_mps := 0.0
@export var crouch_fast_speed_mps := 0.0
## The direction caps of a move on the ground (#1334, art #196: the engineer's 3.0 and 2.0 m/s): its
## sideways part at most `side_speed_mps`, a move in the back family (Locomotion.family_of) at
## most `back_speed_mps`, its diagonals too; 0 is no cap. Client-honoured: the own controller
## keeps them, the host checks only the overall travel (§7), as for the crouch's speeds.
@export var side_speed_mps := 0.0
@export var back_speed_mps := 0.0
## The paths of the mode's maps on which a knockdown starts a motion: the host's physics moves the
## body (the knockdown rework's §4, KE12 (a)), empty for every map, the shape of TaskType.maps. On
## a map it leaves out a knockdown takes no launch and starts no host body. Each path must be one
## of the mode's maps. KD11's need (a body rests only where a crouching player fits, and a raised
## player gets up crouched) holds on every map: the crouch plays everywhere (#991).
@export var motion_maps: PackedStringArray = PackedStringArray()
## The rest (KE15): a motion ends once the reports stay slower than `rest_speed_mps` for `rest_s`
## (counted in reports), or once it has lasted `longest_motion_s` (counted in ticks). Placeholders,
## "not a decision" (KD9 (b)), as are their bounds.
@export var rest_speed_mps := 0.0
@export var rest_s := 0.0
@export var longest_motion_s := 0.0
## The bar's drunk scale (#1390; GDD §3 Base mode, "The bar"): PlayerState.drunk runs 0..drunk_max
## (at most 255, the wire's U8); Drink raises the fact `drunk_too_much` when a drink lifts it from
## below `drunk_too_much_at` to that or above; DrunkTicks lowers it one point per `drunk_point_s`.
## `drunk_max` 0 is a mode with no bar (Drink then is a mode problem). The values are the mode's
## data, provisional (the engineer tunes them on the hall greybox, #1354).
@export var drunk_max := 0
@export var drunk_too_much_at := 0
@export var drunk_point_s := 0.0


## The capsule's height of a player standing, or crouched where `crouched`.
func height_of(crouched: bool) -> float:
	return crouch_height_m if crouched else capsule_height_m


## The eye's height above the feet of a player standing, or crouched where `crouched`.
func eye_height_of(crouched: bool) -> float:
	return crouch_eye_height_m if crouched else eye_height_m


## Whether a knockdown on the map at `path` starts a motion (KE12): the list is empty or holds it.
func motion_plays_on(path: String) -> bool:
	return motion_maps.is_empty() or motion_maps.has(path)


func check(mode: GameMode) -> PackedStringArray:
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
			out_of_bounds("knockdown_s", knockdown_s, 1, 120),
			out_of_bounds("respawn_s", respawn_s, 1, 300),
			out_of_bounds("invulnerable_s", invulnerable_s, 0, 30),
			out_of_bounds("respawn_free_m", respawn_free_m, 0, 5),
			out_of_bounds("capsule_radius_m", capsule_radius_m, 0.1, 1),
			out_of_bounds("capsule_height_m", capsule_height_m, 0.5, 3),
			out_of_bounds("eye_height_m", eye_height_m, 0, capsule_height_m),
			out_of_bounds("step_height_m", step_height_m, 0, 1),
			out_of_bounds(
				"crouch_height_m", crouch_height_m, 2.0 * capsule_radius_m, capsule_height_m
			),
			out_of_bounds("crouch_eye_height_m", crouch_eye_height_m, 0, crouch_height_m),
			out_of_bounds("crouch_speed_mps", crouch_speed_mps, 0.1, walk_speed_mps),
			out_of_bounds(
				"crouch_fast_speed_mps", crouch_fast_speed_mps, crouch_speed_mps, walk_speed_mps
			),
			out_of_bounds("side_speed_mps", side_speed_mps, 0, sprint_speed_mps),
			out_of_bounds("back_speed_mps", back_speed_mps, 0, sprint_speed_mps),
			out_of_bounds("rest_speed_mps", rest_speed_mps, 0.01, 2),
			out_of_bounds("rest_s", rest_s, 0.05, 5),
			out_of_bounds("longest_motion_s", longest_motion_s, maxf(1.0, rest_s), 60),
		]
	)
	for map: String in motion_maps:
		if mode == null or not mode.maps.has(map):
			found.append("motion_maps lists %s, which is not one of the mode's maps" % map)
	if drunk_max != 0 or drunk_too_much_at != 0 or drunk_point_s != 0.0:
		append_found(
			found,
			[
				out_of_bounds("drunk_max", drunk_max, 1, 255),
				out_of_bounds("drunk_too_much_at", drunk_too_much_at, 1, drunk_max),
				out_of_bounds("drunk_point_s", drunk_point_s, 0.05, 60),
			]
		)
	return found
