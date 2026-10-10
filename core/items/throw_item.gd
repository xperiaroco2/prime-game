class_name ThrowItem
extends RuleEffect
## The actor's hand item leaves its eye into a flight (ARCHITECTURE §7.1.16, §9.4; the throwing
## ADR, TE4, TD1 (a), TD10 (a)). The client sends only its facing, and the host takes nothing
## else from it: a facing that does not normalize to a unit vector (not finite, zero, or one whose
## squared length under- or overflows in single precision) takes the actor's last accepted claim's
## (PlayerState.facing, a unit vector, as MovementRule stores it). The origin is Items.eye_of (the
## floor below the last accepted position plus the eye height, so a jump does not raise it), the
## velocity is the facing times `speed_mps` and the gravity `gravity_mps2` straight down; the
## actor's own velocity is not added, so the range never depends on a claim. The pitch is not
## clamped: straight up is a legal lob.
##
## The flight keeps those Vector3s, its fallback rest (Items.fallback_rest, asked here), the
## thrower, `radius_m` and the longest flight in ticks; Items.launch releases the item, and
## ItemThrown carries exactly the flight's vectors, so a client's points are the host's bit for
## bit. FlightTicks, which a phase that accepts a throw must list, flies it from the next tick.
##
## Run it after HoldsItem (`empty_hand`: a belt item is never thrown) and OverFloor (`no_floor`);
## ModeCheck requires both, and only in a player's intent. With no floor below the actor anyway,
## the match logs an error and nothing is thrown, so no item ever hangs in the air.
##
## Emits: ItemThrown (everyone). The flight's rest emits ItemPlaced (FlightTicks).

## Metres per second, 1 to 40 (TD1 (a): one speed per rule). Each neutral default is out of
## bounds on purpose: the data sets it, so the mode check refuses a rule that forgot it. The
## bounds are placeholders, "not a decision"; the base mode's numbers (content/, #646) are the
## engineer's provisional ones.
@export var speed_mps := 0.0
## Metres per second squared, 1 to 40, straight down.
@export var gravity_mps2 := 0.0
## The item's collision radius in metres, 0.02 to 0.5, and no more than largest_radius() of the
## mode's PlayerRules, so the sphere at the eye stays inside the thrower's capsule (TE2).
@export var radius_m := 0.0
## Seconds, 0.5 to 30: a flight not ended by then stops at its last point and drops (TD11).
## Converted once to ticks (Ticks.from_seconds, toward zero) when the item is thrown.
@export var longest_flight_s := 0.0


func run(ctx: MatchContext) -> void:
	var actor := ctx.actor_state()
	if actor == null:
		ctx.error("ThrowItem: no player %d" % ctx.actor)
		return
	if ctx.state.player_rules == null:
		ctx.error("ThrowItem: the mode has no PlayerRules")
		return
	var item := Items.held_by(ctx.state, ctx.actor)
	if item == null:
		ctx.error("ThrowItem: player %d holds no item" % ctx.actor)
		return
	var claimed := Vector3.INF
	if ctx.command != null:
		claimed = ctx.command.get_vector3("facing", Vector3.INF)
	var facing := unit_facing(claimed, actor.facing)
	var fallback := Items.fallback_rest(ctx, actor.position)
	if fallback == WorldQuery.NO_FLOOR:
		(
			ctx
			. error(
				(
					(
						"ThrowItem: no floor below player %d at %s, so nothing is thrown: the rule needs"
						+ " OverFloor"
					)
					% [ctx.actor, actor.position]
				)
			)
		)
		return
	var flight := ItemFlight.new(
		Items.eye_of(ctx, actor),
		facing * speed_mps,
		Vector3(0.0, -gravity_mps2, 0.0),
		fallback,
		ctx.actor,
		radius_m,
		maxi(1, Ticks.from_seconds(longest_flight_s))
	)
	Items.launch(ctx, item, flight)
	ctx.emit(
		ItemThrownEvent.new(
			item.id, ctx.actor, flight.origin, flight.velocity, flight.gravity, flight.launch_tick
		)
	)


## The direction a throw takes: `claimed` normalized when that is a unit vector, else `last` (the
## last accepted claim's facing). Not scaled before normalizing, unlike MovementRule's stored
## facing: a claim whose squared length under- or overflows in single precision normalizes to
## zero, and is refused as the throwing ADR (TE4) says.
static func unit_facing(claimed: Vector3, last: Vector3) -> Vector3:
	if claimed.is_finite():
		var unit := claimed.normalized()
		if unit.is_normalized():
			return unit
	return last


## The largest item radius a throw may have with `rules`' capsule: the sphere at the eye must stay
## inside it, sideways (the capsule's radius) and above (the height less the eye height), less
## WorldQuery.THROW_RADIUS_MARGIN_M (the throwing ADR, TE2).
static func largest_radius(rules: PlayerRules) -> float:
	return (
		minf(rules.capsule_radius_m, rules.capsule_height_m - rules.eye_height_m)
		- WorldQuery.THROW_RADIUS_MARGIN_M
	)


## The condition classes a rule holding this effect must hold, not negated (ModeCheck): HoldsItem,
## so a belt item is never thrown, and OverFloor, so no throw leaves its item in the air.
func required_conditions() -> Array[Script]:
	return [HoldsItem, OverFloor]


func emits() -> Array[Script]:
	return [ItemThrownEvent]


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(
		found,
		[
			out_of_bounds("ThrowItem speed_mps", speed_mps, 1, 40),
			out_of_bounds("ThrowItem gravity_mps2", gravity_mps2, 1, 40),
			out_of_bounds("ThrowItem radius_m", radius_m, 0.02, 0.5),
			out_of_bounds("ThrowItem longest_flight_s", longest_flight_s, 0.5, 30),
		]
	)
	# No PlayerRules: GameMode's own check reports it.
	if mode != null and mode.player_rules != null:
		var largest := largest_radius(mode.player_rules)
		if radius_m > largest:
			found.append(
				(
					(
						"ThrowItem radius_m is %s, more than %s: the sphere at the eye would stick"
						+ " out of the player's capsule (its radius, or its height above the eye,"
						+ " less THROW_RADIUS_MARGIN_M)"
					)
					% [number(radius_m), number(largest)]
				)
			)
	return found
