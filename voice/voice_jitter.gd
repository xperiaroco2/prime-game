class_name VoiceJitter
extends RefCounted
## One speaker's jitter buffer on the listener (E39, the M5 ADR §1.4). Pure: push() takes each
## relayed frame with its arrival time, and update(), called once a frame with the audio the
## playback has queued, says which frames to decode now (with or without concealment) and, through
## command(), when to start, stop or flush the playback. VoicePlayback carries it out.
## - Order: by the stream's seq, which the host renumbers per speaker and listener (u16, wrapping)
##   and which runs on across talk spurts. A duplicate or a frame older than the next due is
##   dropped (`late`). A missing frame is waited for until the queue would run dry before the next
##   update, then decoded from the next packet held with `conceal` (FEC or concealment); two or more
##   missing in a row are concealed once and the rest skipped (`lost`). A frame missing across a
##   stop is skipped, not concealed at the start of the next run.
## - Start and stop: playback starts when the queue and the frames held reach the prebuffer, and
##   stops when the queue runs dry with nothing held: a talk spurt ended, or an underrun. The next
##   frame starts again under a fresh prebuffer. Frames held without starting for STALE_USEC are
##   discarded (`stale`), so old speech never plays in front of the speaker's next spurt.
## - The adaptive prebuffer: at each start, the largest spread of the arrival offsets within one
##   talk spurt over the last WINDOW_USEC of frames, plus a frame, within MIN_PREBUFFER_USEC and
##   MAX_PREBUFFER_USEC. A frame's offset is its arrival against its spurt's first frame's arrival
##   plus a frame per seq since, so a silence between spurts is not jitter. A new spurt starts when
##   a frame arrives more than LATE_SPURT_USEC after its due time or its host tick is more than
##   SPURT_TICKS past the newest frame's (the gate sends 20 ms frames, a tick is 50 ms).
## - Fade and flush: fade_out() stops decoding, gain() falls to 0 over FADE_USEC, then command()
##   says FLUSH; frames arriving meanwhile are dropped. flush() empties the held frames at once.
## One VoiceJitter per stream: a stream that starts again at seq 0 (the relay renumbers a reused
## peer id's streams afresh) gets a new one, as its seqs would read as old here.
## No time-stretching within a spurt: TwoVoIP offers no resampler per stream. Every number marked
## so is a placeholder, "not a decision".

enum Command { NONE, START, STOP, FLUSH }

const FRAME_USEC := 20000
const SEQ_MODULO := 0x10000
const SEQ_HALF := 0x8000
## The prebuffer's bounds: placeholders, "not a decision".
const MIN_PREBUFFER_USEC := 40000
const MAX_PREBUFFER_USEC := 120000
## The arrivals the prebuffer is adapted from: a placeholder, "not a decision".
const WINDOW_USEC := 2000000
## A frame this late after its due time starts a new spurt: a placeholder, "not a decision".
const LATE_SPURT_USEC := 60000
## A host tick this far past the newest frame's starts a new spurt: a placeholder, "not a
## decision".
const SPURT_TICKS := 2
## Held frames that have not started playback within this are discarded: a placeholder, "not a
## decision".
const STALE_USEC := 200000
const FADE_USEC := 50000
## A missing frame is concealed once the queue holds no more than one update's step and this.
const DRY_MARGIN_USEC := 10000

## Frames pushed.
var received := 0
## Duplicates and frames older than the next due, dropped.
var late := 0
## Missing frames decoded from the next packet with concealment (FEC or the codec's).
var concealed := 0
## Missing frames skipped after a concealed one (two or more missing in a row).
var lost := 0
## Held frames discarded after STALE_USEC without starting.
var stale := 0
## Starts of playback.
var starts := 0
## Times the queue ran dry within a spurt: a run that went on after an empty queue, or a restart
## whose first frame's host tick is within SPURT_TICKS of the last decoded frame's.
var underruns := 0
## Talk spurts seen.
var spurts := 0
## Whether the playback runs.
var running := false
## The prebuffer chosen at the latest start, or that a start would choose now.
var prebuffer_usec := MIN_PREBUFFER_USEC

var _command := Command.NONE
## The unwrapped seq due next, once _has_next.
var _next := 0
var _has_next := false
## The newest unwrapped seq accepted and its tick, once _seen.
var _newest := 0
var _newest_tick := 0
var _seen := false
## The current spurt's first frame: its unwrapped seq and arrival.
var _spurt_seq := 0
var _spurt_arrival := 0
## Held frames: unwrapped seq -> [frame: PackedByteArray, tick: int, arrival_usec: int].
var _pending: Dictionary[int, Array] = {}
## The window of accepted arrivals, oldest first: arrival, spurt and offset, in step.
var _window_arrival := PackedInt64Array()
var _window_spurt := PackedInt64Array()
var _window_offset := PackedInt64Array()
## The host tick of the last frame decoded without concealment, once _has_decoded.
var _last_tick := 0
var _has_decoded := false
var _last_update := 0
var _has_updated := false
var _step := FRAME_USEC
## When fade_out() was called, or -1.
var _fade_start := -1


## One decoded slot: `frame` decoded as is, or with `conceal` the slot before it.
class Decode:
	extends RefCounted
	var frame: PackedByteArray
	var conceal: bool
	## The unwrapped seq of the slot this decode fills.
	var seq: int

	func _init(packet: PackedByteArray, with_conceal: bool, slot: int) -> void:
		frame = packet
		conceal = with_conceal
		seq = slot


## Takes one relayed frame: its stream seq (u16), the host tick it was relayed at and when it
## arrived (stamped at the client's poll), in microseconds.
func push(seq: int, tick: int, frame: PackedByteArray, arrival_usec: int) -> void:
	received += 1
	if _fade_start >= 0:
		return
	var unwrapped := _unwrap(seq)
	if (_has_next and unwrapped < _next) or _pending.has(unwrapped):
		late += 1
		return
	_track_spurt(unwrapped, tick, arrival_usec)
	_pending[unwrapped] = [frame, tick, arrival_usec]


## The frames to decode now, in order, given `queued_usec` of audio queued in the playback at
## `now_usec`. Call once a frame, then apply command().
func update(queued_usec: int, now_usec: int) -> Array[Decode]:
	var out: Array[Decode] = []
	_command = Command.NONE
	if _has_updated:
		_step = clampi(now_usec - _last_update, 0, MAX_PREBUFFER_USEC)
	_last_update = now_usec
	_has_updated = true
	if _fade_start >= 0:
		if now_usec - _fade_start >= FADE_USEC:
			flush()
			_command = Command.FLUSH
		return out
	var was_running := running
	if not running and not _try_start(queued_usec, now_usec):
		return out
	var queued := queued_usec
	while not _pending.is_empty():
		if _pending.has(_next):
			var held: Array = _pending[_next]
			out.append(Decode.new(held[0] as PackedByteArray, false, _next))
			_last_tick = held[1]
			_has_decoded = true
			_pending.erase(_next)
			_next += 1
			queued += FRAME_USEC
			continue
		if queued > _step + DRY_MARGIN_USEC:
			break
		var first := _first_pending()
		out.append(Decode.new(_pending[first][0] as PackedByteArray, true, _next))
		concealed += 1
		lost += first - _next - 1
		_next = first
		queued += FRAME_USEC
	if was_running and queued_usec <= 0:
		if out.is_empty():
			running = false
			_command = Command.STOP
		else:
			underruns += 1
	return out


## What the playback must do after the latest update(): start, stop, flush or nothing.
func command() -> Command:
	return _command


## Starts the fade of a speaker who must not be heard any more: nothing more is decoded, gain()
## falls to 0 over FADE_USEC, and the update after that says FLUSH.
func fade_out(now_usec: int) -> void:
	if _fade_start < 0:
		_fade_start = now_usec
		_pending.clear()


## The playback's gain at `now_usec`: 1, or falling to 0 during a fade.
func gain(now_usec: int) -> float:
	if _fade_start < 0:
		return 1.0
	return clampf(1.0 - float(now_usec - _fade_start) / FADE_USEC, 0.0, 1.0)


## Empties the held frames and stops at once. Every seq seen so far stays behind: a frame of it
## arriving later is late, and the next run starts at the first newer frame.
func flush() -> void:
	_pending.clear()
	running = false
	_fade_start = -1
	_has_decoded = false
	if _seen:
		_next = maxi(_next, _newest + 1) if _has_next else _newest + 1
		_has_next = true


## Frames held, not yet decoded.
func pending_frames() -> int:
	return _pending.size()


## Discards stale frames, then starts if the queue and the frames held reach the prebuffer.
func _try_start(queued_usec: int, now_usec: int) -> bool:
	for seq: int in _pending.keys():
		var arrival: int = _pending[seq][2]
		if now_usec - arrival > STALE_USEC:
			_pending.erase(seq)
			stale += 1
	if _pending.is_empty():
		return false
	# Every held frame is at or after the next due (older ones were dropped as late), so the run
	# starts at the first one held: a frame missing across the stop is skipped. The next due only
	# moves at the start, so a frame of the gap that arrives before it is still played.
	var first := _first_pending()
	prebuffer_usec = _adapted_prebuffer()
	var last := first
	for seq: int in _pending:
		last = maxi(last, seq)
	if queued_usec + (last - first + 1) * FRAME_USEC < prebuffer_usec:
		return false
	_next = first
	_has_next = true
	running = true
	starts += 1
	_command = Command.START
	if _has_decoded and _pending.has(_next):
		var tick: int = _pending[_next][1]
		if tick - _last_tick <= SPURT_TICKS:
			underruns += 1
	return true


func _first_pending() -> int:
	var first := 0
	var any := false
	for seq: int in _pending:
		if not any or seq < first:
			first = seq
			any = true
	return first


## `seq` (u16) as an unbounded seq near the newest one seen.
func _unwrap(seq: int) -> int:
	if not _seen:
		return seq
	var ahead := posmod(seq - posmod(_newest, SEQ_MODULO) + SEQ_HALF, SEQ_MODULO) - SEQ_HALF
	return _newest + ahead


func _track_spurt(seq: int, tick: int, arrival_usec: int) -> void:
	if not _seen or seq > _newest:
		var new_spurt := not _seen
		if _seen:
			var due := _spurt_arrival + (seq - _spurt_seq) * FRAME_USEC
			new_spurt = arrival_usec - due > LATE_SPURT_USEC or tick - _newest_tick > SPURT_TICKS
		if new_spurt:
			spurts += 1
			_spurt_seq = seq
			_spurt_arrival = arrival_usec
		_seen = true
		_newest = seq
		_newest_tick = tick
	var offset := arrival_usec - (_spurt_arrival + (seq - _spurt_seq) * FRAME_USEC)
	_window_arrival.append(arrival_usec)
	_window_spurt.append(spurts)
	_window_offset.append(offset)
	var keep := 0
	while keep < _window_arrival.size() and _window_arrival[keep] < arrival_usec - WINDOW_USEC:
		keep += 1
	if keep > 0:
		_window_arrival = _window_arrival.slice(keep)
		_window_spurt = _window_spurt.slice(keep)
		_window_offset = _window_offset.slice(keep)


## The largest spread of offsets within one spurt in the window, plus a frame, within bounds.
func _adapted_prebuffer() -> int:
	var low: Dictionary[int, int] = {}
	var high: Dictionary[int, int] = {}
	for i: int in _window_spurt.size():
		var spurt := _window_spurt[i]
		var offset := _window_offset[i]
		if not low.has(spurt):
			low[spurt] = offset
			high[spurt] = offset
		low[spurt] = mini(low[spurt], offset)
		high[spurt] = maxi(high[spurt], offset)
	var spread := 0
	for spurt: int in low:
		spread = maxi(spread, high[spurt] - low[spurt])
	return clampi(spread + FRAME_USEC, MIN_PREBUFFER_USEC, MAX_PREBUFFER_USEC)
