class_name MeteredEnet
extends EnetTransport
## The host's EnetTransport in a perf run over ENet (ARCHITECTURE §9.7, #187): every message it
## sends is also counted in a WireMeter. It sends exactly what EnetTransport sends.

var meter: WireMeter


func _init(kinds: NetKindTable, wire_meter: WireMeter) -> void:
	super(kinds)
	meter = wire_meter


func send(to_peer: int, kind: int, payload: PackedByteArray) -> Error:
	var result := super(to_peer, kind, payload)
	if result == OK:
		meter.sent(to_peer, kind, payload)
	return result
