class_name BotWebRtc
extends WebRtcTransport
## The harness's WebRtcTransport (M6-6; ARCHITECTURE §4.6): the bots, the leak test and the chaos
## bots over WebRTC on 127.0.0.1, with LanSignalling and host candidates only (no STUN in tests).
## Besides the transport it:
## - records every RELIABLE and LATEST message it sent and delivered, per peer (`order`, OrderLog:
##   the leak test's order check);
## - keeps every rejection in a RejectLedger, by peer, for the whole run (the chaos run's host, as
##   CountingEnet);
## - sends raw bytes on any lane as a modified client can (send_raw, the chaos peers, as ChaosEnet),
##   keeping what it sent in `outbox` when keep_outbox is on.
## The fault shim (the M6 design §5) is on by default: RELIABLE SHIM_RELIABLE_DELAY_MS late, LATEST
## dropped, duplicated and late, seeded per transport.

## The room every harness host opens: LanSignalling hands out only this code (`signalling`).
const CODE := "BTSRTC"
const ADDRESS := "127.0.0.1"
## The fault shim of the runs (the M6 design §5): the freeze twin's rates, and LATEST late by up to
## SHIM_LATEST_DELAY_MS, more than RELIABLE, so a LATEST message sent just before a reliable one can
## arrive after it, the case LaneOrder's "behind" rule exists for.
const SHIM_RELIABLE_DELAY_MS := 50
const SHIM_LATEST_DROP := 0.1
const SHIM_LATEST_DUPLICATE := 0.1
const SHIM_LATEST_DELAY_MS := 100
## How long a harness host waits for its room at the start.
const ROOM_WAIT_MS := 5000

var order := OrderLog.new()
var ledger := RejectLedger.new()
var keep_outbox := false
var outbox: Array[ChaosFrames.Packet] = []


## A transport for the signalling on `port` of 127.0.0.1, with the fault shim seeded with
## `shim_seed` (0: no shim).
func _init(kinds: NetKindTable, port: int, shim_seed: int) -> void:
	super(kinds)
	signal_url = "ws://%s:%d" % [ADDRESS, port]
	local_candidates = true
	packet_received.connect(_on_delivered)
	if shim_seed != 0:
		var shim := FaultShim.new(shim_seed)
		shim.reliable_delay_ms = SHIM_RELIABLE_DELAY_MS
		shim.latest_drop = SHIM_LATEST_DROP
		shim.latest_duplicate = SHIM_LATEST_DUPLICATE
		shim.latest_delay_ms = SHIM_LATEST_DELAY_MS
		use_faults(shim)


## The service a harness host runs on 127.0.0.1: every room it opens is CODE.
static func signalling() -> LanSignalling:
	return LanSignalling.new([], func() -> String: return CODE)


## Polls `service` and `host` (hosting, no peer yet) until the service opened the room, at most
## ROOM_WAIT_MS; false when it did not.
static func wait_for_room(service: LanSignalling, host_transport: WebRtcTransport) -> bool:
	var until := Time.get_ticks_msec() + ROOM_WAIT_MS
	while host_transport.room_code().is_empty() and Time.get_ticks_msec() < until:
		service.poll()
		host_transport.poll()
		OS.delay_msec(2)
	return not host_transport.room_code().is_empty()


func send(to_peer: int, kind: int, payload: PackedByteArray) -> Error:
	var sent := super(to_peer, kind, payload)
	if sent != OK:
		return sent
	var lane := _kinds.lane_of(kind)
	if lane != NetKindTable.Lane.VOICE and _conns.has(to_peer if is_host() else HOST_ID):
		order.record_sent(to_peer, kind, payload, lane == NetKindTable.Lane.RELIABLE)
	if keep_outbox:
		var packet := ChaosFrames.framed(kind, payload, lane)
		packet.label = "honest"
		outbox.append(packet)
	return sent


## Puts `packet`'s bytes on the host's channel for its lane as they are (a LATEST packet still gets
## LaneOrder's header, as any sender's would); false when not connected.
func send_raw(packet: ChaosFrames.Packet) -> bool:
	var conn: Conn = _conns.get(HOST_ID)
	if is_host() or conn == null or not _is_live(conn):
		return false
	if _put(conn, _lane_of(packet), packet.bytes) != OK:
		return false
	if keep_outbox:
		outbox.append(packet)
	return true


## The packets sent since the last call, in order.
func take_outbox() -> Array[ChaosFrames.Packet]:
	var taken := outbox
	outbox = []
	return taken


func _note_reject(peer_id: int, reason: NetRejects.Reason) -> void:
	ledger.count(peer_id, reason)
	super(peer_id, reason)


func _on_delivered(from_peer: int, kind: int, payload: PackedByteArray) -> void:
	if _kinds.lane_of(kind) != NetKindTable.Lane.VOICE:
		order.record_delivered(from_peer, kind, payload)


## The lane whose channel and transfer mode ENet would use for `packet` (ChaosFrames builds them).
static func _lane_of(packet: ChaosFrames.Packet) -> NetKindTable.Lane:
	for lane: NetKindTable.Lane in CHANNEL_IDS:
		if (
			NetKindTable.channel_of(lane) == packet.channel
			and NetKindTable.mode_of(lane) == packet.mode
		):
			return lane
	return NetKindTable.Lane.RELIABLE
