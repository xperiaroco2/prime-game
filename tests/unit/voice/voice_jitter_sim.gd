extends RefCounted
## A listener's side of one stream for the VoiceJitter suites: relayed frames arrive at their
## times, the client polls once a render frame (STEP_USEC) and stamps each frame with the poll's
## time, and a playback model drains its queue in real time while running. Frames are synthetic:
## 2 bytes of the seq, or whatever bytes a test gives.

const STEP_USEC := 16667
const FRAME_USEC := VoiceJitter.FRAME_USEC
## The host's tick (ARCHITECTURE §3.3: 20 ticks a second).
const TICK_USEC := 50000

var jitter := VoiceJitter.new()
## Every decode, in order.
var decoded: Array[VoiceJitter.Decode] = []
## The prebuffer at each start, and when the start came.
var start_prebuffers := PackedInt64Array()
var start_times := PackedInt64Array()
## Times the running playback ran dry while its spurt still had frames to come: the audible
## underruns, by the test's own knowledge of where each spurt ends (`ends`).
var dry := 0
## When each of them came.
var dry_times := PackedInt64Array()
var stops := 0
var flushes := 0
var queue_usec := 0
var running := false
## Seqs that end a talk spurt: running dry after one of them is the spurt's end, not an underrun.
var ends: Dictionary[int, bool] = {}
## Polls skipped in [stall_from, stall_to): the listener's process froze.
var stall_from := -1
var stall_to := -1


## Polls from 0 to `until_usec`, pushing each delivery at the first poll at or after its arrival.
func run(deliveries: Array[FixtureVoiceDelivery], until_usec: int) -> void:
	var queue := deliveries.duplicate()
	queue.sort_custom(
		func(a: FixtureVoiceDelivery, b: FixtureVoiceDelivery) -> bool: return a.arrival < b.arrival
	)
	var next := 0
	var last := 0
	var t := 0
	while t <= until_usec:
		if stall_from <= t and t < stall_to:
			t += STEP_USEC
			continue
		if running:
			var left := queue_usec - (t - last)
			if left <= 0 and queue_usec > 0 and not _at_spurt_end():
				dry += 1
				dry_times.append(t)
			queue_usec = maxi(0, left)
		last = t
		while next < queue.size() and (queue[next] as FixtureVoiceDelivery).arrival <= t:
			var d := queue[next] as FixtureVoiceDelivery
			jitter.push(d.seq & 0xFFFF, d.tick, d.frame, t)
			next += 1
		for decode: VoiceJitter.Decode in jitter.update(queue_usec, t):
			decoded.append(decode)
			queue_usec += FRAME_USEC
		match jitter.command():
			VoiceJitter.Command.START:
				running = true
				start_prebuffers.append(jitter.prebuffer_usec)
				start_times.append(t)
			VoiceJitter.Command.STOP:
				running = false
				stops += 1
			VoiceJitter.Command.FLUSH:
				running = false
				queue_usec = 0
				flushes += 1
		t += STEP_USEC


## The decoded slots' seqs, in order.
func slots() -> PackedInt64Array:
	var out := PackedInt64Array()
	for decode: VoiceJitter.Decode in decoded:
		out.append(decode.seq)
	return out


## The seqs decoded without concealment, in order, read from their frames' first 2 bytes.
func frames_played() -> PackedInt64Array:
	var out := PackedInt64Array()
	for decode: VoiceJitter.Decode in decoded:
		if not decode.conceal:
			out.append(decode.frame.decode_u16(0))
	return out


func concealed_slots() -> PackedInt64Array:
	var out := PackedInt64Array()
	for decode: VoiceJitter.Decode in decoded:
		if decode.conceal:
			out.append(decode.seq)
	return out


## The underruns at or after `from_usec`.
func dry_after(from_usec: int) -> int:
	var count := 0
	for at: int in dry_times:
		if at >= from_usec:
			count += 1
	return count


## The mean prebuffer of the starts at or after `from_usec`, in microseconds.
func mean_prebuffer_after(from_usec: int) -> float:
	var total := 0
	var count := 0
	for i: int in start_times.size():
		if start_times[i] >= from_usec:
			total += start_prebuffers[i]
			count += 1
	return float(total) / maxi(1, count)


## A talk spurt of `count` frames from `first_seq`, the first sent at `start_usec`, each 20 ms
## after the last, arriving after `latency_usec` plus up to `jitter_usec` (uniform, from `rng`).
## Its last seq goes into `ends`.
func spurt(
	first_seq: int,
	start_usec: int,
	count: int,
	latency_usec: int,
	jitter_usec: int,
	rng: RandomNumberGenerator
) -> Array[FixtureVoiceDelivery]:
	var out: Array[FixtureVoiceDelivery] = []
	for k: int in count:
		var sent := start_usec + k * FRAME_USEC
		var delay := latency_usec + (rng.randi_range(0, jitter_usec) if jitter_usec > 0 else 0)
		var seq := first_seq + k
		out.append(
			FixtureVoiceDelivery.new(seq, int(float(sent) / TICK_USEC), frame_of(seq), sent + delay)
		)
	ends[first_seq + count - 1] = true
	return out


## A synthetic frame naming its seq.
static func frame_of(seq: int) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(2)
	frame.encode_u16(0, seq & 0xFFFF)
	return frame


func _at_spurt_end() -> bool:
	return decoded.is_empty() or ends.has(decoded[-1].seq)
