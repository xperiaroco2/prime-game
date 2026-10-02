class_name CountingEnet
extends EnetTransport
## A hosting EnetTransport that also keeps every rejection in a RejectLedger, by peer, for the whole
## run (the chaos run's host over ENet). Nothing else changes.

var ledger := RejectLedger.new()


func _note_reject(peer_id: int, reason: NetRejects.Reason) -> void:
	ledger.count(peer_id, reason)
	super(peer_id, reason)
