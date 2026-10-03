class_name RelayMeter
extends RefCounted
## The host's debug counters of its voice relay and its upload (ARCHITECTURE §4.5 "The host's
## counters"; the M5 ADR's E47 as amended, §3 item 11 and §4, M5-4): HostSession keeps one in debug
## builds only and adds to it as it relays and sends; totals since the session started. Read through
## HostSession.relay_counters() and HostNode.relay_counters(). The F3 overlay never shows them live
## during a Round: there they would tell the host's player how many hear them (§3 item 11).
##
## The relay's time is Time.get_ticks_usec() around the flush, the encoding and the sends of a poll
## that held frames; the send time around each VoiceDown's NetTransport.send alone. The upload is
## NetTransport.take_upload() taken before and after the voice sends and the snapshot sends, so each
## gets what went out during it (Godot's put_packet flushes, one datagram per send); whatever went
## out in between (events, ENet's acknowledgements and pings, sent while it polls) counts as other.

## VoiceDown messages the transport took.
var sent := 0
## Microseconds in the relay's flush, encoding and sends, and in the VoiceDown sends alone.
var relay_usec := 0
var send_usec := 0
## Snapshot messages the transport took.
var snapshots := 0
## (bytes, datagrams) sent towards other machines during the voice sends, the snapshot sends, and
## at any other time.
var voice_upload := Vector2i.ZERO
var snapshot_upload := Vector2i.ZERO
var other_upload := Vector2i.ZERO


## The counters by name, with the relay's own (relayed, dropped), the voice frames over budget and
## the session's age added; the overlay and the bots runner print them in name order.
func to_dict(relay: VoiceRelay, over_budget: int, session_usec: int) -> Dictionary[StringName, int]:
	@warning_ignore("integer_division")
	var session_ms := session_usec / 1000
	var found: Dictionary[StringName, int] = {
		&"session_ms": session_ms,
		&"voice_relayed": relay.relayed,
		&"voice_sent": sent,
		&"voice_dropped": relay.dropped,
		&"voice_over_budget": over_budget,
		&"voice_relay_usec": relay_usec,
		&"voice_send_usec": send_usec,
		&"voice_up_bytes": voice_upload.x,
		&"voice_up_datagrams": voice_upload.y,
		&"snapshots_sent": snapshots,
		&"snapshot_up_bytes": snapshot_upload.x,
		&"snapshot_up_datagrams": snapshot_upload.y,
		&"other_up_bytes": other_upload.x,
		&"other_up_datagrams": other_upload.y,
	}
	return found
