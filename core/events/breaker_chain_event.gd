class_name BreakerChainEvent
extends MatchEvent
## The ship's engine's tripped breakers (ARCHITECTURE §4.2, §9.5.27; GDD §8 "Tripped breakers"):
## the breakers problem `problem` (EngineProblemOpened's id) and its chain after each change.
## `breakers` are the tripped breaker stations in the order to switch them back on (1 to 8 of
## them): the console's hologram plays that order to whoever looks (GDD §8: "Remember it, or a
## friend at the console reads it out"), so it is public. The first `next` of them are on; while
## `next` > 0, `since` is the host tick the green window of breaker `next - 1` is measured from
## (its lamp yellow for the kind's ramp, then green for its green seconds), else -1. Sent at the
## open (`next` 0), at each breaker switched on, and at each unwind of a chain too late (`next`
## one less). It names no player: a short circuit is the presser's KnockedDown alone. Audience:
## everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The problem's id.
var problem: int
## The tripped breaker stations, in the order to switch them on.
var breakers: PackedInt32Array
## How many of them are on (the first `next`).
var next: int
## The host tick the last one on's window is measured from, or -1 while none is on.
var since: int


func _init(problem_id: int, order: PackedInt32Array, on_count: int, since_tick: int) -> void:
	problem = problem_id
	breakers = order
	next = on_count
	since = since_tick


func event_name() -> StringName:
	return &"BreakerChain"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"problem": problem, "breakers": breakers.duplicate(), "next": next, "since": since}
