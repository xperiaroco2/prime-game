class_name SpikeVoiceRelay
extends RefCounted
## Spike (#15): the host's side of proximity voice, pure (no nodes, no sockets). Voice is relayed
## through the host, never sent between clients directly: a client can reach only the host (the
## #13 transport has server relay off), and a client never receives, nor learns about, voice the
## routing rule does not entitle it to (ARCHITECTURE invariant 2).
## relay() checks one VOICE_UP frame and returns what to send to whom; the caller sends it.
## The host checks the intent crudely: the speaker must be a placed player, and a per-speaker
## budget of MAX_FRAMES_PER_SECOND drops a flood. The host never decodes the Opus payload.

const MAX_FRAMES_PER_SECOND := 75.0  # a speaker sends 50; room for a burst after a hitch

var routing := SpikeVoiceRouting.new()
var received: Dictionary[int, int] = {}  # frames that reached the host, per speaker
# "speaker>listener": frames delivered, and frames culled by the routing rule
var delivered: Dictionary[String, int] = {}
var culled: Dictionary[String, int] = {}
var dropped_flood := 0
var dropped_unplaced := 0
var max_delivered_distance := -1.0
var min_culled_distance := INF
var payload_bytes_out := 0
var _budget: Dictionary[int, float] = {}


## Refills every speaker's frame budget; call once per host frame, before reading packets.
func advance(delta: float) -> void:
	for id: int in _budget:
		_budget[id] = minf(_budget[id] + delta * MAX_FRAMES_PER_SECOND, MAX_FRAMES_PER_SECOND)


func forget(id: int) -> void:
	_budget.erase(id)


## The packets to send for one frame from `speaker`, as [[listener: int, bytes], ...].
## `positions` holds the host-accepted position of every placed player.
func relay(
	speaker: int, seq: int, opus: PackedByteArray, positions: Dictionary[int, Vector3]
) -> Array[Array]:
	var out: Array[Array] = []
	received[speaker] = received.get(speaker, 0) + 1
	if not positions.has(speaker):
		dropped_unplaced += 1
		return out
	var budget: float = _budget.get(speaker, MAX_FRAMES_PER_SECOND)
	if budget < 1.0:
		dropped_flood += 1
		return out
	_budget[speaker] = budget - 1.0
	var hears := routing.listeners_of(speaker, positions)
	var bytes := SpikeVoiceMessages.encode_down(speaker, seq, opus)
	var from := positions[speaker]
	for id: int in positions:
		if id == speaker:
			continue
		var pair := "%d>%d" % [speaker, id]
		var distance := from.distance_to(positions[id])
		if hears.has(id):
			delivered[pair] = delivered.get(pair, 0) + 1
			max_delivered_distance = maxf(max_delivered_distance, distance)
			payload_bytes_out += bytes.size()
			out.append([id, bytes])
		else:
			culled[pair] = culled.get(pair, 0) + 1
			min_culled_distance = minf(min_culled_distance, distance)
	return out
