class_name AllSubtasksDone
extends Condition
## Passes when every task of the match is done (ARCHITECTURE §3.4, §9.4): Tasks.all_done, so a
## task with no subtasks is done, and with no tasks at all it holds (the engineer's rule of
## 2026-09-30, #79). The crew's win condition ("every task done") and, negated, part of the
## dissidents' "time up". Tasks are shared and their progress is public, so it reads nothing
## hidden. Used by win conditions, which check facts only: it never rejects an intent.


func _test(ctx: MatchContext) -> bool:
	return Tasks.all_done(ctx.state)
