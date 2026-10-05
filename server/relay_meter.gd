class_name RelayMeter
extends RefCounted
## The host's debug counters of its voice relay and its upload (ARCHITECTURE §4.5 "The host's
## counters"; the M5 ADR's E47 as amended, §3 item 11 and §4, M5-4): HostSession keeps one in debug
## builds only and adds to it as it relays and sends; totals since the session started. Read through
## HostSession.relay_counters() and HostNode.relay_counters(). The F3 overlay never shows them live
## during a Round: there they would tell the host's player how many hear them (§3 item 11).
##
## The relay's time is Time.get_ticks_usec() around the flush, the encoding and the sends of a poll
## that held frames; the send time around each VoiceBatch's NetTransport.send alone. The upload is
## NetTransport.take_upload() taken before and after the voice sends and the snapshot sends, so each
## gets what went out during it (Godot's put_packet flushes, one datagram per send); whatever went
## out in between (events, and ENet's acknowledgements and pings sent while it polls) counts as
## other. An acknowledgement or ping that rides in a datagram a send flushes counts with that send.

## Frames the transport took towards their listeners (one per listener a frame went to), and the
## VoiceBatch messages that carried them (M5-4b: one or a few per listener per poll).
var sent := 0
var batches := 0
## Microseconds in the relay's flush, encoding and sends, and in the VoiceBatch sends alone.
var relay_usec := 0
var send_usec := 0
## Snapshot messages the transport took.
var snapshots := 0
## Bytes and datagrams sent towards other machines during the voice sends, the snapshot sends, and
## at any other time. Plain ints (64-bit): a Vector2i holds 32-bit ints, and the voice bytes of
## 10 players talking pass 2^31 in about two hours of one session.
var voice_up_bytes := 0
var voice_up_datagrams := 0
var snapshot_up_bytes := 0
var snapshot_up_datagrams := 0
var other_up_bytes := 0
var other_up_datagrams := 0


## Adds one NetTransport.take_upload() (bytes, datagrams) to the voice sends' part.
func add_voice_upload(taken: Vector2i) -> void:
	voice_up_bytes += taken.x
	voice_up_datagrams += taken.y


## Adds one NetTransport.take_upload() (bytes, datagrams) to the snapshot sends' part.
func add_snapshot_upload(taken: Vector2i) -> void:
	snapshot_up_bytes += taken.x
	snapshot_up_datagrams += taken.y


## Adds one NetTransport.take_upload() (bytes, datagrams) to the part sent at any other time.
func add_other_upload(taken: Vector2i) -> void:
	other_up_bytes += taken.x
	other_up_datagrams += taken.y


## The counters by name, with the relay's own (relayed, dropped), the voice frames over budget and
## the session's age added; the overlay and the bots runner print them in name order.
func to_dict(relay: VoiceRelay, over_budget: int, session_usec: int) -> Dictionary[StringName, int]:
	@warning_ignore("integer_division")
	var session_ms := session_usec / 1000
	var found: Dictionary[StringName, int] = {
		&"session_ms": session_ms,
		&"voice_relayed": relay.relayed,
		&"voice_sent": sent,
		&"voice_batches": batches,
		&"voice_dropped": relay.dropped,
		&"voice_over_budget": over_budget,
		&"voice_relay_usec": relay_usec,
		&"voice_send_usec": send_usec,
		&"voice_up_bytes": voice_up_bytes,
		&"voice_up_datagrams": voice_up_datagrams,
		&"snapshots_sent": snapshots,
		&"snapshot_up_bytes": snapshot_up_bytes,
		&"snapshot_up_datagrams": snapshot_up_datagrams,
		&"other_up_bytes": other_up_bytes,
		&"other_up_datagrams": other_up_datagrams,
	}
	return found
