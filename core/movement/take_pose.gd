class_name TakePose
extends RuleEffect
## The actor takes the seated pose where it stands (#1296; GDD §12 "The camera wall": the watcher
## sits in the chair; ARCHITECTURE §7.1.19, §9.4): PlayerState.posed, which every peer's snapshot
## shows on its avatar. The rule's conditions decide where it may; this effect checks nothing, and
## a second Pose while posed changes nothing. Any own move ends the pose (MovementRule), as do a
## placement, a knockdown, a respawn and a reset. As every applied action does, it stops the
## actor's running channel first (RuleRunner: a raiser who sits down stops its raise).
##
## Emits: nothing (the flag travels in the snapshot, public body state).


func run(ctx: MatchContext) -> void:
	ctx.state.player(ctx.actor).posed = true


func emits() -> Array[Script]:
	return []
