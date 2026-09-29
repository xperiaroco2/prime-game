class_name SpikeTransport
extends RefCounted
## Spike (#13): the thin transport interface. Game code talks to this and never to ENet, so the
## transport can be swapped (Steam, WebRTC) later. Peers are ids; HOST_ID is the host. Packets are
## opaque bytes: schemas live in SpikeNetMessages, not here. The owner calls poll() every frame.

@warning_ignore_start("unused_signal")  # emitted by the implementations
signal connected(own_id: int)
signal connect_failed
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal disconnected
signal packet_received(from_peer: int, bytes: PackedByteArray)
@warning_ignore_restore("unused_signal")

const HOST_ID := 1
const EVERYONE := 0


func host(_bind_ip: String, _port: int, _max_clients: int) -> Error:
	return _missing("host")


func join(_address: String, _port: int) -> Error:
	return _missing("join")


func poll() -> void:
	_missing("poll")


## Sends to one peer, or to every connected peer with EVERYONE. Unreliable packets are ordered.
func send(_to_peer: int, _bytes: PackedByteArray, _reliable: bool) -> Error:
	return _missing("send")


func own_id() -> int:
	_missing("own_id")
	return 0


func close() -> void:
	_missing("close")


func _missing(method: String) -> Error:
	push_error("SpikeTransport.%s is not implemented" % method)
	return ERR_UNAVAILABLE
