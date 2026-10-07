class_name LoopbackTransport
extends NetTransport
## NetTransport inside one process. Two uses:
## - own_client_of(host): the listen server's own client, peer HOST_ID, on any hosting transport
##   (ENet or loopback), so the host's player sees exactly what a remote client would (ADR).
## - With a LoopbackHub: a host and clients in one process, for headless tests of the layers above.
## Packets are framed like on ENet, queued until the receiver polls, and decoded by receive_bytes.

var _hub: LoopbackHub
var _port := 0
var _max_clients := 0


func _init(kinds: NetKindTable, hub: LoopbackHub = null) -> void:
	super(kinds)
	_hub = hub


## The host's own client, linked to a hosting transport as peer HOST_ID; null when the transport
## is not hosting or already has one. Refusing new connections does not apply to it: it is the
## host's own player.
static func own_client_of(host_side: NetTransport) -> LoopbackTransport:
	if not host_side.is_host() or host_side._links.has(HOST_ID):
		return null
	var client := LoopbackTransport.new(host_side.kind_table())
	host_side._link(client, HOST_ID)
	return client


## A connected client's is in this process: LOCAL, with no round trip.
func own_route() -> Route:
	return Route.LOCAL if role() == Role.CLIENT and _peers.has(HOST_ID) else Route.NONE


func _backend_host(port: int, max_clients: int) -> Error:
	if _hub == null:
		return ERR_UNCONFIGURED
	var err := _hub.add_host(port, self)
	if err == OK:
		_port = port
		_max_clients = max_clients
	return err


## Like ENet, a join that cannot succeed still returns OK; connect_failed follows from poll().
func _backend_join(_address: String, port: int) -> Error:
	if _hub == null:
		return ERR_UNCONFIGURED
	var host_side := _hub.host_at(port) as LoopbackTransport
	if host_side == null or not host_side._accepts_client():
		_push(Inbound.new(Inbound.Type.CONNECT_FAILED, HOST_ID))
		return OK
	host_side._link(self, _hub.next_peer_id())
	return OK


func _backend_close() -> void:
	if _hub != null and is_host():
		_hub.remove_host(_port, self)


func _accepts_client() -> bool:
	var remote := _links.size() - (1 if _links.has(HOST_ID) else 0)
	return is_host() and not is_refusing_new_connections() and remote < _max_clients
