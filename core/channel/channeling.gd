class_name Channeling
extends Condition
## Passes when the actor runs a channel (ARCHITECTURE §9.4; M4-4): the condition of the base
## mode's StopRaise, whose rule then stops it as every applied action of its actor does (§9.2).
## Rejects with `not_channeling`: the sender knows what it holds (a raise that just completed or
## stopped answers a late StopRaise with it).

const NOT_CHANNELING := &"not_channeling"


func _test(ctx: MatchContext) -> bool:
	return Channels.of_actor(ctx.state, ctx.actor) != null


func _reason() -> StringName:
	return NOT_CHANNELING
