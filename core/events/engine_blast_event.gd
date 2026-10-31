class_name EngineBlastEvent
extends MatchEvent
## The ship's engine (ARCHITECTURE §4.2, §9.5.27; GDD §8): a problem's timer ran out, and the
## blast went through the ship. Every open problem is gone with it (no EngineProblemFixed
## follows), and the engine stands on `stage` (1-based) after its drop, that stage's bar from its
## start (ZoneProgress follows). The knockdowns it caused follow as KnockedDown events. It names
## no player: the blast names nobody (GDD §8, the humans' spoils). Audience: everyone.

## The kind of audience() (ModeCheck reads it without an instance).
const AUDIENCE_KIND := Audience.Kind.EVERYONE

## The stage the engine stands on after the drop, 1 up.
var stage: int


func _init(stage_after: int) -> void:
	stage = stage_after


func event_name() -> StringName:
	return &"EngineBlast"


func audience() -> Audience:
	return Audience.everyone()


func to_dict() -> Dictionary:
	return {"stage": stage}
