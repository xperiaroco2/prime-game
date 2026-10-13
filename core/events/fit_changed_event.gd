class_name FitChangedEvent
extends MatchEvent
## The car repair's fit (ARCHITECTURE §4.2, §9.5; the car repair ADR's §2.4 and RE10, #808): a fit
## at the car started (`fitter` the fitting player's peer id) or stopped before it completed
## (`fitter` 0; the fit's progress is lost, RD10 (d)). A completed fit sends PartFitted instead.
## `station` is the car's station id (StationPlaced's), `tick` the host tick it happened on: the
## fitter's client derives its own progress from it and its copy of the fit's seconds. It names the
## fitter, so a client can draw the crouched fitter at work on its avatar; the engineer accepted
## that every client learns who fits (RD15 (a)). An honest client shows it only on the avatar in
## the world, and nothing at the lift panel reads it (the ADR's §3, RD14 (a)). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The car's station id.
var station: int
## The fitting player's peer id, or 0 when the fit stopped.
var fitter: int
## The host tick of the start or the stop.
var tick: int


func _init(station_id: int, fitter_peer: int, at_tick: int) -> void:
	station = station_id
	fitter = fitter_peer
	tick = at_tick


func event_name() -> StringName:
	return &"FitChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"station": station, "fitter": fitter, "tick": tick}
