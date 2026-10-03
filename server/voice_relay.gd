class_name VoiceRelay
extends RefCounted
## The host's voice relay (ARCHITECTURE §4.5 "Voice relay", §6, E11). The routing table holds
## `Match.speakers_for(l)` for every present player l, refreshed after every `Match.tick` call
## (catch-up ticks included), so between two ticks it is the routing `view_of` records for the
## last one. A VoiceUp from speaker s goes, as a VoiceDown (s, the stream's next seq, the host
## tick, the bytes unchanged), to each listener l != s whose entry holds s; a frame from a peer
## that is not a present player is dropped. The host never decodes Opus.
##
## Frames are held during one poll and relayed right after it: after a freeze of the host or of the
## speaker only the newest NEWEST_PER_POLL frames per speaker (by the speaker's own seq) are
## relayed and the older ones dropped and counted, because a backlog played late is worse than a
## gap. The seq a listener gets is its own stream's (per speaker and listener), so it cannot tell
## how much s sent to others.
##
## Peer ids are reused (§4): on the transport's peer_left(p), p leaves the relay at once, as speaker
## and listener, until the refresh after the tick that applied its PeerLeft (leave(), refresh()).

## The newest frames relayed per speaker per poll: 100 ms, a placeholder, "not a decision".
const NEWEST_PER_POLL := 5
## VoiceUp's and VoiceDown's seq are u16 (§4.3).
const SEQ_MODULO := 0x10000
## A seq up to this far behind the poll's first frame is older than it, else newer.
const SEQ_HALF := 0x8000
const VOICE_DOWN := &"VoiceDown"

## Frames dropped as an old part of a backlog (over NEWEST_PER_POLL in one poll).
var dropped := 0
## Frames of present players passed on by flush() (the newest NEWEST_PER_POLL per poll), whether
## anyone hears them or not (RelayMeter).
var relayed := 0

## Listener -> the speakers it may hear: every present player has an entry.
var _routes: Dictionary[int, PackedInt32Array] = {}
## Peers that left (peer_left) and are out of the relay until a refresh no longer keeps them.
var _muted: Dictionary[int, bool] = {}
## Vector2i(speaker, listener) -> the next seq of that stream.
var _next_seq: Dictionary[Vector2i, int] = {}
## Speaker -> the frames held in this poll, each [seq, opus], in arrival order.
var _held: Dictionary[int, Array] = {}


## One relayed frame: its listener and its VoiceDown.
class Outgoing:
	extends RefCounted
	var listener: int
	var message: WireMessage

	func _init(to_peer: int, down: WireMessage) -> void:
		listener = to_peer
		message = down


## The routing after a Match.tick call: listener -> speakers_for(listener), one entry per present
## player. A muted peer stays muted while `still_leaving` has it (its PeerLeft is not applied yet,
## or this session disconnected it).
func refresh(table: Dictionary[int, PackedInt32Array], still_leaving: Dictionary) -> void:
	_routes = table
	for peer: int in _muted.keys():
		if not still_leaving.has(peer):
			_muted.erase(peer)


## The transport says `peer` left: it neither speaks nor hears from now on, its frames held in
## this poll are dropped, and its streams start again at seq 0 for whoever takes its id.
func leave(peer: int) -> void:
	_muted[peer] = true
	_held.erase(peer)
	for key: Vector2i in _next_seq.keys():
		if key.x == peer or key.y == peer:
			_next_seq.erase(key)


## Whether `listener` hears `speaker` now.
func routes(listener: int, speaker: int) -> bool:
	if listener == speaker or _muted.has(listener) or _muted.has(speaker):
		return false
	return _routes.has(speaker) and _routes.has(listener) and _routes[listener].has(speaker)


## Whether a frame waits for flush().
func has_held() -> bool:
	return not _held.is_empty()


## Holds one VoiceUp of `speaker` until flush(); dropped at once from a peer that is not a present
## player.
func hold(speaker: int, seq: int, opus: PackedByteArray) -> void:
	if not _routes.has(speaker) or _muted.has(speaker):
		return
	if not _held.has(speaker):
		_held[speaker] = []
	_held[speaker].append([seq, opus])


## The VoiceDowns of the frames held in this poll, stamped with `host_tick`: per speaker in
## peer-id order, its newest frames in its own seq order, each to its listeners in peer-id order.
func flush(host_tick: int) -> Array[Outgoing]:
	var out: Array[Outgoing] = []
	var speakers: Array[int] = []
	speakers.assign(_held.keys())
	speakers.sort()
	var listeners: Array[int] = []
	listeners.assign(_routes.keys())
	listeners.sort()
	for speaker: int in speakers:
		var newest := _newest(_held[speaker])
		relayed += newest.size()
		for frame: Array in newest:
			for listener: int in listeners:
				if not routes(listener, speaker):
					continue
				var key := Vector2i(speaker, listener)
				var seq: int = _next_seq.get(key, 0)
				_next_seq[key] = (seq + 1) % SEQ_MODULO
				var fields := {"speaker": speaker, "seq": seq, "tick": host_tick, "opus": frame[1]}
				out.append(Outgoing.new(listener, WireMessage.new(VOICE_DOWN, fields)))
	_held.clear()
	return out


## The newest NEWEST_PER_POLL of one speaker's frames, ordered by its seq (which wraps at
## SEQ_MODULO; ties keep the arrival order); the rest are counted in `dropped`.
func _newest(frames: Array) -> Array:
	var first: int = frames[0][0]
	var order: Array[Vector2i] = []
	for i in frames.size():
		var seq: int = frames[i][0]
		var ahead := posmod(seq - first + SEQ_HALF, SEQ_MODULO) - SEQ_HALF
		order.append(Vector2i(ahead, i))
	order.sort()
	var kept := order.slice(maxi(0, order.size() - NEWEST_PER_POLL))
	dropped += order.size() - kept.size()
	var newest: Array = []
	for entry: Vector2i in kept:
		newest.append(frames[entry.y])
	return newest
