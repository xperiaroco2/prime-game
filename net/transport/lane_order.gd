class_name LaneOrder
extends RefCounted
## Restores ENet's channel-0 order of LATEST against RELIABLE for a backend whose channels do not
## keep it: WebRTC's separate data channels now, Steam's unreliable messages later (the M6 design
## §2.2, E49). Without it a MoveClaim (LATEST) sent just before a PickUp (RELIABLE) can arrive
## after it, and the host checks the PickUp against the older claim and refuses it.
##
## The sender prefixes each LATEST packet with HEADER_BYTES: [reliable_sent: u16][latest_seq: u16],
## little-endian and wrapping: how many packets it had written to that peer's RELIABLE channel
## before (every one, ADMIT included), and its own count of LATEST packets to that peer. RELIABLE
## and VOICE packets carry no header. The header sits below NetFrame: what this class hands back
## for delivery is the frame without it.
##
## The receiver counts every packet it reads from RELIABLE, before any decoding, and reads the
## LATEST channel before the RELIABLE one in each poll, so a LATEST packet sent before a reliable
## one comes first, as ENet would deliver it. A LATEST packet is delivered when its reliable_sent
## equals the count and its seq is newer than the last one delivered; held while reliable_sent is
## ahead, until that many reliable packets were read, then judged the same way; dropped when
## reliable_sent is behind (sent before a reliable packet already delivered) or its seq is not
## newer. Counts and seqs compare in serial-number order (RFC 1982), so both wrap.
##
## Pure: no Node, no backend, no clock of its own. The backend:
## - add_peer() when a peer's connection opens (a client: HOST_ID), forget() when the peer leaves
##   or is disconnected (disconnect_peer, peer_left), at once: held packets are discarded, never
##   delivered, and a packet read for a peer it does not know is a REJECTED UNKNOWN_PEER;
## - passes the time, and counts a REJECTED read through the transport's reject path;
## - decodes each Read.superseded frame through the one decode path without delivering it and adds
##   the valid ones to NetTransport.latest_superseded, as the inbox does with its own merge;
## - after reading both channels in a poll, counts NetRejects.Reason.ORDER_STALLED for each peer
##   stalled_peers() names and drops it: the host disconnects it, a client ends as host_lost.

## How a LATEST packet was judged on arrival.
enum Verdict { DELIVERED, HELD, DROPPED, REJECTED }

const HEADER_BYTES := 4
## The longest LATEST packet: the header and the longest frame (NetFrame decodes the rest).
const MAX_PACKET_BYTES := HEADER_BYTES + NetFrame.MAX_PACKET_BYTES
## Held LATEST packets per peer before one is dropped. A placeholder, not a decision (§2.2): a
## freeze's backlog is 50 to 100 packets, of which only the newest of each kind matters after each
## reliable packet they wait for.
const HOLD_CAP := 8
## A hold that no release has emptied for this long is a transport fault: the silence rule's
## (§2.6, WebRtcTransport.SILENCE_MS). A reliable channel loses nothing, so the counts disagree for
## good only through a bug or a binding that drops packets; an honest reliable packet late by
## seconds never reaches it.
const STALL_MS := WebRtcTransport.SILENCE_MS

const _SERIAL := 0x10000
const _HALF := 0x8000

var _peers: Dictionary[int, PeerOrder] = {}


## A read LATEST packet: its verdict, the frame to deliver now (DELIVERED only), why it was
## REJECTED, and the frame the full hold dropped for it, if any (this packet's own, or an older
## held one): not delivered, but decoded like any superseded LATEST packet.
class Read:
	var verdict: Verdict
	var frame := PackedByteArray()
	var reject := NetRejects.Reason.NONE
	var superseded: Array[PackedByteArray] = []

	func _init(read_verdict: Verdict) -> void:
		verdict = read_verdict


class Held:
	var reliable_sent: int
	var seq: int
	## The NetFrame kind byte, or -1 for a packet with no frame after the header. Only the cap's
	## choice uses it; the frame is decoded like any other once delivered or dropped.
	var kind: int
	var frame: PackedByteArray

	func _init(
		header_reliable: int, header_seq: int, frame_kind: int, frame_bytes: PackedByteArray
	) -> void:
		reliable_sent = header_reliable
		seq = header_seq
		kind = frame_kind
		frame = frame_bytes


## One peer's counts in both directions and its hold.
class PeerOrder:
	var reliable_sent := 0
	var latest_seq := 0
	var reliable_received := 0
	var has_delivered := false
	var last_delivered := 0
	var held: Array[Held] = []
	## When the hold last turned non-empty or released a packet; -1 while it is empty.
	var hold_since_ms := -1


## A connection to peer_id opened: its counts start at 0 both ways.
func add_peer(peer_id: int) -> void:
	_peers[peer_id] = PeerOrder.new()


## The peer left or was disconnected: its held packets are discarded, never delivered, and what
## it sends later is rejected as from an unknown peer.
func forget(peer_id: int) -> void:
	_peers.erase(peer_id)


## Forgets every peer: the transport closed.
func clear() -> void:
	_peers.clear()


func has_peer(peer_id: int) -> bool:
	return _peers.has(peer_id)


# The sender.


## Call after each packet written to to_peer's RELIABLE channel, ADMIT included: only one the
## channel accepted (an error from the binding sent nothing, and counting it would hold every later
## LATEST packet until the peer stalls).
func count_reliable_sent(to_peer: int) -> void:
	if _peers.has(to_peer):
		var peer := _peers[to_peer]
		peer.reliable_sent = (peer.reliable_sent + 1) % _SERIAL


## The LATEST packet to write to to_peer: the header, then the frame. Empty for a peer it does not
## know: send nothing.
func stamp_latest(to_peer: int, frame: PackedByteArray) -> PackedByteArray:
	var bytes := PackedByteArray()
	if not _peers.has(to_peer):
		return bytes
	var peer := _peers[to_peer]
	bytes.resize(HEADER_BYTES)
	bytes.encode_u16(0, peer.reliable_sent)
	bytes.encode_u16(2, peer.latest_seq)
	bytes.append_array(frame)
	peer.latest_seq = (peer.latest_seq + 1) % _SERIAL
	return bytes


# The receiver.


## Judges a packet read from from_peer's LATEST channel at now_ms. Every frame it hands back,
## delivered or superseded, goes through the transport's one decode path.
func read_latest(from_peer: int, bytes: PackedByteArray, now_ms: int) -> Read:
	var reject := _reject_of(from_peer, bytes)
	if reject != NetRejects.Reason.NONE:
		var rejected := Read.new(Verdict.REJECTED)
		rejected.reject = reject
		return rejected
	var peer := _peers[from_peer]
	var sent := bytes.decode_u16(0)
	var seq := bytes.decode_u16(2)
	if peer.has_delivered and not _is_newer(seq, peer.last_delivered):
		return Read.new(Verdict.DROPPED)
	var lead := _serial_diff(sent, peer.reliable_received)
	if lead < 0:
		return Read.new(Verdict.DROPPED)
	var frame := bytes.slice(HEADER_BYTES)
	if lead > 0:
		var kind := frame.decode_u8(0) if frame.size() > 0 else -1
		return _hold(peer, Held.new(sent, seq, kind, frame), now_ms)
	peer.has_delivered = true
	peer.last_delivered = seq
	var read := Read.new(Verdict.DELIVERED)
	read.frame = frame
	return read


## Call for every packet read from from_peer's RELIABLE channel, before decoding it. Returns the
## held frames that this packet released and that are delivered, oldest first: they were sent
## right after it, so the caller hands them to the inbox right after it.
func read_reliable(from_peer: int, now_ms: int) -> Array[PackedByteArray]:
	var delivered: Array[PackedByteArray] = []
	if not _peers.has(from_peer):
		return delivered
	var peer := _peers[from_peer]
	peer.reliable_received = (peer.reliable_received + 1) % _SERIAL
	var released: Array[Held] = []
	var kept: Array[Held] = []
	for held in peer.held:
		if _serial_diff(held.reliable_sent, peer.reliable_received) > 0:
			kept.append(held)
		else:
			released.append(held)
	if released.is_empty():
		return delivered
	peer.held = kept
	peer.hold_since_ms = -1 if kept.is_empty() else now_ms
	# By distance from one reference seq: a plain integer order even for seqs a hostile peer
	# spreads around the circle, where serial-number order is not transitive.
	var base := peer.last_delivered if peer.has_delivered else released[0].seq
	released.sort_custom(
		func(a: Held, b: Held) -> bool: return _serial_diff(a.seq, base) < _serial_diff(b.seq, base)
	)
	for held in released:
		if peer.has_delivered and not _is_newer(held.seq, peer.last_delivered):
			continue
		peer.has_delivered = true
		peer.last_delivered = held.seq
		delivered.append(held.frame)
	return delivered


## The peers whose hold no release has emptied for more than STALL_MS at now_ms: a transport
## fault. Call after both channels were read in a poll. Each one is named once and forgotten.
func stalled_peers(now_ms: int) -> PackedInt32Array:
	var stalled := PackedInt32Array()
	for peer_id: int in _peers:
		var since := _peers[peer_id].hold_since_ms
		if since >= 0 and now_ms - since > STALL_MS:
			stalled.append(peer_id)
	stalled.sort()
	for peer_id in stalled:
		forget(peer_id)
	return stalled


## Held LATEST packets of peer_id (for tests and debug counters).
func held_count(peer_id: int) -> int:
	return _peers[peer_id].held.size() if _peers.has(peer_id) else 0


func _reject_of(from_peer: int, bytes: PackedByteArray) -> NetRejects.Reason:
	if bytes.size() < HEADER_BYTES:
		return NetRejects.Reason.ORDER_HEADER_SHORT
	if bytes.size() > MAX_PACKET_BYTES:
		return NetRejects.Reason.TOO_LARGE
	if not _peers.has(from_peer):
		return NetRejects.Reason.UNKNOWN_PEER
	return NetRejects.Reason.NONE


func _hold(peer: PeerOrder, arriving: Held, now_ms: int) -> Read:
	for other in peer.held:
		if other.seq == arriving.seq:
			return Read.new(Verdict.DROPPED)  # A duplicate: the first copy is already waiting.
	if peer.held.size() < HOLD_CAP:
		if peer.held.is_empty():
			peer.hold_since_ms = now_ms
		peer.held.append(arriving)
		return Read.new(Verdict.HELD)
	var dropped := _to_drop(peer.held, arriving)
	var read := Read.new(Verdict.DROPPED if dropped == arriving else Verdict.HELD)
	read.superseded.append(dropped.frame)
	if dropped != arriving:
		peer.held.erase(dropped)
		peer.held.append(arriving)
	return read


## Which packet a full hold drops, the arriving one included. First the oldest of the arriving
## one's kind that a newer one of its kind waiting for the same reliable packet follows: both are
## released into one poll, where the inbox's merge would drop it anyway, so nothing is lost. Only
## when there is none (as many reliable packets in flight as the hold is long), the oldest of that
## kind (§2.2's rule), which loses the state sent between two reliable packets; and with none of
## that kind held, the arriving packet itself, so a peer cannot push out another kind's packets.
func _to_drop(held: Array[Held], arriving: Held) -> Held:
	var candidates: Array[Held] = []
	for other in held:
		if other.kind == arriving.kind:
			candidates.append(other)
	candidates.append(arriving)
	# Oldest first, by distance from the arriving seq (see read_reliable).
	candidates.sort_custom(
		func(a: Held, b: Held) -> bool:
			return _serial_diff(a.seq, arriving.seq) < _serial_diff(b.seq, arriving.seq)
	)
	for i in candidates.size():
		for j in range(i + 1, candidates.size()):
			if candidates[j].reliable_sent == candidates[i].reliable_sent:
				return candidates[i]
	return candidates[0]


## a - b in serial-number order: positive when a is ahead of b, negative when behind. The one
## ambiguous distance, half the range, counts as behind.
static func _serial_diff(a: int, b: int) -> int:
	var diff := (a - b + _SERIAL) % _SERIAL
	return diff if diff < _HALF else diff - _SERIAL


static func _is_newer(a: int, b: int) -> bool:
	return _serial_diff(a, b) > 0
