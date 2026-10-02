class_name ChaosLoopback
extends LoopbackTransport
## A chaos peer's client transport on the loopback: it sends what a modified client can send,
## raw bytes on any channel and transfer mode (send_raw), besides the messages its ClientSession
## sends through send(). Every packet either way goes into `outbox`, in order, so the chaos run
## knows what the host will poll next (ChaosBudget). The host decodes each one through the one
## decode path, as any packet (NetTransport.receive_bytes).

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
	var host_side := _link_host.get_ref() as NetTransport if _link_host != null else null
	if host_side == null or not _peers.has(HOST_ID):
		return false
	host_side._push(
		Inbound.new(Inbound.Type.PACKET, _own_id, packet.bytes, packet.channel, packet.mode)
	)
	outbox.append(packet)
	return true


## The packets sent since the last call, in order.
func take_outbox() -> Array[ChaosFrames.Packet]:
	var taken := outbox
	outbox = []
	return taken
