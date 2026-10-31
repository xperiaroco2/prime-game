class_name BreakerSwitchedEvent
extends MatchEvent
## The ship's engine's tripped breakers (ARCHITECTURE §4.2, §9.5.27; GDD §8, the chain): the
## breaker `station` went `on` at host tick `tick` (its lamp ramps from yellow to green from then:
## the client's copy of the kind's ramp and green seconds), or tripped again (`on` false: the chain
## was too late). It names no player: a short circuit is the presser's KnockedDown alone. Audience:
## everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The breaker station.
var station: int
## Whether it is on now.
var on: bool
## The host tick it switched.
var tick: int


func _init(station_id: int, is_on: bool, at_tick: int) -> void:
	station = station_id
	on = is_on
	tick = at_tick


func event_name() -> StringName:
	return &"BreakerSwitched"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "on": on, "tick": tick}
