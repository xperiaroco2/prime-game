class_name EndMirror
extends RuleEffect
## Every mirror place is given up (Mirror.leave_all; ARCHITECTURE §7.1.24, §9.4; #1394): a
## transition action on a row from a phase that lists MirrorTicks into one that does not (the base
## mode's Countdown -> Loading), so no place survives into a match (MirrorTicks.problems). None
## held: nothing happens.
##
## Emits: MirrorPlaces (everyone). No demands.


func run(ctx: MatchContext) -> void:
	Mirror.leave_all(ctx)


func emits() -> Array[Script]:
	return [MirrorPlacesEvent]
