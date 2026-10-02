class_name RejectLedger
extends RefCounted
## Every rejection a host's transport counted, by peer and NetRejects reason, for a whole chaos run
## (ARCHITECTURE §4, §4.5): what the transport rejected and what server/ dropped after it
## (OVER_BUDGET, BAD_PAYLOAD). NetRejects keeps its per-peer counts only between two summary lines
## (peer ids are reused), so the chaos run keeps its own, lifetime count here; the counting
## transports (CountingLoopback, CountingEnet) fill it from NetTransport._note_reject, the one place
## every rejection passes. The leak test's exemption for the chaos peers is scoped through it: the
## counts from every other peer stay zero (ChaosRun.host_problems).

## Peer -> reason -> count.
var _counts: Dictionary[int, Dictionary] = {}


func count(peer: int, reason: NetRejects.Reason) -> void:
	if not _counts.has(peer):
		_counts[peer] = {}
	var by_reason: Dictionary = _counts[peer]
	by_reason[reason] = (by_reason.get(reason, 0) as int) + 1


## The rejections of `peer` for `reason`.
func of(peer: int, reason: NetRejects.Reason) -> int:
	var by_reason: Dictionary = _counts.get(peer, {})
	return by_reason.get(reason, 0)


## Every rejection of `peer`.
func total_from(peer: int) -> int:
	var sum := 0
	for n: int in (_counts.get(peer, {}) as Dictionary).values():
		sum += n
	return sum


## Every rejection of a peer other than those in `peers`.
func total_except(peers: Array[int]) -> int:
	var sum := 0
	for peer: int in _counts:
		if not peers.has(peer):
			sum += total_from(peer)
	return sum


## Reason -> count for `peer`, by the reason's name ("BAD_PAYLOAD": 3), for a report.
func named(peer: int) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var by_reason: Dictionary = _counts.get(peer, {})
	for reason: int in by_reason:
		out[NetRejects.Reason.find_key(reason)] = by_reason[reason]
	return out
