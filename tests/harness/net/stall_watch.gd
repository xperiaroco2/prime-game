class_name StallWatch
extends RefCounted
## When the running side of a stall dropped the stalled side, judged at the running side's own
## polls (#443). A transport drops a peer only inside a poll: ENet at a resend check of a service,
## WebRtcTransport's silence rule once per poll. A main-thread hitch on a loaded PC (verifies
## beside each other) delays the poll the drop comes in, so the wall-clock time of the drop can
## pass a window's top by the hitch although the transport dropped the peer at its first chance
## (a pair 3 drop 21649 ms after the stall, 649 ms over the top, beside two other verifies).
## So the top is judged at the last poll before the drop: if that poll still had the stalled side
## past the top, the transport kept a peer it should have dropped. The bottom stays the wall clock
## of the drop: a hitch only makes a drop later, never earlier.
##
## The owner calls serviced(<start of the poll>) after each poll of the running side, stall() when
## the other side stops and drop() from the running side's drop signal (which comes inside a poll,
## so before that poll's serviced()).

var stalled_at_ms := -1
## The start of the running side's latest poll that returned with the stalled side still there.
var kept_at_ms := -1
var dropped_at_ms := -1


func stall(now_ms: int) -> void:
	stalled_at_ms = now_ms


## A poll of the running side began at `started_ms` and returned; ignored once it has dropped.
func serviced(started_ms: int) -> void:
	if dropped_at_ms < 0:
		kept_at_ms = started_ms


func drop(now_ms: int) -> void:
	dropped_at_ms = now_ms


func dropped() -> bool:
	return dropped_at_ms >= 0


## The wall clock from the stall to the drop.
func dropped_after_ms() -> int:
	return dropped_at_ms - stalled_at_ms


## From the stall to the last poll that still had the stalled side (negative: none after it).
func kept_after_ms() -> int:
	return kept_at_ms - stalled_at_ms


## How long the running side went unpolled before the poll the drop came in.
func hitch_ms() -> int:
	return dropped_at_ms - kept_at_ms


## "" when the drop came no earlier than `low_ms` after the stall and no poll after `high_ms`
## still had the stalled side; else why not.
func judge(low_ms: int, high_ms: int) -> String:
	if stalled_at_ms < 0 and dropped():
		return "dropped the other side before the stall"
	if not dropped():
		return "never dropped the stalled side"
	if dropped_after_ms() < low_ms:
		return "dropped after %d ms, under %d ms" % [dropped_after_ms(), low_ms]
	if kept_at_ms < stalled_at_ms:
		# The top is proven by the polls, so a run that recorded none after the stall proves nothing:
		# the owner stopped calling serviced() (or polls the running side elsewhere).
		return "had no poll of the running side recorded after the stall"
	if kept_after_ms() > high_ms:
		return (
			"still had the stalled side at its poll %d ms after the stall, over %d ms (dropped after %d ms)"
			% [kept_after_ms(), high_ms, dropped_after_ms()]
		)
	return ""
