class_name MeteredLoopback
extends LoopbackTransport
## The host's LoopbackTransport in a perf run (ARCHITECTURE §9.7, #187): every message it sends is
## also counted in a WireMeter. It sends exactly what LoopbackTransport sends.

var meter: WireMeter


func _init(kinds: NetKindTable, hub: LoopbackHub, wire_meter: WireMeter) -> void:
	super(kinds, hub)
	meter = wire_meter


func send(to_peer: int, kind: int, payload: PackedByteArray) -> Error:
	var result := super(to_peer, kind, payload)
	if result == OK:
		meter.sent(to_peer, kind, payload)
	return result
