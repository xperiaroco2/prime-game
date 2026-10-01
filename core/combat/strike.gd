class_name Strike
extends RuleEffect
## A weapon's hit (ARCHITECTURE §7.1 "Hits", §9.4): the host picks the targets and damages each.
## The zone is the weapon's data: a horizontal sector from the attacker's last accepted position
## (its feet), `reach_m` long and `angle_deg` wide, centred on the horizontal part of the facing.
## A target is every living player other than the attacker (never a downed one: strikes skip the
## downed, vision revision 1; never an invulnerable one, for PlayerRules.invulnerable_s after a
## respawn or a revive: PlayerState.is_invulnerable, which nothing ends early, not even the
## player's own attack, the engineer's answer 3 on PR #133) such that:
## - its capsule (the mode's PlayerRules radius and height, standing on its last accepted
##   position) has a point in the sector, measured horizontally: its circle of `capsule_radius_m`
##   around its position touches the sector;
## - its capsule overlaps the attacker's vertically (neither stands a full height above the other);
## - the line from the attacker's eye (Items.eye_of) to the middle of its capsule is clear
##   (WorldQuery.line_of_sight).
## Each target then takes `damage` through the life rule (LifeRules.damage), in peer-id order; at 0
## health it is knocked down there (KnockedDown, Correction; nothing drops).
##
## The facing is the Use's `facing`, a claim: harmless, because the positions are the host's. A
## Use without a finite, non-zero facing uses the last accepted claim's. A facing with no
## horizontal part (straight up or down) leaves only the sector's apex: it touches only a capsule
## that overlaps the attacker's. No lag compensation (§7.1).
##
## Emits: Swung (everyone, with the zone's horizontal direction as a unit vector, or zero when
## the facing has none), even with no target, before any damage; per target Damaged and
## SelfStatus (the victim); a knockdown KnockedDown (everyone) and Correction (the downed). The
## attacker learns nothing of a hit but a knockdown, which everyone learns (an accepted exception).

## Degrees, 1 to 360. The neutral default is refused by the mode check: the data sets it.
@export var angle_deg := 0.0
## Metres, 0.1 to 10, horizontal, from the attacker's feet. Neutral default: the data sets it.
@export var reach_m := 0.0
## Whole points, 1 to 1000. Neutral default: the data sets it.
@export var damage := 0


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
		LifeRules.damage(ctx, peer, Ticks.thousandths(damage))


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
		if peer == attacker.peer or not target.is_alive() or target.is_invulnerable(ctx.tick):
			continue
		if absf(target.position.y - attacker.position.y) > rules.capsule_height_m:
			continue
		var centre := Vector2(target.position.x, target.position.z)
		if _distance_to_sector(centre, apex, ahead, half) > rules.capsule_radius_m:
			continue
		if eye == Vector3.INF:
			eye = Items.eye_of(ctx, attacker)
		var middle := target.position + Vector3.UP * (rules.capsule_height_m / 2.0)
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
	return [SwungEvent, DamagedEvent, SelfStatusEvent, KnockedDownEvent, CorrectionEvent]


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(
		found,
		[
			out_of_bounds("Strike angle_deg", angle_deg, 1, 360),
			out_of_bounds("Strike reach_m", reach_m, 0.1, 10),
			out_of_bounds("Strike damage", damage, 1, 1000),
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
