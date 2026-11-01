class_name PinballBallTrack
extends RefCounted
## The pinball's ball between snapshots (#1400; ARCHITECTURE §4.7.63): the host reports the ball's
## table-local place in each snapshot (ClientPinball.ball, §7.1.22), and every window near the
## machine draws it at the same render tick as the remote bodies (AvatarViews.drawn_at, §4.7.6),
## so the bystanders and the seated player see one game. Pure: PinballViews adds each newly folded
## snapshot's ball and asks where to draw it.
##
## - Between two samples that both show the ball, the place is linear in the tick; past the newest
##   it holds there (no extrapolation: a ball never runs through a wall the host stopped it at).
## - A sample without the ball (lost, or no game) hides it from its own tick on, never earlier: a
##   ball that drains is seen to the drain.
## - A jump longer than SNAP_M between two samples (a new ball at the launch) is not slid across
##   the table: the older place holds until the newer sample's tick.
## - A sample at or below the newest tick is ignored (ClientSession emits snapshot_received also
##   for a snapshot the model skipped), and samples older than KEEP_TICKS below the newest go.

## A jump between two samples longer than this is a new place, not a move (metres; the table is
## 1.3 m long, a ball crosses it in about 0.3 s, 6 ticks; not a decision).
const SNAP_M := 0.5
## How far below the newest sample the track keeps samples, in ticks (two seconds at Ticks.RATE).
const KEEP_TICKS := 40

## [tick: int, shown: bool, place: Vector3], oldest first.
var _samples: Array[Array] = []


## Adds the ball of the snapshot at `tick`: `shown` whether it has one, at `place`. Whether it was
## taken (a tick at or below the newest is not).
func add(tick: int, shown: bool, place: Vector3) -> bool:
	if not _samples.is_empty() and tick <= (_samples.back()[0] as int):
		return false
	_samples.append([tick, shown, place])
	while (_samples.front()[0] as int) < tick - KEEP_TICKS:
		_samples.pop_front()
	return true


## The newest tick added, or -1 for none.
func newest() -> int:
	return _samples.back()[0] as int if not _samples.is_empty() else -1


## Where to draw the ball at `render_tick` (fractional host ticks), table-local, or null when it is
## not on the table then (no sample at or before that tick, or the one there shows no ball).
func at(render_tick: float) -> Variant:
	var before := -1
	for i in _samples.size():
		if float(_samples[i][0] as int) <= render_tick:
			before = i
		else:
			break
	if before < 0 or not (_samples[before][1] as bool):
		return null
	var from: Vector3 = _samples[before][2]
	if before + 1 >= _samples.size():
		return from
	var next: Array = _samples[before + 1]
	var to: Vector3 = next[2]
	if not (next[1] as bool) or from.distance_to(to) > SNAP_M:
		return from
	var start := float(_samples[before][0] as int)
	var weight := (render_tick - start) / (float(next[0] as int) - start)
	return from.lerp(to, clampf(weight, 0.0, 1.0))


## Forgets every sample (a new game, the match cleared, the session gone).
func clear() -> void:
	_samples.clear()
