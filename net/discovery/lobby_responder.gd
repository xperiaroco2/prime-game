class_name LobbyResponder
extends RefCounted
## A lobby's host answers the finders nearby (#1316; ARCHITECTURE §4.9): bound to the discovery
## port (IPv4), it reads LobbyBeacon queries and sends each asker the answer `describe` gives now
## (null stays silent: a match running, no lobby to join). It answers only this machine and the
## local network's private addresses (is_nearby: never a public one, so a scan from the internet
## learns no room code), at most one answer per asker every ANSWER_GAP_MS. Whether a second host on
## one machine can bind the port too is the system's; start() is false when it cannot. Refused
## datagrams are counted (`rejected`). The owner calls poll() every frame.

## The most datagrams one poll reads (a flood waits for the next poll).
const READS_PER_POLL := 32
## The least time between two answers to one asker (its queries come every second).
const ANSWER_GAP_MS := 250

var port := LobbyBeacon.PORT
## The IPv4 address it listens on ("0.0.0.0": every one; tests use 127.0.0.1).
var bind_address := "0.0.0.0"
## The host's number in every answer, drawn anew at each start(): a finder hearing it twice (the
## broadcast and this machine) lists one lobby.
var host_number := 0
## The clock in ms (Time's unless replaced; tests step it).
var now_ms := func() -> int: return Time.get_ticks_msec()
## Datagrams refused: no query, an asker not nearby, an asker answered too lately.
var rejected := 0

var _socket := PacketPeerUDP.new()
var _running := false
var _random := RandomNumberGenerator.new()
## Asker "address:port" -> when it was last answered.
var _answered: Dictionary[String, int] = {}


func _init() -> void:
	_random.randomize()


## Listens (true), or false when the port is taken or cannot be bound.
func start() -> bool:
	if _running:
		return true
	_running = _socket.bind(port, bind_address) == OK
	if _running:
		host_number = _random.randi_range(1, 0x7FFF_FFFF)
	return _running


func stop() -> void:
	if _running:
		_socket.close()
	_running = false
	_answered.clear()


func running() -> bool:
	return _running


## Answers the queries waiting: `describe` () -> LobbyBeacon.Answer (null: answer nobody now).
func poll(describe: Callable) -> void:
	if not _running:
		return
	var now: int = now_ms.call()
	for asker: String in _answered.keys():
		if now - _answered[asker] >= ANSWER_GAP_MS:
			_answered.erase(asker)
	for i: int in READS_PER_POLL:
		if _socket.get_available_packet_count() == 0:
			return
		var number := LobbyBeacon.query_number(_socket.get_packet())
		var address := _socket.get_packet_ip()
		var asker := "%s:%d" % [address, _socket.get_packet_port()]
		if number < 0 or not is_nearby(address) or _answered.has(asker):
			rejected += 1
			continue
		var answer := describe.call() as LobbyBeacon.Answer
		if answer == null:
			continue
		answer.query = number
		answer.host = host_number
		var bytes := LobbyBeacon.answer(answer)
		if bytes.is_empty():
			continue
		_answered[asker] = now
		_socket.set_dest_address(address, _socket.get_packet_port())
		_socket.put_packet(bytes)


## Whether an IPv4 `address` is nearby: this machine (127/8), a private network (10/8,
## 172.16/12, 192.168/16) or a link-local one (169.254/16).
static func is_nearby(address: String) -> bool:
	if not address.is_valid_ip_address() or address.contains(":"):
		return false
	var parts := address.split(".")
	var first := int(parts[0])
	var second := int(parts[1])
	return (
		first == 127
		or first == 10
		or (first == 172 and second >= 16 and second <= 31)
		or (first == 192 and second == 168)
		or (first == 169 and second == 254)
	)
