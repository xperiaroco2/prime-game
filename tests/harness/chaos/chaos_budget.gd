class_name ChaosBudget
extends RefCounted
## What the host must count for one chaos peer, replayed from the packets that peer sent, by the
## rules of ARCHITECTURE §4 and §4.5: a frame NetFrame rejects is counted under its reason and is
## malformed; a valid frame takes its lane's budget first (voice frames, reliable intents with their
## bytes, the bytes of the rest; PeerBudget's numbers, placeholders) and over it is counted
## OVER_BUDGET, answered by nobody and never malformed; then a payload the codec rejects, or a debug
## kind from a peer other than 1, is counted BAD_PAYLOAD and is malformed. MALFORMED_LIMIT malformed
## messages within the window disconnect the peer at once, so what it sent after them in the same
## poll is from a peer that is not connected (UNKNOWN_PEER). What is left decodes and reaches the
## session: the chaos run checks the rules' answers to those (ChaosOracle) through the observer.
##
## The one-process run calls poll() once per host step, right after it, with the packets the peer
## sent since the step before (the loopback delivers each frame's packets at the host's next poll,
## and a chaos peer sends at most one LATEST message per poll, so none is superseded).

## Reason -> how many the host must have counted for this peer.
var expected: Dictionary[int, int] = {}
## The peer was disconnected for malformed messages.
var disconnected := false
## The host time of that disconnect; -1 before.
var disconnected_at_usec := -1
## Chaos intent seq -> how many of its copies were dropped over a budget.
var over_budget_seqs: Dictionary[int, int] = {}
## The well-formed packets that reached the session (decoded), in order.
var reached: Array[ChaosFrames.Packet] = []
## The malformed messages within the window, as host times, oldest first.
var malformed_at: Array[int] = []

var _budget := PeerBudget.new()


## One host step at `now_usec`, `elapsed_usec` after the last: the refill, then `packets` in order.
func poll(now_usec: int, elapsed_usec: int, packets: Array[ChaosFrames.Packet]) -> void:
	_budget.refill(elapsed_usec)
	for packet: ChaosFrames.Packet in packets:
		if disconnected:
			_count(NetRejects.Reason.UNKNOWN_PEER)
			continue
		if not packet.frame_valid:
			_count(packet.expect)
			_malformed(now_usec)
			continue
		if not _take(packet):
			_count(NetRejects.Reason.OVER_BUDGET)
			if packet.seq >= ChaosFrames.CHAOS_SEQ:
				over_budget_seqs[packet.seq] = over_budget_seqs.get(packet.seq, 0) + 1
			continue
		if packet.expect == NetRejects.Reason.BAD_PAYLOAD:
			_count(NetRejects.Reason.BAD_PAYLOAD)
			_malformed(now_usec)
			continue
		reached.append(packet)


## The malformed messages within the window that ends at `now_usec`, as the host counts them.
func malformed_within(now_usec: int) -> int:
	var count := 0
	for at: int in malformed_at:
		if at > now_usec - HostSession.MALFORMED_WINDOW_USEC:
			count += 1
	return count


func expected_total() -> int:
	var sum := 0
	for n: int in expected.values():
		sum += n
	return sum


func _take(packet: ChaosFrames.Packet) -> bool:
	match packet.lane:
		NetKindTable.Lane.VOICE:
			return _budget.take_voice()
		NetKindTable.Lane.RELIABLE:
			return _budget.take_intent(packet.payload_size())
	return _budget.take_bytes(packet.payload_size())


func _count(reason: NetRejects.Reason) -> void:
	expected[reason] = expected.get(reason, 0) + 1


func _malformed(now_usec: int) -> void:
	while (
		not malformed_at.is_empty()
		and (malformed_at[0] <= now_usec - HostSession.MALFORMED_WINDOW_USEC)
	):
		malformed_at.pop_front()
	malformed_at.append(now_usec)
	if malformed_at.size() >= HostSession.MALFORMED_LIMIT:
		disconnected = true
		disconnected_at_usec = now_usec
