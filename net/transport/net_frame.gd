class_name NetFrame
extends RefCounted
## One message on the wire: [kind: u8][payload size: u16, little-endian][payload]. A 3-byte
## header instead of var_to_bytes framing, which is as large as an Opus frame (ARCHITECTURE §4).
## The payload is opaque here: the message schemas decode it, never into objects.
##
## decode() trusts nothing: the size cap, a known kind, its direction and lane, its payload cap,
## and a declared size that matches the packet exactly, so trailing bytes are rejected too.

const HEADER_BYTES := 3
const MAX_PACKET_BYTES := HEADER_BYTES + NetKindTable.MAX_PAYLOAD

var kind := 0
var payload := PackedByteArray()
## NONE when the packet is a valid message.
var reject := NetRejects.Reason.NONE


## The packet for a kind and payload. The caller checks both against the table first.
static func encode(message_kind: int, message_payload: PackedByteArray) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(HEADER_BYTES)
	bytes.encode_u8(0, message_kind)
	bytes.encode_u16(1, message_payload.size())
	bytes.append_array(message_payload)
	return bytes


## The message in a received packet, or a frame whose reject names why the packet is not one.
## from_host: the packet came from the host (this peer is a client). channel and mode: where the
## packet arrived, as the MultiplayerPeer reports them.
static func decode(
	bytes: PackedByteArray,
	kinds: NetKindTable,
	from_host: bool,
	channel: int,
	mode: MultiplayerPeer.TransferMode,
) -> NetFrame:
	var frame := NetFrame.new()
	var size := bytes.size()
	if size < HEADER_BYTES:
		return frame._rejected(NetRejects.Reason.TOO_SHORT)
	if size > MAX_PACKET_BYTES:
		return frame._rejected(NetRejects.Reason.TOO_LARGE)
	var message_kind := bytes.decode_u8(0)
	if not kinds.has(message_kind):
		return frame._rejected(NetRejects.Reason.UNKNOWN_KIND)
	if not kinds.allows(message_kind, from_host):
		return frame._rejected(NetRejects.Reason.WRONG_DIRECTION)
	var lane := kinds.lane_of(message_kind)
	if channel != NetKindTable.channel_of(lane) or mode != NetKindTable.mode_of(lane):
		return frame._rejected(NetRejects.Reason.WRONG_LANE)
	var declared := bytes.decode_u16(1)
	if declared > kinds.payload_cap(message_kind):
		return frame._rejected(NetRejects.Reason.PAYLOAD_TOO_LARGE)
	if declared > size - HEADER_BYTES:
		return frame._rejected(NetRejects.Reason.TRUNCATED)
	if declared < size - HEADER_BYTES:
		return frame._rejected(NetRejects.Reason.TRAILING_BYTES)
	frame.kind = message_kind
	frame.payload = bytes.slice(HEADER_BYTES)
	return frame


func _rejected(reason: NetRejects.Reason) -> NetFrame:
	reject = reason
	return self
