class_name PeerBudget
extends RefCounted
## One peer's three token buckets (ARCHITECTURE §4.5 "Rate limits", E7): voice frames, reliable
## intents, and the bytes of every message that is not voice (the reliable intents and MoveClaim).
## The accident they bound: a client bug that sends an intent every frame, every command of which
## stays in the command log for the whole match. Voice has a bucket of its own, so a player talking
## at a high bitrate never drains what a SetReady or a LoadAck needs. Each bucket holds more than
## 10 s of an honest client's traffic, so a thawed peer's backlog passes. A message over a budget is
## dropped before decoding; nobody is disconnected for its rate. The host's own client (peer 1) has
## no budget. Every number is a placeholder, "not a decision".

## Voice frames (one 20 ms frame each): the bucket and its refill per second.
const VOICE_FRAMES := 500.0
const VOICE_FRAMES_PER_SECOND := 50.0
## Reliable intents.
const INTENTS := 100.0
const INTENTS_PER_SECOND := 20.0
## Payload bytes of every message that is not voice: 64 KiB, refilled at 16 KiB/s.
const BYTES := 65536.0
const BYTES_PER_SECOND := 16384.0
const USEC_PER_SECOND := 1000000.0

var voice_frames := VOICE_FRAMES
var intents := INTENTS
var bytes := BYTES


## Refills every bucket for `elapsed_usec` of host time, up to its size.
func refill(elapsed_usec: int) -> void:
	if elapsed_usec <= 0:
		return
	var seconds := elapsed_usec / USEC_PER_SECOND
	voice_frames = minf(VOICE_FRAMES, voice_frames + seconds * VOICE_FRAMES_PER_SECOND)
	intents = minf(INTENTS, intents + seconds * INTENTS_PER_SECOND)
	bytes = minf(BYTES, bytes + seconds * BYTES_PER_SECOND)


## Takes one voice frame; false (nothing taken) when the bucket is empty.
func take_voice() -> bool:
	if voice_frames < 1.0:
		return false
	voice_frames -= 1.0
	return true


## Takes one reliable intent of `size` payload bytes: one intent and its bytes, or nothing.
func take_intent(size: int) -> bool:
	if intents < 1.0 or bytes < size:
		return false
	intents -= 1.0
	bytes -= size
	return true


## Takes `size` payload bytes of a message that is neither voice nor a reliable intent.
func take_bytes(size: int) -> bool:
	if bytes < size:
		return false
	bytes -= size
	return true
