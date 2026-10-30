class_name Strike
extends RuleEffect
## A hit on Use (ARCHITECTURE §7.1 "Hits", §9.4): the host picks the targets and damages each.
## A kind's own rule (the knife's) or the mode's fallback rule (the base hit of the empty hand and
## of every item without its own Use rule, #1437) runs it.
## The zone is the weapon's data: a horizontal sector from the attacker's last accepted position
## (its feet), `reach_m` long and `angle_deg` wide, centred on the horizontal part of the facing.
## A target is every living player other than the attacker (never a downed one: strikes skip the
## downed, vision revision 1; never an invulnerable one, for PlayerRules.invulnerable_s after a
## respawn or a revive: PlayerState.is_invulnerable, which nothing ends early, not even the
## player's own attack, the engineer's answer 3 on PR #133; never a limp one, #1393) such that:
## - its capsule (the mode's PlayerRules radius and height, standing on its last accepted
##   position) has a point in the sector, measured horizontally: its circle of `capsule_radius_m`
##   around its position touches the sector;
## - its capsule overlaps the attacker's vertically: with `dy` its feet less the attacker's,
##   -h(target) <= dy <= h(attacker), each `h` its own capsule's height, crouch_height_m while
##   crouched (the crouch ADR, KE2, KD7 (a));
## - the line from the attacker's eye (Items.eye_of, crouched or not) to the middle of its own
##   capsule, crouched or not, is clear (WorldQuery.line_of_sight).
## Each target then takes damage_to's amount through the life rule (LifeRules.damage), in peer-id
## order: `damage` from the front, `back_damage` from behind (is_behind), or the two-handed pair
## while the attacker's hand item is two-handed and `two_handed_damage` is set; at 0
## health it is knocked down there (KnockedDown, Correction; nothing drops). A target no longer
## alive when its turn comes (what an earlier target's damage set off downed or killed it) is
## skipped.
##
## The facing is the Use's `facing`, a claim: harmless, because the positions are the host's. A
## Use without a finite, non-zero facing uses the last accepted claim's. A facing with no
## horizontal part (straight up or down) leaves only the sector's apex: it touches only a capsule
## that overlaps the attacker's. No lag compensation (§7.1).
##
## Emits: Swung (everyone, with the zone's horizontal direction as a unit vector, or zero when
## the facing has none), even with no target, before any damage; per target Damaged and
## SelfStatus (the victim); a knockdown KnockedDown (everyone) and Correction (the downed), and on a
## map PlayerRules.motion_maps lists LaunchBody (server) with launch_of's velocity (KE9). The
## attacker learns nothing of a hit but a knockdown, which everyone learns (an accepted exception).

## How far below 0 the cosine of is_behind's angle must lie: exactly 90° stays the front.
const BEHIND_EPSILON := 1e-6

## Degrees, 1 to 360. The neutral default is refused by the mode check: the data sets it.
@export var angle_deg := 0.0
## Metres, 0.1 to 10, horizontal, from the attacker's feet. Neutral default: the data sets it.
@export var reach_m := 0.0
## Whole points, 1 to 1000: the damage of a hit from the front. Neutral default: the data sets it.
@export var damage := 0
## Whole points, 0 to 1000: the damage of a hit from behind (is_behind); 0 means `damage`.
@export var back_damage := 0
## Whole points, 0 to 1000: the front damage while the attacker's hand item is two-handed
## (ItemKind.is_two_handed), with `two_handed_back_damage` from behind (0 means
## `two_handed_damage`). 0 (the default) means such a hand hits as any other: `damage` and
## `back_damage`. The mode's one fallback rule carries both pairs, since the dispatch reaches only
## a mode's first Use rule (Match._find_action takes the first rule by trigger).
@export var two_handed_damage := 0
@export var two_handed_back_damage := 0
## The launch of a blow that knocks its target down (the knockdown rework's KD2, KE9): metres per
## second away from the attacker, horizontally, and upwards. 0 launches nothing (the default); a
## knockdown on a map PlayerRules.motion_maps leaves out drops it. Bounds 0 to 20 and 0 to 10,
## placeholders, "not a decision" (KD9 (b)).
@export var launch_mps := 0.0
@export var launch_up_mps := 0.0


func run(ctx: MatchContext) -> void:
	var attacker := ctx.actor_state()
	if attacker == null:
		ctx.error("Strike: no player %d" % ctx.actor)
		return
	if ctx.state.player_rules == null:
		ctx.error("Strike: the mode has no PlayerRules")
		return
	var facing := attacker.facing
	if ctx.command != null:
		var claimed := ctx.command.get_vector3("facing", Vector3.INF)
		if claimed.is_finite() and not claimed.is_zero_approx():
			facing = claimed
	var hit := targets(ctx, attacker, facing)
	var ahead := horizontal(facing)
	ctx.emit(SwungEvent.new(attacker.peer, Vector3(ahead.x, 0.0, ahead.y)))
	for peer: int in hit:
		# A target no longer alive when its turn comes is skipped (a defensive check behind the
		# kill queue, the car repair ADR's RE17): damage() would log a rule error for it.
		if not ctx.state.players[peer].is_alive() or ctx.state.players[peer].is_limp():
			continue
		var launch := launch_of(attacker, ctx.state.players[peer], ahead)
		var amount := damage_to(ctx, attacker, ctx.state.players[peer])
		LifeRules.damage(ctx, peer, Ticks.thousandths(amount), launch)


## The whole points `target` takes from this blow. The pair is `two_handed_damage` and
## `two_handed_back_damage` while the attacker's hand item is two-handed and `two_handed_damage` is
## set, else `damage` and `back_damage`; then the pair's back value from behind (is_behind) when
## set, else its front value. Judged per target at its turn, from the state of that tick.
func damage_to(ctx: MatchContext, attacker: PlayerState, target: PlayerState) -> int:
	var front := damage
	var back := back_damage
	var held := Items.held_by(ctx.state, attacker.peer)
	if two_handed_damage > 0 and held != null and held.kind.is_two_handed():
		front = two_handed_damage
		back = two_handed_back_damage
	if back > 0 and is_behind(attacker, target):
		return back
	return front


## Whether `attacker` stands in `target`'s rear half (the engineer's answer on #1437,
## issuecomment-6528751037): the angle between the target's facing and the horizontal direction
## from the target's feet to the attacker's is over 90°. The positions are the host's last accepted
## ones; the facing is the target's last accepted claim (Vector3.FORWARD before its first), a claim
## like the attacker's own facing. Exactly 90°, within float rounding, is the front; so is a target
## with no horizontal facing, and an attacker on the target's own spot.
static func is_behind(attacker: PlayerState, target: PlayerState) -> bool:
	var facing := horizontal(target.facing)
	var away := Vector2(
		attacker.position.x - target.position.x, attacker.position.z - target.position.z
	)
	if facing.is_zero_approx() or away.is_zero_approx():
		return false
	return facing.dot(away.normalized()) < -BEHIND_EPSILON


## The launch `target` takes if this blow knocks it down (KE9): `launch_mps` horizontally from the
## attacker's feet towards the target's (both last accepted positions); where they coincide along
## `ahead` (the zone's horizontal direction), and with no `ahead` none; plus `launch_up_mps` up.
func launch_of(attacker: PlayerState, target: PlayerState, ahead: Vector2) -> Vector3:
	var away := Vector2(
		target.position.x - attacker.position.x, target.position.z - attacker.position.z
	)
	var flat := ahead if away.is_zero_approx() else away.normalized()
	return Vector3(flat.x * launch_mps, launch_up_mps, flat.y * launch_mps)


## The living players other than `attacker`, not invulnerable at this tick, in this weapon's zone
## along `facing`, in peer-id order.
func targets(ctx: MatchContext, attacker: PlayerState, facing: Vector3) -> Array[int]:
	var rules := ctx.state.player_rules
	var ahead := horizontal(facing)
	var apex := Vector2(attacker.position.x, attacker.position.z)
	var half := deg_to_rad(clampf(angle_deg, 0.0, 360.0) / 2.0)
	var found: Array[int] = []
	var eye := Vector3.INF
	for peer: int in ctx.state.peers():
		var target := ctx.state.players[peer]
		if peer == attacker.peer or not target.is_alive() or target.is_limp():
			continue
		if target.is_invulnerable(ctx.tick):
			continue
		var dy := target.position.y - attacker.position.y
		if dy < -rules.height_of(target.crouched) or dy > rules.height_of(attacker.crouched):
			continue
		var centre := Vector2(target.position.x, target.position.z)
		if _distance_to_sector(centre, apex, ahead, half) > rules.capsule_radius_m:
			continue
		if eye == Vector3.INF:
			eye = Items.eye_of(ctx, attacker)
		var middle := target.position + Vector3.UP * (rules.height_of(target.crouched) / 2.0)
		if not ctx.world.line_of_sight(eye, middle):
			continue
		found.append(peer)
	return found


## The horizontal direction of `facing` as a unit vector, or zero when it has none (straight up
## or down, or not finite). Scaled before normalising, so a huge finite claim still gives a unit.
static func horizontal(facing: Vector3) -> Vector2:
	var flat := Vector2(facing.x, facing.z)
	if not flat.is_finite():
		return Vector2.ZERO
	var largest := maxf(absf(flat.x), absf(flat.y))
	if largest == 0.0:
		return Vector2.ZERO
	return (flat / largest).normalized()


func emits() -> Array[Script]:
	return [
		SwungEvent,
		DamagedEvent,
		SelfStatusEvent,
		KnockedDownEvent,
		CorrectionEvent,
		LaunchBodyEvent
	]


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(
		found,
		[
			out_of_bounds("Strike angle_deg", angle_deg, 1, 360),
			out_of_bounds("Strike reach_m", reach_m, 0.1, 10),
			out_of_bounds("Strike damage", damage, 1, 1000),
			out_of_bounds("Strike back_damage", back_damage, 0, 1000),
			out_of_bounds("Strike two_handed_damage", two_handed_damage, 0, 1000),
			out_of_bounds("Strike two_handed_back_damage", two_handed_back_damage, 0, 1000),
			out_of_bounds("Strike launch_mps", launch_mps, 0, 20),
			out_of_bounds("Strike launch_up_mps", launch_up_mps, 0, 10),
		]
	)
	return found


## The horizontal distance from `point` to the sector with its apex at `apex`, `reach_m` long,
## `half` radians either side of `ahead` (a unit vector, or zero: the apex alone). 0 inside.
func _distance_to_sector(point: Vector2, apex: Vector2, ahead: Vector2, half: float) -> float:
	var offset := point - apex
	var distance := offset.length()
	if half >= PI - 1e-9:
		return maxf(0.0, distance - reach_m)
	if not ahead.is_zero_approx():
		if distance == 0.0 or absf(ahead.angle_to(offset)) <= half + 1e-9:
			return maxf(0.0, distance - reach_m)
	# Outside the angle: the nearest point of the sector lies on one of its two straight edges.
	var left := _to_segment(point, apex, apex + ahead.rotated(half) * reach_m)
	var right := _to_segment(point, apex, apex + ahead.rotated(-half) * reach_m)
	return minf(left, right)


static func _to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var along := to - from
	var length_squared := along.length_squared()
	if length_squared == 0.0:
		return point.distance_to(from)
	var t := clampf((point - from).dot(along) / length_squared, 0.0, 1.0)
	return point.distance_to(from + along * t)
