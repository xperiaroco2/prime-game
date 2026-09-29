class_name SpikeSnapshotBuffer
extends RefCounted
## Spike (#14): interpolation of remote players between host snapshots. Each snapshot carries the
## host's tick; tick / tick_hz is its host time. The buffer estimates the host clock from arrivals
## and renders every player at (host clock - delay), between the two samples around that time.
## Past the newest sample it holds the last position and counts a starved sample.
## Pure logic: the caller passes local times in seconds, so tests need no scene.

const KEEP_SECONDS := 1.0

var tick_hz := 20.0
## How far behind the estimated host clock players are shown, in seconds.
var delay := 0.1
## Renders that found no newer sample for a player (the delay was too short for the jitter).
var starved := 0
## Renders that found a pair of samples to interpolate between.
var interpolated := 0

# The newest estimate of (host time - local time). Only moves forward by jumps when a snapshot
# arrives early, and drifts back slowly otherwise, so a late packet does not pull it back.
var _offset := 0.0
var _has_offset := false
var _last_tick := -1
# peer id -> Array of [host_time: float, pos: Vector3, yaw: float], oldest first
var _samples: Dictionary[int, Array] = {}


## Adds one snapshot. Older or repeated ticks are ignored. Players missing from it are dropped.
func push(
	local_time: float,
	tick: int,
	peer_ids: PackedInt32Array,
	positions: PackedVector3Array,
	yaws: PackedFloat32Array
) -> void:
	if tick <= _last_tick:
		return
	_last_tick = tick
	var host_time := tick / tick_hz
	var offset := host_time - local_time
	if not _has_offset or offset > _offset:
		_offset = offset
		_has_offset = true
	var present: Dictionary[int, bool] = {}
	for i in peer_ids.size():
		var id := peer_ids[i]
		present[id] = true
		if not _samples.has(id):
			_samples[id] = []
		var list: Array = _samples[id]
		list.append([host_time, positions[i], yaws[i]])
		while list.size() > 2 and (list[1][0] as float) < host_time - KEEP_SECONDS:
			list.pop_front()
	for id: int in _samples.keys():
		if not present.has(id):
			_samples.erase(id)


## Lets the clock estimate drift back by rate seconds per second, so one early packet does not
## hold it forward for ever. Call once per frame.
func relax(delta: float, rate: float = 0.01) -> void:
	_offset -= delta * rate


func ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_samples.keys())
	return out


## Samples buffered for a player that are newer than the current render time.
func depth(id: int, local_time: float) -> int:
	var at := render_time(local_time)
	var n := 0
	var list: Array = _samples.get(id, [])
	for entry: Array in list:
		if (entry[0] as float) > at:
			n += 1
	return n


func render_time(local_time: float) -> float:
	return local_time + _offset - delay


## [pos: Vector3, yaw: float] of a player at the render time, or [] when the player is unknown.
func sample(id: int, local_time: float) -> Array:
	if not _samples.has(id):
		return []
	var list: Array = _samples[id]
	var at := render_time(local_time)
	var newest: Array = list[-1]
	if at >= (newest[0] as float):
		starved += 1
		return [newest[1], newest[2]]
	var oldest: Array = list[0]
	if at <= (oldest[0] as float):
		return [oldest[1], oldest[2]]
	for i in range(list.size() - 1, 0, -1):
		var a: Array = list[i - 1]
		var b: Array = list[i]
		if (a[0] as float) <= at:
			var t := inverse_lerp(a[0] as float, b[0] as float, at)
			interpolated += 1
			var pos := (a[1] as Vector3).lerp(b[1] as Vector3, t)
			return [pos, lerp_angle(a[2] as float, b[2] as float, t)]
	return [oldest[1], oldest[2]]
