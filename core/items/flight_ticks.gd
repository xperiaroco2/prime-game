class_name FlightTicks
extends TickSystem
## The tick system of thrown items (ARCHITECTURE §7.1.16, §9.4; the throwing ADR, TE3 under TD9
## (a)): every tick of the phase that lists it, each item in flight, in id order, flies one more
## tick, except in its launch tick (Items.launch): ItemFlight.ticks goes from n - 1 to n, and the
## segment from p(n - 1) to p(n) (ItemFlight.point) is swept for the first contact:
##
## - the world: WorldQuery.sweep with the flight's radius, which answers the segment's end when
##   nothing is in the way, so any other answer is a contact there;
## - a living player other than the thrower (TD3 (b)): the PlayerRules capsule standing at that
##   player's last accepted position, widened by the flight's radius, tested here in core/, with no
##   lag compensation, as hits read it (§7.1.10). An invulnerable player stops it too (a stop is
##   not damage); the downed, the dead and the gone are flown over (TD12 (a)). On the part of the
##   segment the world leaves, so a wall and a player at the same point is the world's stop.
##
## A flight that has not ended within its longest flight (ItemFlight.max_ticks) stops at its last
## point. The item then drops to WorldQuery.floor_below of the stop point, lifted (Items.lifted),
## and rests there through Items.place with the cause `thrown` (ItemPlaced, then item_rested, so
## Delivery's check runs as for any rest). With no floor below the stop, it rests at the flight's
## fallback, the floor below the thrower's feet at the launch (TD11 (a)), and the match logs an
## error: a level with a hole.
##
## A phase that does not list it pauses every flight: the count of ticks flown is the flight's own,
## so a later phase that lists it resumes each flight where it stopped. The thrower's life and
## presence are never read, only its id. Each item asks one sweep a tick and, at its end, one
## floor_below, in id order, so the command log replays them in the same order.
##
## Emits: ItemPlaced, and what the rules on item_rested emit. No demands.


func run(ctx: MatchContext) -> void:
	advance(ctx)


func emits() -> Array[Script]:
	return [ItemPlacedEvent]


## One tick of every item in flight, in id order.
static func advance(ctx: MatchContext) -> void:
	var ids: Array[int] = []
	for id: int in ctx.state.items:
		if ctx.state.items[id].is_in_flight():
			ids.append(id)
	ids.sort()
	for id: int in ids:
		var item: ItemState = ctx.state.items.get(id)
		# Rested meanwhile, by what an earlier item's rest set off in this tick.
		if item == null or not item.is_in_flight():
			continue
		# The launch tick: the flight starts at p(0) and leaves it on the next tick.
		if ctx.tick <= item.flight.launch_tick:
			continue
		_fly(ctx, item)


## The fraction t in [0, 1] of the segment from `from` to `to` at which a sphere of `radius` moving
## along it first touches the capsule of `capsule_radius` and `capsule_height` (Godot's height,
## caps included) standing with its feet at `feet`: 0 when it touches it at `from`, -1 when it
## never does. A capsule lower than its two caps is taken as a ball at half its height.
static func contact_fraction(
	from: Vector3,
	to: Vector3,
	feet: Vector3,
	capsule_radius: float,
	capsule_height: float,
	radius: float
) -> float:
	var reach := capsule_radius + radius
	var low := feet.y + capsule_radius
	var high := feet.y + capsule_height - capsule_radius
	if high < low:
		low = feet.y + capsule_height / 2.0
		high = low
	var on_axis := Vector3(feet.x, clampf(from.y, low, high), feet.z)
	if from.distance_to(on_axis) <= reach:
		return 0.0
	var along := to - from
	var best := INF
	# The side: the upright cylinder of `reach` around the axis, entered between the axis' ends.
	# Entered through its top or bottom instead, the point is already in an end's ball.
	var side := _entry(
		Vector3(from.x - feet.x, 0.0, from.z - feet.z), Vector3(along.x, 0.0, along.z), reach
	)
	if side >= 0.0 and side <= 1.0:
		var y := from.y + along.y * side
		if y >= low and y <= high:
			best = side
	# The ends: a ball of `reach` around each end of the axis.
	for end_y: float in [low, high]:
		var end := _entry(from - Vector3(feet.x, end_y, feet.z), along, reach)
		if end >= 0.0 and end <= 1.0 and end < best:
			best = end
	return best if best != INF else -1.0


## One more tick of `item`'s flight; at its first contact, or at its longest flight, the rest.
static func _fly(ctx: MatchContext, item: ItemState) -> void:
	var flight := item.flight
	var from := flight.at(flight.ticks)
	flight.ticks += 1
	var to := flight.at(flight.ticks)
	var stop := ctx.world.sweep(from, to, flight.radius)
	# sweep answers `to` itself when nothing is in the way.
	var ended := stop != to
	var hit := _first_player_contact(ctx, flight, from, stop)
	if hit >= 0.0:
		ended = true
		if hit < 1.0:
			stop = from.lerp(stop, hit)
	if not ended and flight.ticks >= flight.max_ticks:
		ended = true
	if ended:
		_rest(ctx, item, stop)


## The earliest contact fraction on the segment from `from` to `to` with a living player other
## than the thrower, or -1. Peers in id order, so of two players met at the same point the lower
## id's is taken (both give the same stop).
static func _first_player_contact(
	ctx: MatchContext, flight: ItemFlight, from: Vector3, to: Vector3
) -> float:
	var rules := ctx.state.player_rules
	var best := -1.0
	for peer: int in ctx.state.peers():
		var player := ctx.state.players[peer]
		if peer == flight.thrower or not player.is_alive():
			continue
		var t := contact_fraction(
			from, to, player.position, rules.capsule_radius_m, rules.capsule_height_m, flight.radius
		)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## `item` drops to the floor below `stop` and rests there with the cause `thrown`; with no floor
## there, at the flight's fallback.
static func _rest(ctx: MatchContext, item: ItemState, stop: Vector3) -> void:
	var flight := item.flight
	var rest := ctx.world.floor_below(Items.lifted(stop))
	if rest == WorldQuery.NO_FLOOR:
		var where := "flight: no floor below %s for item %d" % [stop, item.id]
		if flight.fallback.is_finite():
			ctx.error("%s: it rests below its thrower's feet, at %s" % [where, flight.fallback])
			rest = flight.fallback
		else:
			ctx.error("%s, nor below its thrower: it rests there" % where)
			rest = stop
	Items.place(ctx, item, rest, Items.THROWN)


## The least t >= 0 at which `start + t * along` comes within `reach` of the origin, or -1 when it
## never does or `start` already is (the caller checked that).
static func _entry(start: Vector3, along: Vector3, reach: float) -> float:
	var a := along.dot(along)
	var c := start.dot(start) - reach * reach
	if a == 0.0 or c <= 0.0:
		return -1.0
	var b := 2.0 * start.dot(along)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	return (-b - sqrt(discriminant)) / (2.0 * a)
