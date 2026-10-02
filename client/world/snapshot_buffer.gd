class_name SnapshotBuffer
extends RefCounted
## The remote players' poses between snapshots (ARCHITECTURE §4.7 and §7, the M4 ADR's E23): pure,
## fed every snapshot as it arrives (ClientSession.snapshot_received) with the local clock.
##
## - The host tick is estimated from a sliding window of arrivals (WINDOW_USEC), never an all-time
##   maximum (the M1 spike's lesson, §7): each arrival's offset is its tick minus its arrival time
##   in ticks; the least delayed one of the window, the highest offset, puts the estimate at the
##   tick of the snapshot that would arrive now with the least delay.
## - Remote players are drawn at the estimate minus a delay of one tick plus the jitter seen over
##   the window (the spread of the offsets), between MIN_DELAY_TICKS and MAX_DELAY_TICKS. A larger
##   delay takes effect at once, a smaller one slowly (DELAY_SLEW), and the render time never runs
##   backwards: it holds instead.
## - Positions and facings are interpolated linearly between the two snapshots around the render
##   time. Past the newest snapshot a player holds still (no extrapolation: a player who stopped
##   running is not drawn on into a wall). A placement snaps (snap(), and any two snapshots further
##   apart than SNAP_SPEED_MPS could carry anyone). The velocity is the newest snapshot's and only
##   picks an animation: a claimed velocity never moves a body on another screen.
## - A relayed facing can be degenerate in honest play (a bot falling straight down claims
##   (0, -1, 0), a standing one may claim zero): every pose has a unit facing and a yaw and pitch
##   kept from the last usable facing, and the pitch is within ±MAX_PITCH (the M4 ADR's §3).
##
## The numbers are placeholders, "not a decision".

const USEC_PER_TICK := 1000000 / Ticks.RATE
## Arrivals older than this, in microseconds, leave the estimate and the jitter: 2 s.
const WINDOW_USEC := 2000000
## The delay's bounds, in host ticks: 100 ms and 250 ms (E23).
const MIN_DELAY_TICKS := 2.0
const MAX_DELAY_TICKS := 5.0
## Ticks of delay a smaller target takes off per tick of time: the render time runs at most 10 %
## faster while the delay shrinks.
const DELAY_SLEW := 0.1
## Snapshots older than the newest by more than this many ticks are dropped (2 s).
const KEEP_TICKS := 40
## Horizontal metres per second no player moves by itself or by a push (sprint and a push-out
## allowance stay under 15): two snapshots further apart are a placement and snap.
const SNAP_SPEED_MPS := 30.0
## The largest pitch drawn: a head never turns straight up or down.
const MAX_PITCH := deg_to_rad(89.0)
## Shorter vectors have no usable direction.
const DEGENERATE := 0.0001


## One remote player's pose at a render time.
class Pose:
	extends RefCounted
	var position := Vector3.ZERO
	## A unit look vector, never zero.
	var facing := Vector3.FORWARD
	## Radians about +Y, 0 looking along -Z: the body's turn.
	var yaw := 0.0
	## Radians up (+) or down (-), within ±MAX_PITCH: the head's tilt.
	var pitch := 0.0
	## The newest snapshot's velocity: for picking an animation only.
	var velocity := Vector3.ZERO


## The snapshots held, oldest first, and their avatars (peer -> fields).
var _ticks: Array[int] = []
var _avatars: Array[Dictionary] = []
## The window of arrivals, oldest first: when each came (microseconds) and its offset (ticks).
var _arrived: Array[int] = []
var _offsets: Array[float] = []
var _delay := MIN_DELAY_TICKS
var _delay_usec := -1
var _last_render := -INF
## Peer -> the host tick of its last placement: never interpolated across.
var _snaps: Dictionary[int, int] = {}
## Peer -> its last usable facing, and the yaw and pitch built from it.
var _facings: Dictionary[int, Vector3] = {}
var _angles: Dictionary[int, Vector2] = {}


## A snapshot of host tick `tick` arrived at `arrived_usec` on the local clock. A late one still
## counts for the jitter and is kept in order; a tick already held is not replaced.
func add(tick: int, avatars: Dictionary, arrived_usec: int) -> void:
	_arrived.append(arrived_usec)
	_offsets.append(tick - float(arrived_usec) / USEC_PER_TICK)
	_forget_arrivals(arrived_usec)
	var at := _ticks.bsearch(tick)
	if at < _ticks.size() and _ticks[at] == tick:
		return
	_ticks.insert(at, tick)
	_avatars.insert(at, avatars)
	while _ticks[0] < _ticks[_ticks.size() - 1] - KEEP_TICKS:
		_ticks.remove_at(0)
		_avatars.remove_at(0)


## Whether any snapshot arrived yet: the estimate needs one.
func has_estimate() -> bool:
	return not _offsets.is_empty()


## The estimated host tick at `now_usec`, with its fraction; -1 before the first snapshot.
func estimated_tick(now_usec: int) -> float:
	if _offsets.is_empty():
		return -1.0
	return float(now_usec) / USEC_PER_TICK + (_offsets.max() as float)


## The spread of the window's offsets, in ticks: how much later than the least delayed snapshot
## the most delayed one came.
func jitter_ticks() -> float:
	if _offsets.is_empty():
		return 0.0
	return (_offsets.max() as float) - (_offsets.min() as float)


## The delay the window asks for: one tick plus the jitter, within the bounds.
func target_delay_ticks() -> float:
	return clampf(1.0 + jitter_ticks(), MIN_DELAY_TICKS, MAX_DELAY_TICKS)


## The delay in use, in ticks (the debug overlay shows it in milliseconds).
func delay_ticks() -> float:
	return _delay


## The host tick to draw the others at, at `now_usec`: the estimate minus the delay, never less
## than the last one asked for. Call it once per frame, before pose_of().
func render_tick(now_usec: int) -> float:
	if _offsets.is_empty():
		return -1.0
	_forget_arrivals(now_usec)
	var target := target_delay_ticks()
	if target >= _delay or _delay_usec < 0:
		_delay = target
	else:
		var elapsed := float(now_usec - _delay_usec) / USEC_PER_TICK
		_delay = maxf(target, _delay - DELAY_SLEW * maxf(0.0, elapsed))
	_delay_usec = now_usec
	_last_render = maxf(_last_render, estimated_tick(now_usec) - _delay)
	return _last_render


## The newest host tick held; -1 when none.
func newest_tick() -> int:
	return _ticks[_ticks.size() - 1] if not _ticks.is_empty() else -1


## `peer` was placed (PlayersPlaced, a respawn) about host tick `tick`, the estimate when the
## event arrived: it snaps there. Events and snapshots travel on different lanes, so the estimate
## may be a tick off either way: no two snapshots are blended across any tick within one of it
## (the player holds still for at most a tick before and after instead of sliding).
func snap(peer: int, tick: int) -> void:
	_snaps[peer] = tick


## Forgets the snapshots and placements (a new level): the arrivals stay, the host's clock runs on.
func clear() -> void:
	_ticks.clear()
	_avatars.clear()
	_snaps.clear()


## `peer`'s pose at host tick `at` (a render_tick()), or null when no snapshot held has it.
func pose_of(peer: int, at: float) -> Pose:
	var before := -1
	var after := -1
	var newest := -1
	for i: int in _ticks.size():
		if not _avatars[i].has(peer):
			continue
		newest = i
		if _ticks[i] <= at:
			before = i
		elif after < 0:
			after = i
	if newest < 0:
		return null
	var pose := Pose.new()
	pose.velocity = _field(newest, peer, "velocity")
	if before < 0 or after < 0:
		var only := before if before >= 0 else after
		pose.position = _field(only, peer, "position")
		_face(pose, peer, _field(only, peer, "facing"))
		return pose
	var from := _field(before, peer, "position")
	var to := _field(after, peer, "position")
	var span := float(_ticks[after] - _ticks[before])
	if _snaps_between(peer, before, after) or _too_far(from, to, span):
		pose.position = from
		_face(pose, peer, _field(before, peer, "facing"))
		return pose
	var weight := (at - _ticks[before]) / span
	pose.position = from.lerp(to, weight)
	var facing_from := _usable(
		_field(before, peer, "facing"), _facings.get(peer, Vector3.FORWARD) as Vector3
	)
	var facing_to := _usable(_field(after, peer, "facing"), facing_from)
	_face(pose, peer, facing_from.lerp(facing_to, weight))
	return pose


## The yaw and pitch of `facing`, or `last` (yaw, pitch) for what has no usable direction: a zero
## or non-finite facing keeps both, a vertical one keeps the yaw. The pitch stays within MAX_PITCH.
static func look_angles(facing: Vector3, last: Vector2) -> Vector2:
	var unit := _direction(facing)
	if unit == Vector3.ZERO:
		return last
	var yaw := last.x
	if Vector2(unit.x, unit.z).length() >= DEGENERATE:
		yaw = atan2(-unit.x, -unit.z)
	var pitch := clampf(asin(clampf(unit.y, -1.0, 1.0)), -MAX_PITCH, MAX_PITCH)
	return Vector2(yaw, pitch)


## Sets the pose's facing, yaw and pitch from `facing`, or from the peer's last usable one.
func _face(pose: Pose, peer: int, facing: Vector3) -> void:
	var last_facing: Vector3 = _facings.get(peer, Vector3.FORWARD)
	var angles := look_angles(facing, _angles.get(peer, Vector2.ZERO) as Vector2)
	pose.facing = _usable(facing, last_facing).normalized()
	pose.yaw = angles.x
	pose.pitch = angles.y
	_facings[peer] = pose.facing
	_angles[peer] = angles


func _snaps_between(peer: int, before: int, after: int) -> bool:
	if not _snaps.has(peer):
		return false
	var placed: int = _snaps[peer]
	return _ticks[before] < placed + 1 and _ticks[after] >= placed - 1


static func _too_far(from: Vector3, to: Vector3, ticks: float) -> bool:
	var horizontal := Vector2(to.x - from.x, to.z - from.z).length()
	return horizontal > SNAP_SPEED_MPS * ticks / Ticks.RATE


## `facing` as a unit vector, or `fallback` (a unit vector) when it has no usable direction.
static func unit_or(facing: Vector3, fallback: Vector3) -> Vector3:
	var unit := _direction(facing)
	return unit if unit != Vector3.ZERO else fallback


## `facing` normalised first, so a huge but finite one keeps its direction (its squared length
## would overflow, and normalized() alone would give zero: the netcode review of PR #154), or
## `fallback` when it has no usable direction. The result is a unit vector unless `fallback` is not.
static func _usable(facing: Vector3, fallback: Vector3) -> Vector3:
	return unit_or(facing, fallback)


## The unit direction of `facing`, or zero when it has none: not finite, or every component under
## DEGENERATE. Scaled by its largest component first, so no square overflows.
static func _direction(facing: Vector3) -> Vector3:
	if not facing.is_finite():
		return Vector3.ZERO
	var largest := maxf(absf(facing.x), maxf(absf(facing.y), absf(facing.z)))
	if largest < DEGENERATE:
		return Vector3.ZERO
	var unit := (facing / largest).normalized()
	return unit if unit.is_finite() and unit.is_normalized() else Vector3.ZERO


func _field(index: int, peer: int, key: String) -> Vector3:
	var avatar: Dictionary = _avatars[index][peer]
	var value: Variant = avatar.get(key, Vector3.ZERO)
	return value as Vector3 if value is Vector3 else Vector3.ZERO


func _forget_arrivals(now_usec: int) -> void:
	while _arrived.size() > 1 and _arrived[0] < now_usec - WINDOW_USEC:
		_arrived.remove_at(0)
		_offsets.remove_at(0)
