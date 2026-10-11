class_name ItemThrownEvent
extends MatchEvent
## A held item left its thrower's hand into a flight (ARCHITECTURE §4.2, §7.1.16; the throwing
## ADR, TE6): the item, the thrower, and what the launch fixed, exactly as the flight keeps it, so a
## client computes the host's arc bit for bit with ItemFlight.point(origin, velocity, gravity, n),
## n being the host tick less `tick`. Audience: everyone: the item was in a hand everyone sees,
## items are public (§5), and the velocity shows only the look the snapshot's facing already
## shows. That holds while the Throw rule is the item kind's or the mode's: a role-owned one would
## put the role into the exact speed and gravity (§9.2; ModeCheck warns).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var item: int
## The thrower's peer id.
var peer: int
## Where the item leaves the thrower's eye (Items.eye_of).
var origin: Vector3
## Metres per second: the facing, normalized, times the rule's speed.
var velocity: Vector3
## Metres per second squared, straight down.
var gravity: Vector3
## The launch tick L: after host tick L + k the item has flown to p(k).
var tick: int


func _init(
	item_id: int, thrower: int, from: Vector3, speed: Vector3, down: Vector3, launch_tick: int
) -> void:
	item = item_id
	peer = thrower
	origin = from
	velocity = speed
	gravity = down
	tick = launch_tick


func event_name() -> StringName:
	return &"ItemThrown"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {
		"item": item,
		"peer": peer,
		"origin": origin,
		"velocity": velocity,
		"gravity": gravity,
		"tick": tick,
	}
