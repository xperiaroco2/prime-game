class_name ZoneProgressEvent
extends MatchEvent
## A zone of the zone task (#36, ARCHITECTURE §4.2, §9.5) started or stopped counting, or is
## done (ZE4 of the zone task ADR): its ticks so far (after this tick's gain), the ticks it needs,
## whether it counts now, and the host tick this holds at. Between two events a client draws the
## fill from its estimate of the host tick, from `ticks` at `tick`, capped at `needed`; done is
## `ticks` == `needed`, not counting. Sent at most once per zone per ZoneTask.WINDOW_TICKS, done in
## its own tick. It names no player: anyone living counts, whatever the role (ZD3). Audience:
## everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The zone's station id (StationPlaced).
var station: int
var ticks: int
var needed: int
var counting: bool
## The host tick of this state.
var tick: int


func _init(
	station_id: int, ticks_so_far: int, needed_ticks: int, is_counting: bool, at_tick: int
) -> void:
	station = station_id
	ticks = ticks_so_far
	needed = needed_ticks
	counting = is_counting
	tick = at_tick


func event_name() -> StringName:
	return &"ZoneProgress"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {
		"station": station, "ticks": ticks, "needed": needed, "counting": counting, "tick": tick
	}
