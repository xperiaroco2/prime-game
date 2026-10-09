class_name ItemFlight
extends RefCounted
## A thrown item's flight (ARCHITECTURE §7.1.16; the throwing ADR, TE3 under TD9 (a)): what the
## launch fixed, kept in ItemState.flight while the item is FLYING, as Channels keeps a raise.
##
## The arc is p(n) = o + v·s + ½·g·s², s = float(n) / Ticks.RATE seconds after the launch, each
## point computed from the stored vectors by point(), never integrated step by step, so no error
## adds up and a client that calls point() with the vectors ItemThrown carries gets the host's
## points bit for bit. o, v and g are set once at the launch, as the Vector3s ItemThrown carries;
## nothing recomputes them from a rule's numbers.
##
## `ticks` is the flight's own count of ticks flown, which only FlightTicks advances: none in the
## launch tick L (`launch_tick`), one in each later tick of a phase that lists FlightTicks. So
## after tick L + k of such a phase, `ticks` is k and the item has flown to p(k); a phase without
## FlightTicks pauses the flight, and a later one resumes it where it stopped.

## o: where the item leaves the thrower's eye (Items.eye_of).
var origin := Vector3.ZERO
## v: metres per second.
var velocity := Vector3.ZERO
## g: metres per second squared, straight down.
var gravity := Vector3.ZERO
## n: the ticks flown so far.
var ticks := 0
## f: where the item rests when its flight ends over no floor (TD11 (a)): the floor below the
## thrower's feet at the launch (Items.fallback_rest), asked once then.
var fallback := Vector3.ZERO
## The thrower's peer id: the one living player the item flies through. Only the id is kept: the
## thrower being knocked down, dying or leaving does not touch the flight.
var thrower := 0
## The item's collision radius in metres: the sphere swept through the world, and the widening of
## each player's capsule.
var radius := 0.0
## The longest flight in ticks: a flight not ended by then stops at p(max_ticks).
var max_ticks := 0
## The tick L of the launch (Items.launch sets it): FlightTicks does not advance the flight in it.
var launch_tick := 0


func _init(
	from: Vector3 = Vector3.ZERO,
	speed: Vector3 = Vector3.ZERO,
	down: Vector3 = Vector3.ZERO,
	rest_fallback: Vector3 = Vector3.ZERO,
	thrower_peer: int = 0,
	item_radius: float = 0.0,
	longest_ticks: int = 0
) -> void:
	origin = from
	velocity = speed
	gravity = down
	fallback = rest_fallback
	thrower = thrower_peer
	radius = item_radius
	max_ticks = longest_ticks


## The arc's point `n` ticks after the launch: the one function host and clients call.
static func point(from: Vector3, speed: Vector3, down: Vector3, n: int) -> Vector3:
	# Both are ints: an integer division would give s = 0 for the whole first second.
	var s := float(n) / Ticks.RATE
	return from + speed * s + down * (0.5 * s * s)


## This flight's point `n` ticks after the launch.
func at(n: int) -> Vector3:
	return point(origin, velocity, gravity, n)
