class_name LoopbackHub
extends RefCounted
## The in-process "network" LoopbackTransports host and join on: hosts by port, and peer ids for
## joining clients. Ids count up from 2 (1 is the host), so tests are deterministic.

## Weak, so a host that nobody holds any more is gone from the hub too.
var _hosts: Dictionary[int, WeakRef] = {}
var _next_peer_id := NetTransport.HOST_ID + 1


## The host on this port, or null.
func host_at(port: int) -> NetTransport:
	var ref: WeakRef = _hosts.get(port)
	return ref.get_ref() as NetTransport if ref != null else null


func add_host(port: int, host: NetTransport) -> Error:
	if host_at(port) != null:
		return ERR_ALREADY_IN_USE
	_hosts[port] = weakref(host)
	return OK


func remove_host(port: int, host: NetTransport) -> void:
	if host_at(port) == host:
		_hosts.erase(port)


func next_peer_id() -> int:
	_next_peer_id += 1
	return _next_peer_id - 1
