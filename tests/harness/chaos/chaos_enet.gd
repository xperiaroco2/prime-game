class_name ChaosEnet
extends EnetTransport
## A chaos peer's client transport over ENet: raw bytes on any channel and transfer mode
## (send_raw), besides what its ClientSession sends; ChaosLoopback's twin, with the same `outbox`.

var outbox: Array[ChaosFrames.Packet] = []


func send(to_peer: int, kind: int, payload: PackedByteArray) -> Error:
	var sent := super(to_peer, kind, payload)
	if sent == OK:
		var packet := ChaosFrames.framed(kind, payload, _kinds.lane_of(kind))
		packet.label = "honest"
		outbox.append(packet)
	return sent


## Puts `packet`'s bytes on the wire to the host as they are; false when not connected.
func send_raw(packet: ChaosFrames.Packet) -> bool:
	if _peer == null or not _live.has(HOST_ID) or not _peers.has(HOST_ID):
		return false
	_peer.transfer_channel = packet.channel
	_peer.transfer_mode = packet.mode
	_peer.set_target_peer(HOST_ID)
	if _peer.put_packet(packet.bytes) != OK:
		return false
	outbox.append(packet)
	return true


## The packets sent since the last call, in order.
func take_outbox() -> Array[ChaosFrames.Packet]:
	var taken := outbox
	outbox = []
	return taken
