class_name EngineProblemOpenedEvent
extends MatchEvent
## The ship's engine (ARCHITECTURE §4.2, §9.5.27; GDD §8): a problem opened at `stations`, its
## stations (StationPlaced's ids, ascending; one for most kinds, more for a kind whose problem
## spans several, the breakers' two boards). `problem` is its id within the match, unique from 1
## up: EngineProblemFixed names it. `deadline` is the host tick it blows on unless it is fixed by
## that tick's commands: a client counts down to it from its estimate of the host tick (the
## hologram's countdown). It names no player and no kind: the hologram shows where, not what (GDD
## §8). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The problem's id (1 up).
var problem: int
## Its stations' ids, ascending.
var stations: PackedInt32Array
## The host tick its timer runs out on.
var deadline: int


func _init(problem_id: int, station_ids: PackedInt32Array, deadline_tick: int) -> void:
	problem = problem_id
	stations = station_ids
	deadline = deadline_tick


func event_name() -> StringName:
	return &"EngineProblemOpened"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"problem": problem, "stations": stations.duplicate(), "deadline": deadline}
