class_name NetRejects
extends RefCounted
## Counts received packets the transport rejected, by reason and by peer, and the messages that
## the host session dropped after the transport (OVER_BUDGET, BAD_PAYLOAD; ARCHITECTURE §4.5), so
## one summary line holds them all. One peer can send thousands of bad packets a second, so nothing
## logs one line per packet: the transport logs take_summary() at most once per interval
## (NetTransport.REJECT_SUMMARY_INTERVAL_MS).

enum Reason {
	NONE,
	TOO_SHORT,
	TOO_LARGE,
	UNKNOWN_KIND,
	WRONG_DIRECTION,
	WRONG_LANE,
	PAYLOAD_TOO_LARGE,
	TRUNCATED,
	TRAILING_BYTES,
	UNKNOWN_PEER,
	## server/: over one of the peer's budgets, dropped before decoding (§4.5); not malformed.
	OVER_BUDGET,
	## server/: the codec rejected the payload, or a debug kind came from a peer other than 1.
	BAD_PAYLOAD,
	## A LATEST packet shorter than LaneOrder's header (WebRTC and later backends).
	ORDER_HEADER_SHORT,
	## LaneOrder: a hold that no reliable packet released for LaneOrder.STALL_MS, a transport fault
	## that disconnects the peer (the M6 ADR §2.2).
	ORDER_STALLED,
	## WebRTC: one of a peer's data channels closed while its connection stayed up, and the host
	## was not closing that peer; the peer leaves (the M6 ADR §2.6).
	CHANNEL_CLOSED,
}

## Peers named in one summary line; the rest are summed up.
const SUMMARY_PEERS := 5

var _total := 0
var _by_reason: Dictionary[int, int] = {}
var _pending_by_reason: Dictionary[int, int] = {}
## Per peer only since the last summary: peer ids are chosen by clients, so a lifetime count per
## id would grow with every reconnect.
var _pending_by_peer: Dictionary[int, int] = {}


func count(peer_id: int, reason: Reason) -> void:
	_total += 1
	_by_reason[reason] = _by_reason.get(reason, 0) + 1
	_pending_by_reason[reason] = _pending_by_reason.get(reason, 0) + 1
	_pending_by_peer[peer_id] = _pending_by_peer.get(peer_id, 0) + 1


func total() -> int:
	return _total


func of_reason(reason: Reason) -> int:
	return _by_reason.get(reason, 0)


## Rejections from this peer since the last summary.
func from_peer(peer_id: int) -> int:
	return _pending_by_peer.get(peer_id, 0)


## Every rejection so far by reason, "REASON xN, ...", or "none" (a test's failure message: the
## summaries may have been logged and taken already).
func totals() -> String:
	var reasons := PackedStringArray()
	for reason: int in _sorted_by_count(_by_reason):
		reasons.append("%s x%d" % [Reason.find_key(reason), _by_reason[reason]])
	return ", ".join(reasons) if not reasons.is_empty() else "none"


## Rejections since the last summary.
func pending() -> int:
	var sum := 0
	for n: int in _pending_by_reason.values():
		sum += n
	return sum


## One line about the rejections since the last summary, or "" when there were none.
func take_summary() -> String:
	var count_now := pending()
	if count_now == 0:
		return ""
	var reasons := PackedStringArray()
	for reason: int in _sorted_by_count(_pending_by_reason):
		reasons.append("%s x%d" % [Reason.find_key(reason), _pending_by_reason[reason]])
	var peers := PackedStringArray()
	var peer_ids := _sorted_by_count(_pending_by_peer)
	for peer_id: int in peer_ids.slice(0, SUMMARY_PEERS):
		peers.append("%d x%d" % [peer_id, _pending_by_peer[peer_id]])
	if peer_ids.size() > SUMMARY_PEERS:
		peers.append("and %d more" % (peer_ids.size() - SUMMARY_PEERS))
	_pending_by_reason.clear()
	_pending_by_peer.clear()
	return (
		"net: rejected %d packet(s): %s; from peer(s) %s"
		% [count_now, ", ".join(reasons), ", ".join(peers)]
	)


static func _sorted_by_count(counts: Dictionary[int, int]) -> Array[int]:
	var keys: Array[int] = []
	keys.assign(counts.keys())
	keys.sort_custom(
		func(a: int, b: int) -> bool:
			return counts[a] > counts[b] or (counts[a] == counts[b] and a < b)
	)
	return keys
