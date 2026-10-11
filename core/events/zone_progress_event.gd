class_name ZoneProgressEvent
extends MatchEvent
## A station's progress (ARCHITECTURE §4.2, §9.5): a zone of the zone task (#36) or the
## Generator's charge (#797, the Generator ADR's GE7) started or stopped counting, or is done (ZE4
## of the zone task ADR); the Generator's also at the deal, at 0 (at its full value when dealt with
## no switch, GE9). Its ticks counted through host tick `tick`, the ticks it needs, and whether it
## counts in the ticks after `tick` (a zone's event follows that tick's gain; a start or stop of the
## charge in a command comes before it, so its `tick` is the one before). Between two events a
## client draws the fill from its estimate of the host tick, from `ticks` at `tick`, capped at
## `needed`; done is `ticks` == `needed`, not counting. Sent at most once per station per
## ZoneTask.WINDOW_TICKS (Generator.WINDOW_TICKS, the same), done in its own tick. It names no
## player: anyone living counts or charges, whatever the role (ZD3; row 20 of the Generator
## ADR). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The station's id (StationPlaced): the zone's, or the generator's.
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
