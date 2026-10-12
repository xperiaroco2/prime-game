class_name LiftChangedEvent
extends MatchEvent
## The car repair's lift (ARCHITECTURE §4.2, §9.5; the car repair ADR's RE10, #807): a hold at the
## lift panel started (`up`: the car starts rising, fully up the type's `rise_seconds` later) or
## stopped (the drop, or the phase's end lowering it with no kill, RE4). `station` is the panel's
## station id (StationPlaced's), `tick` the host tick it happened on: a client derives the car's
## height from it and its own copy of `rise_seconds`. It names no player: nobody is told who holds
## or who let go (the ADR's §3), held apart from this declaration by a unit test. Audience:
## everyone (a client shows it only in the world, seen and heard within its range).

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The lift panel's station id.
var station: int
## Whether the car goes up (a hold started) or comes down (it stopped).
var up: bool
## The host tick of the start or the stop.
var tick: int


func _init(station_id: int, going_up: bool, at_tick: int) -> void:
	station = station_id
	up = going_up
	tick = at_tick


func event_name() -> StringName:
	return &"LiftChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "up": up, "tick": tick}
