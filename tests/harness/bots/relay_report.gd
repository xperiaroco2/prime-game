class_name RelayReport
extends RefCounted
## The host's voice relay counters (HostSession.relay_counters, RelayMeter; ARCHITECTURE §4.5
## "The host's counters") in the words of the M5 ADR's §4 measurement, for the bots runner's prints
## over ENet (M5-4): per window, the difference of two readings; at the end, every total.
##
## Derived: VoiceDowns sent per 20 ms (the streams on the wire while everyone talks), the relay's
## microseconds per 20 ms and per send, the send alone per send, and the upload in Mbit/s on the
## wire: the bytes take_upload counted (ENet's headers included) plus IP_UDP_BYTES per datagram.
## Over WebRTC take_upload already counts them (WebRtcTransport.PACKET_OVERHEAD_BYTES, E56): the
## caller passes 0.

## IPv4 and UDP headers per datagram, which ENet's statistics leave out.
const IP_UDP_BYTES := 28
const FRAME_MS := 20.0
const BITS_PER_BYTE := 8.0
const MBIT := 1000000.0


## One line for the window from `before` to `now` (two readings of relay_counters), headed by
## `label`, with `ip_udp_bytes` added per datagram; empty when no time passed.
static func window(
	label: String,
	before: Dictionary[StringName, int],
	now: Dictionary[StringName, int],
	ip_udp_bytes := IP_UDP_BYTES
) -> String:
	var delta := _difference(before, now)
	var ms: int = delta.get(&"session_ms", 0)
	if ms <= 0:
		return ""
	var frames := ms / FRAME_MS
	var seconds := ms / 1000.0
	var sent: int = delta[&"voice_sent"]
	var per_send := "-"
	var send_alone := "-"
	if sent > 0:
		per_send = "%.1f" % (delta[&"voice_relay_usec"] / float(sent))
		send_alone = "%.1f" % (delta[&"voice_send_usec"] / float(sent))
	var voice := _mbit(delta, &"voice", seconds, ip_udp_bytes)
	var snapshots := _mbit(delta, &"snapshot", seconds, ip_udp_bytes)
	var other := _mbit(delta, &"other", seconds, ip_udp_bytes)
	return (
		(
			"%s %.1f-%.1f s: relayed %d, sent %d (%.1f per 20 ms), dropped %d, over budget %d;"
			+ " relay %.0f us per 20 ms (%s us per send, %s in the send);"
			+ " upload voice %.3f, snapshots %.3f, other %.3f, total %.3f Mbit/s"
			+ " (%d voice datagrams)"
		)
		% [
			label,
			before.get(&"session_ms", 0) / 1000.0,
			now.get(&"session_ms", 0) / 1000.0,
			delta[&"voice_relayed"],
			sent,
			sent / frames,
			delta[&"voice_dropped"],
			delta[&"voice_over_budget"],
			delta[&"voice_relay_usec"] / frames,
			per_send,
			send_alone,
			voice,
			snapshots,
			other,
			voice + snapshots + other,
			delta[&"voice_up_datagrams"],
		]
	)


## Every counter by name, headed by `label`.
static func totals(label: String, counters: Dictionary[StringName, int]) -> String:
	var names := counters.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var parts := PackedStringArray()
	for key: StringName in names:
		parts.append("%s %d" % [key, counters[key]])
	return "%s: %s" % [label, ", ".join(parts)]


static func _difference(
	before: Dictionary[StringName, int], now: Dictionary[StringName, int]
) -> Dictionary[StringName, int]:
	var found: Dictionary[StringName, int] = {}
	for key: StringName in now:
		found[key] = now[key] - before.get(key, 0)
	return found


## `prefix`_up_bytes and _datagrams as Mbit/s on the wire over `seconds`.
static func _mbit(
	delta: Dictionary[StringName, int], prefix: String, seconds: float, ip_udp_bytes: int
) -> float:
	var bytes: int = delta.get(StringName(prefix + "_up_bytes"), 0)
	var datagrams: int = delta.get(StringName(prefix + "_up_datagrams"), 0)
	return (bytes + ip_udp_bytes * datagrams) * BITS_PER_BYTE / seconds / MBIT
