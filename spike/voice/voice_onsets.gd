class_name SpikeVoiceOnsets
extends RefCounted
## Spike (#16): the acoustic mouth-to-ear measurement, pure so it can be tested with synthetic
## samples. A listening client clicks through its loudspeaker now and then. The capturing client's
## microphone hears each click twice: first straight through the air (the "mouth"), then again
## after the whole voice path (encode, host relay, jitter buffer, playback, the listener's
## loudspeaker: the "ear"). Both are found in the same stream of microphone samples, so the gap
## between them is the mouth-to-ear latency, with the audio devices' own buffers included and no
## clock shared between machines.
## feed() finds onsets: the first sample of a 1 ms block whose peak rises THRESHOLD times above
## the running noise floor (and above MIN_LEVEL), at least REFRACTORY_S after the previous onset.
## echo_delays() pairs them afterwards. Room noise makes onsets too, at random; every click's echo
## comes the same delay after it. So the delay shared by the most pairs of onsets is the latency,
## and each click is paired with the onset nearest that delay.

const BLOCK_S := 0.001
const THRESHOLD := 8.0  # 18 dB above the noise floor
const MIN_LEVEL := 0.008  # a relayed click through a quiet loudspeaker can be this faint
const REFRACTORY_S := 0.08  # a click and its room reverb
const MIN_DELAY_S := 0.1  # the shortest echo delay looked for (above REFRACTORY_S)
const MAX_DELAY_S := 0.8  # the longest
const MODE_WIDTH_S := 0.02  # the window the common delay is found with: an echo strays a few ms
const TOLERANCE_S := 0.03  # how far one click's delay may stray from the common one
const FLOOR_RISE := 0.01  # per block: the floor follows quieter blocks fast, louder ones slowly
const FLOOR_FALL := 0.2

var rate: int
var floor_level := 0.0  # the running noise floor (block peaks, rising slowly, falling fast)
var _index := 0  # the next sample's index in the stream
var _block := 0
var _block_peak := 0.0
var _block_first_loud := -1
var _last_found := -1  # the last onset feed() returned


func _init(sample_rate: int) -> void:
	rate = sample_rate
	_block = maxi(1, roundi(sample_rate * BLOCK_S))


## Feeds the next stereo frames (their mean is used). Returns the onsets found in them, each as
## [index: int, peak: float]: the sample index in the whole stream and the block's peak.
func feed(frames: PackedVector2Array) -> Array[Array]:
	var found: Array[Array] = []
	for frame: Vector2 in frames:
		var v := absf((frame.x + frame.y) * 0.5)
		if v > _block_peak:
			_block_peak = v
		if _block_first_loud < 0 and v > _threshold():
			_block_first_loud = _index
		_index += 1
		if _index % _block == 0:
			var onset := _end_block()
			if not onset.is_empty():
				found.append(onset)
	return found


## How many samples feed() has taken so far.
func fed() -> int:
	return _index


## The clicks and their echoes among `indices` (onset sample indices, ascending) at `sample_rate`,
## as [click index, echo index] pairs. The common delay is the centre of the MODE_WIDTH_S window
## holding the most gaps between onsets MIN_DELAY_S to MAX_DELAY_S apart; each onset is then paired
## with the one nearest that delay after it, within TOLERANCE_S. An onset used as an echo is no
## click itself.
static func echo_pairs(indices: Array[int], sample_rate: int) -> Array[Array]:
	var lo := roundi(MIN_DELAY_S * sample_rate)
	var hi := roundi(MAX_DELAY_S * sample_rate)
	var tol := roundi(TOLERANCE_S * sample_rate)
	var width := roundi(MODE_WIDTH_S * sample_rate)
	var gaps: Array[int] = []
	for i in indices.size():
		for j in range(i + 1, indices.size()):
			var d := indices[j] - indices[i]
			if d > hi:
				break
			if d >= lo:
				gaps.append(d)
	var pairs: Array[Array] = []
	if gaps.is_empty():
		return pairs
	gaps.sort()
	# The delay with the most gaps in a MODE_WIDTH_S window around it, sliding over the sorted gaps.
	var best := 0
	var best_count := 0
	var start := 0
	for end in gaps.size():
		while gaps[end] - gaps[start] > width:
			start += 1
		if end - start + 1 > best_count:
			best_count = end - start + 1
			best = floori((gaps[start] + gaps[end]) / 2.0)
	var used: Dictionary[int, bool] = {}
	var last_click := -lo
	for i in indices.size():
		# Sooner than MIN_DELAY_S after a click, an onset is its tail (a long click set off the
		# detector twice), not a click of its own.
		if used.has(i) or indices[i] - last_click < lo:
			continue
		var pick := -1
		for j in range(i + 1, indices.size()):
			var d := indices[j] - indices[i]
			if d > best + tol:
				break
			if (
				absi(d - best) <= tol
				and (pick < 0 or absi(d - best) < absi(indices[pick] - indices[i] - best))
			):
				pick = j
		if pick >= 0:
			last_click = indices[i]
			pairs.append([indices[i], indices[pick]])
			# The echo and its own tail are no clicks either.
			var k := pick
			while k < indices.size() and indices[k] - indices[pick] < lo:
				used[k] = true
				k += 1
	return pairs


func _threshold() -> float:
	return maxf(MIN_LEVEL, floor_level * THRESHOLD)


func _end_block() -> Array:
	var onset: Array = []
	var loud := _block_peak > _threshold()
	var free := _last_found < 0 or _index - _last_found >= roundi(REFRACTORY_S * rate)
	if loud and free:
		onset = [_block_first_loud, _block_peak]
		_last_found = _block_first_loud
	else:
		# Loud blocks count too, only slowly: a lasting sound (a fan, speech) lifts the floor over
		# it within a few hundred ms instead of firing again after every REFRACTORY_S.
		var k := FLOOR_FALL if _block_peak < floor_level else FLOOR_RISE
		floor_level += (_block_peak - floor_level) * k
	_block_peak = 0.0
	_block_first_loud = -1
	return onset
