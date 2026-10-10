class_name PhaseChangedEvent
extends MatchEvent
## Every transition (ARCHITECTURE §4.2): the new phase and, if one runs, the countdown's or the
## match clock's end as a host tick. It names only the phase: an outcome and its argument reach
## no peer through it (§9.2; MatchEnded names the win condition, #548). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

var phase: StringName
## The host tick on which the phase's countdown or the match clock ends, or -1.
var end_tick := -1


func _init(phase_id: StringName, ends_at: int) -> void:
	phase = phase_id
	end_tick = ends_at


func event_name() -> StringName:
	return &"PhaseChanged"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"phase": phase, "end_tick": end_tick}
