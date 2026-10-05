class_name ClockEnded
extends Condition
## Passes once the match clock has reached its end (ARCHITECTURE §3.3, §3.4, §9.4): Match counts
## the clock down in phases whose clock runs and sets MatchState.clock_ended when it raises the
## fact `clock_ended`. Before StartClock ran there is no end, so it fails. Part of the
## dissidents' "time up"; win conditions check facts only, so it never rejects an intent.


## It reads the match clock, not the actor: a win condition may hold it.
func reads_actor_state() -> bool:
	return false


func _test(ctx: MatchContext) -> bool:
	return ctx.state.clock_ended
