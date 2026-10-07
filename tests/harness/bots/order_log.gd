class_name OrderLog
extends RefCounted
## The order check of the leak test over WebRTC (the M6 design §5, M6-6): each peer's RELIABLE and
## LATEST messages arrive in the order they were sent in. WebRTC carries the two lanes on separate
## data channels, and LaneOrder restores ENet's order between them; this check sees it end to end.
##
## A transport (BotWebRtc) records, per peer, every RELIABLE and LATEST message it sent (the
## channel took it) and every one it delivered (packet_received, after the inbox's LATEST merge), as
## a fingerprint of its kind and payload. What one side delivered from a peer must be what that peer
## sent, in order, with LATEST messages left out at most (dropped, merged or superseded) and never a
## RELIABLE one: `problems` walks both lists. VOICE is unordered by design and not checked.
##
## A sender's list may be a prefix (a remote bot writes its view file before it leaves, and its
## claims go on): a delivered message found nowhere after the walk's place but before it arrived out
## of order; one found nowhere was sent after the list ended, and the walk stops there. Messages are
## unique in practice (a claim carries its tick, an intent its seq, a snapshot its tick), so a
## message found before the walk's place is the same one, not a twin.

## How many problems one direction reports at most: the first explains the rest.
const MAX_PROBLEMS := 3

## Peer -> its lists.
var _peers: Dictionary[int, Lists] = {}


## One peer's lists: the fingerprints of what was sent to it, whether each one was RELIABLE (1) or
## LATEST (0), and the fingerprints of what was delivered from it.
class Lists:
	extends RefCounted
	var sent := PackedInt64Array()
	var reliable := PackedByteArray()
	var delivered := PackedInt64Array()


## A message's fingerprint: its payload's hash, its kind and its size. A hash collision can hide a
## problem, and in a remote bot's file (very rarely) make one up.
static func fingerprint(kind: int, payload: PackedByteArray) -> int:
	return (hash(payload) & 0xFFFFFFFF) | (kind << 32) | ((payload.size() & 0xFFFF) << 40)


func record_sent(to_peer: int, kind: int, payload: PackedByteArray, reliable: bool) -> void:
	var lists := of(to_peer)
	lists.sent.append(fingerprint(kind, payload))
	lists.reliable.append(1 if reliable else 0)


func record_delivered(from_peer: int, kind: int, payload: PackedByteArray) -> void:
	of(from_peer).delivered.append(fingerprint(kind, payload))


## The lists of `peer` (empty ones for a peer never recorded).
func of(peer: int) -> Lists:
	if not _peers.has(peer):
		_peers[peer] = Lists.new()
	return _peers[peer]


## The lists of `peer` as plain data (a view file's `order`).
func to_data(peer: int) -> Dictionary:
	var lists := of(peer)
	return {"sent": lists.sent, "reliable": lists.reliable, "delivered": lists.delivered}


## Lists from to_data's plain data; empty ones from anything else.
static func from_data(data: Variant) -> Lists:
	var lists := Lists.new()
	if data is Dictionary:
		var fields: Dictionary = data
		if fields.get("sent") is PackedInt64Array:
			lists.sent = fields["sent"]
		if fields.get("reliable") is PackedByteArray:
			lists.reliable = fields["reliable"]
		if fields.get("delivered") is PackedInt64Array:
			lists.delivered = fields["delivered"]
	return lists


## Both directions between this side, the host, and a client's own lists (`client`, its peer
## `peer` here), headed by `label` ("bot 2"); empty when the order held. `client_complete`: the
## client's lists are whole (it runs in this process), not a file written before its last sends.
func check_client(
	label: String, peer: int, client: Lists, client_complete := false
) -> PackedStringArray:
	var mine := of(peer)
	var found := PackedStringArray()
	# A recording that broke would pass any walk: a client that sent or was sent anything (a lurker
	# neither) has something delivered.
	if client.delivered.is_empty() and not mine.sent.is_empty():
		found.append(
			"host to %s: %d messages sent, none recorded as delivered" % [label, mine.sent.size()]
		)
	if client.sent.is_empty() and not mine.delivered.is_empty():
		found.append(
			"%s to host: %d delivered, none recorded as sent" % [label, mine.delivered.size()]
		)
	if mine.delivered.is_empty() and not client.sent.is_empty():
		found.append(
			"%s to host: %d messages sent, none recorded as delivered" % [label, client.sent.size()]
		)
	found.append_array(
		problems("host to %s" % label, mine.sent, mine.reliable, client.delivered, true)
	)
	found.append_array(
		problems(
			"%s to host" % label, client.sent, client.reliable, mine.delivered, client_complete
		)
	)
	return found


## What went wrong between a sender's lists (`sent_to`, `reliable`) and what the other side
## delivered from it (`got`), headed by `label` ("host to bot 2"); empty when the order held.
## `complete`: `sent_to` holds everything the sender sent so far (the host's own lists when it
## checks, or a client's in the same process), so a delivered message missing from it was never
## sent to this peer. Otherwise (a remote bot's file) the first one missing was sent after the file
## ended: every RELIABLE message the file holds past the walk's place was sent before it and must
## have been delivered, and no message the file holds may be delivered after it.
static func problems(
	label: String,
	sent_to: PackedInt64Array,
	reliable: PackedByteArray,
	got: PackedInt64Array,
	complete: bool
) -> PackedStringArray:
	var found := PackedStringArray()
	var first_at: Dictionary[int, int] = {}
	for i in sent_to.size():
		if not first_at.has(sent_to[i]):
			first_at[sent_to[i]] = i
	var at := 0
	var past_end := false
	for n in got.size():
		var message := got[n]
		if past_end:
			if first_at.has(message):
				found.append(
					(
						"%s: message %d was delivered after one sent after the list's end"
						% [label, first_at[message]]
					)
				)
				return found
			continue
		var match_at := _find(sent_to, message, at)
		if match_at >= 0:
			var skipped := _reliable_in(reliable, at, match_at)
			if skipped >= 0:
				found.append(
					(
						"%s: RELIABLE message %d was not delivered before message %d"
						% [label, skipped, match_at]
					)
				)
				return found
			at = match_at + 1
		elif first_at.has(message):
			found.append(
				(
					"%s: message %d was delivered after message %d, which was sent after it"
					% [label, first_at[message], at - 1]
				)
			)
			if found.size() >= MAX_PROBLEMS:
				return found
		elif complete:
			found.append("%s: delivered message %d was never sent to it" % [label, n])
			return found
		else:
			past_end = true
			var lost := _reliable_in(reliable, at, sent_to.size())
			if lost >= 0:
				found.append(
					(
						"%s: RELIABLE message %d was not delivered before one sent after the list"
						% [label, lost]
					)
				)
				return found
	return found


## The first RELIABLE message in [from, to), or -1.
static func _reliable_in(reliable: PackedByteArray, from: int, to: int) -> int:
	for i in range(from, to):
		if reliable[i] == 1:
			return i
	return -1


## One line on what was checked between this side, the host, and a client: the messages each way.
func summary(label: String, peer: int, client: Lists) -> String:
	var mine := of(peer)
	return (
		"%s: host to it %d sent, %d delivered; it to host %d sent, %d delivered"
		% [
			label,
			mine.sent.size(),
			client.delivered.size(),
			client.sent.size(),
			mine.delivered.size()
		]
	)


static func _find(list: PackedInt64Array, message: int, from: int) -> int:
	for i in range(from, list.size()):
		if list[i] == message:
			return i
	return -1
