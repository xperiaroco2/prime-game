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
## Pure: no Node, no backend, no clock of its own. The caller passes the time, adds
## take_superseded() to NetTransport.latest_superseded, counts a REJECTED read through the
## transport's reject path, disconnects each peer stalled_peers() names (counting
## NetRejects.Reason.ORDER_STALLED), and calls forget() when a peer leaves or is disconnected.
## Its packets: from the host, peer ids; on a client, NetTransport.HOST_ID.

## How a LATEST packet was judged on arrival.
enum Verdict { DELIVERED, HELD, DROPPED, REJECTED }

const HEADER_BYTES := 4
## Held LATEST packets per peer before the oldest of the arriving one's kind is dropped. A
## placeholder, not a decision (§2.2): a freeze's backlog is 50 to 100 packets, of which only the
## newest of each kind matters after the reliable packet they wait for.
const HOLD_CAP := 8
## A hold that no release has emptied for this long is a transport fault: the silence rule's 20 s
## (§2.6). A reliable channel loses nothing, so the counts disagree for good only through a bug or
## a binding that drops packets; an honest reliable packet late by seconds never reaches it.
const STALL_MS := 20000

const _SERIAL := 0x10000
const _HALF := 0x8000

var _peers: Dictionary[int, PeerOrder] = {}
var _superseded := 0


## A read LATEST packet: its verdict, the frame to deliver now (DELIVERED only) and, for
## REJECTED, why.
class Read:
	var verdict: Verdict
	var frame := PackedByteArray()
	var reject := NetRejects.Reason.NONE

	func _init(read_verdict: Verdict) -> void:
		verdict = read_verdict


class Held:
	var reliable_sent: int
	var seq: int
	## The NetFrame kind byte, or -1 for a packet with no frame after the header. Only the cap's
	## eviction uses it; the frame is decoded like any other once delivered.
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
	## In arrival order.
	var held: Array[Held] = []
	## When the hold last turned non-empty or released a packet; -1 while it is empty.
	var hold_since_ms := -1


# The sender.


## Call after each packet written to to_peer's RELIABLE channel, ADMIT included.
func count_reliable_sent(to_peer: int) -> void:
	var peer := _peer(to_peer)
	peer.reliable_sent = (peer.reliable_sent + 1) % _SERIAL


## The LATEST packet to write to to_peer: the header, then the frame.
func stamp_latest(to_peer: int, frame: PackedByteArray) -> PackedByteArray:
	var peer := _peer(to_peer)
	var bytes := PackedByteArray()
	bytes.resize(HEADER_BYTES)
	bytes.encode_u16(0, peer.reliable_sent)
	bytes.encode_u16(2, peer.latest_seq)
	bytes.append_array(frame)
	peer.latest_seq = (peer.latest_seq + 1) % _SERIAL
	return bytes


# The receiver.


## Judges a packet read from from_peer's LATEST channel at now_ms. Valid or not, every frame it
## hands back goes through the transport's one decode path.
func read_latest(from_peer: int, bytes: PackedByteArray, now_ms: int) -> Read:
	if bytes.size() < HEADER_BYTES:
		var short := Read.new(Verdict.REJECTED)
		short.reject = NetRejects.Reason.ORDER_HEADER_SHORT
		return short
	var peer := _peer(from_peer)
	var sent := bytes.decode_u16(0)
	var seq := bytes.decode_u16(2)
	var frame := bytes.slice(HEADER_BYTES)
	if peer.has_delivered and not _is_newer(seq, peer.last_delivered):
		return Read.new(Verdict.DROPPED)
	var lead := _serial_diff(sent, peer.reliable_received)
	if lead > 0:
		_hold(
			peer, Held.new(sent, seq, frame.decode_u8(0) if frame.size() > 0 else -1, frame), now_ms
		)
		return Read.new(Verdict.HELD)
	if lead < 0:
		return Read.new(Verdict.DROPPED)
	peer.has_delivered = true
	peer.last_delivered = seq
	var read := Read.new(Verdict.DELIVERED)
	read.frame = frame
	return read


## Call for every packet read from from_peer's RELIABLE channel, before decoding it. Returns the
## held frames that this packet released and that are delivered, oldest first: they were sent
## right after it, so the caller hands them to the inbox right after it.
func read_reliable(from_peer: int, now_ms: int) -> Array[PackedByteArray]:
	var peer := _peer(from_peer)
	peer.reliable_received = (peer.reliable_received + 1) % _SERIAL
	var released: Array[Held] = []
	var kept: Array[Held] = []
	for held in peer.held:
		if _serial_diff(held.reliable_sent, peer.reliable_received) > 0:
			kept.append(held)
		else:
			released.append(held)
	var delivered: Array[PackedByteArray] = []
	if released.is_empty():
		return delivered
	peer.held = kept
	peer.hold_since_ms = -1 if kept.is_empty() else now_ms
	released.sort_custom(func(a: Held, b: Held) -> bool: return _is_newer(b.seq, a.seq))
	for held in released:
		if held.reliable_sent != peer.reliable_received:
			continue
		if peer.has_delivered and not _is_newer(held.seq, peer.last_delivered):
			continue
		peer.has_delivered = true
		peer.last_delivered = held.seq
		delivered.append(held.frame)
	return delivered


## The peers whose hold no release has emptied for more than STALL_MS at now_ms: a transport
## fault. Call after both channels were read in a poll. Lists a peer until forget().
func stalled_peers(now_ms: int) -> PackedInt32Array:
	var stalled := PackedInt32Array()
	for peer_id: int in _peers:
		var since := _peers[peer_id].hold_since_ms
		if since >= 0 and now_ms - since > STALL_MS:
			stalled.append(peer_id)
	stalled.sort()
	return stalled


## Held LATEST packets of peer_id (for tests and debug counters).
func held_count(peer_id: int) -> int:
	return _peers[peer_id].held.size() if _peers.has(peer_id) else 0


## LATEST packets dropped at the hold's cap since the last call: valid or not, each one had a newer
## packet of its kind behind it. The caller adds them to NetTransport.latest_superseded.
func take_superseded() -> int:
	var found := _superseded
	_superseded = 0
	return found


## The peer left or was disconnected: its held packets are discarded, never delivered, and its
## counts start again for a new connection.
func forget(peer_id: int) -> void:
	_peers.erase(peer_id)


## Forgets every peer: the transport closed.
func clear() -> void:
	_peers.clear()


func _peer(peer_id: int) -> PeerOrder:
	if not _peers.has(peer_id):
		_peers[peer_id] = PeerOrder.new()
	return _peers[peer_id]


func _hold(peer: PeerOrder, held: Held, now_ms: int) -> void:
	for other in peer.held:
		if other.seq == held.seq:
			return  # A duplicate: the first copy is already waiting.
	if peer.held.size() >= HOLD_CAP:
		peer.held.remove_at(_oldest_to_drop(peer.held, held.kind))
		_superseded += 1
	if peer.held.is_empty():
		peer.hold_since_ms = now_ms
	peer.held.append(held)


## The oldest held packet (by seq) of that kind; with none of it, the oldest held packet, so the
## hold stays bounded whatever a peer sends.
func _oldest_to_drop(held: Array[Held], kind: int) -> int:
	var oldest := -1
	for i in held.size():
		if held[i].kind == kind and (oldest < 0 or _is_newer(held[oldest].seq, held[i].seq)):
			oldest = i
	if oldest >= 0:
		return oldest
	oldest = 0
	for i in held.size():
		if _is_newer(held[oldest].seq, held[i].seq):
			oldest = i
	return oldest


## a - b in serial-number order: positive when a is ahead of b, negative when behind. The one
## ambiguous distance, half the range, counts as behind.
static func _serial_diff(a: int, b: int) -> int:
	var diff := (a - b + _SERIAL) % _SERIAL
	return diff if diff < _HALF else diff - _SERIAL


static func _is_newer(a: int, b: int) -> bool:
	return _serial_diff(a, b) > 0
