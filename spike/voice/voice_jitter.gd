class_name SpikeVoiceJitter
extends RefCounted
## Spike (#15): the listener's jitter logic for one speaker, pure so it can be tested with
## synthetic frames. Two parts:
## - Ordering: frames arrive by sequence number, maybe late, twice or not at all. pop() hands them
##   out in order. A missing frame is waited for while fewer than REORDER_WAIT newer ones are held;
##   then it is decoded with decode_fec from the next frame when that one is here, or given up.
##   decode_fec uses the next packet's in-band FEC data if the encoder put any there; otherwise
##   Opus conceals the gap. Whether TwoVoIP v6.5 turns in-band FEC on was not verified.
## - Gating: the playback starts once PREBUFFER_FRAMES of decoded audio are queued, and stops (to
##   refill) when the queue runs dry. The caller applies it with mark_end_opus_stream.
## A jump of RESET_GAP or more past the newest frame seen means the speaker was cut off for a while
## (out of range, or a sender stall): the next frame starts afresh. A burst of in-order frames
## (a listener stall) is no jump and is all kept.

enum Gate { KEEP, START, STOP }

const REORDER_WAIT := 2
const RESET_GAP := 25  # 500 ms of 20 ms frames
const PREBUFFER_FRAMES := 2880  # 60 ms at 48 kHz

var received := 0
var late := 0  # too late, or a duplicate
var fec := 0  # a missing frame decoded with decode_fec from the next one
var lost := 0
var resets := 0
var underruns := 0
var playing := false
var _next := -1
var _newest := -1
var _pending: Dictionary[int, PackedByteArray] = {}


func push(seq: int, opus: PackedByteArray) -> void:
	received += 1
	if _next < 0 or seq >= _newest + RESET_GAP:
		if _next >= 0:
			resets += 1
		_next = seq
		_pending.clear()
	if seq < _next or _pending.has(seq):
		late += 1
		return
	_pending[seq] = opus
	_newest = maxi(_newest, seq)


## The frames ready to decode, in order, each as [opus: PackedByteArray, fec: int]. fec 1 means:
## decode the frame before this packet (from its FEC data if any, else concealment); the same
## packet comes again with fec 0 as the next frame.
func pop() -> Array[Array]:
	var out: Array[Array] = []
	while not _pending.is_empty():
		if _pending.has(_next):
			out.append([_pending[_next], 0])
			_pending.erase(_next)
			_next += 1
			continue
		if _pending.size() < REORDER_WAIT:
			break
		if _pending.has(_next + 1):
			out.append([_pending[_next + 1], 1])
			fec += 1
		else:
			lost += 1
		_next += 1
	return out


## What the playback should do with `queued_frames` of decoded audio waiting.
func gate(queued_frames: int) -> Gate:
	if not playing and queued_frames >= PREBUFFER_FRAMES:
		playing = true
		return Gate.START
	if playing and queued_frames <= 0:
		playing = false
		underruns += 1
		return Gate.STOP
	return Gate.KEEP
