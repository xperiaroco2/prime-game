class_name CountingLoopback
extends LoopbackTransport
## A hosting LoopbackTransport that also keeps every rejection in a RejectLedger, by peer, for the
## whole run (the chaos run's host). Nothing else changes: the rejection is counted in NetRejects
## and signalled exactly as on any transport.

var ledger := RejectLedger.new()


func _note_reject(peer_id: int, reason: NetRejects.Reason) -> void:
	ledger.count(peer_id, reason)
	super(peer_id, reason)
