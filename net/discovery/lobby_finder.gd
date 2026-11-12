class_name LobbyFinder
extends RefCounted
## Finds the lobbies nearby (#1316; ARCHITECTURE §4.9): while it runs, a LobbyBeacon query every
## QUERY_MS from its own IPv4 UDP socket (any free port) to the broadcast address and to this
## machine, both on the discovery port; each host's answer comes back to that socket. A lobby is
## one host (its number) at the address its first answer came from: a later answer naming that
## host from another address is not taken (a forged one cannot steer its Join), nor a new host past
## MOST_LOBBIES (a flood cannot grow the list). Each is kept with the round trip of its latest
## answer in whole ms (frame-bound: both ends read once a frame) and when it was last heard; one
## unheard for FORGET_MS is gone (s05: "a lobby that goes away leaves its row"). An answer of
## another protocol (another build) is not listed. Refused datagrams are counted (`rejected`).
## The owner calls poll() every frame; nothing here blocks.

## How often a query goes out, and how long an unheard lobby stays (provisional, not a decision).
const QUERY_MS := 1000
const FORGET_MS := 3500
## The most datagrams one poll reads (a flood waits for the next poll), and the most lobbies kept.
const READS_PER_POLL := 64
const MOST_LOBBIES := 16
## The queries remembered for timing their answers.
const QUERIES_KEPT := 8


## One lobby found.
class Found:
	extends RefCounted
	var answer: LobbyBeacon.Answer
	## The address its answer came from (a direct join's), and the round trip in whole ms.
	var address := ""
	var ping_ms := 0
	var heard_ms := 0


## Where queries go (tests point them at 127.0.0.1 alone, or another port).
var targets: PackedStringArray = ["255.255.255.255", "127.0.0.1"]
var port := LobbyBeacon.PORT
## The protocol a lobby must speak to be listed (WireSchema.VERSION).
var protocol := WireSchema.VERSION
## The clock in ms (Time's unless replaced; tests step it).
var now_ms := func() -> int: return Time.get_ticks_msec()
## Datagrams refused: not an answer, another protocol, no query of ours, a host's other address,
## a host past MOST_LOBBIES.
var rejected := 0

var _socket := PacketPeerUDP.new()
var _running := false
var _next := 1
var _sent_at_ms := 0
## Query number -> when it went out.
var _queries: Dictionary[int, int] = {}
## Host number -> what was found of it, in the order first found.
var _found: Dictionary[int, Found] = {}


## Starts asking (true), or false when no socket could be had. IPv4 only: the broadcast goes out
## of an IPv4 socket, never a dual-stack one.
func start() -> bool:
	if _running:
		return true
	if _socket.bind(0, "0.0.0.0") != OK:
		return false
	_socket.set_broadcast_enabled(true)
	_running = true
	_ask(now_ms.call() as int)
	return true


func stop() -> void:
	if _running:
		_socket.close()
	_running = false
	_queries.clear()
	_found.clear()


func running() -> bool:
	return _running


## Sends the query when due, reads the answers and forgets the lobbies gone quiet.
func poll() -> void:
	if not _running:
		return
	var now: int = now_ms.call()
	if now - _sent_at_ms >= QUERY_MS:
		_ask(now)
	for i: int in READS_PER_POLL:
		if _socket.get_available_packet_count() == 0:
			break
		var bytes := _socket.get_packet()
		_take(LobbyBeacon.read_answer(bytes), _socket.get_packet_ip(), now)
	for host: int in _found.keys():
		if now - _found[host].heard_ms > FORGET_MS:
			_found.erase(host)


## The lobbies found, in the order first found.
func lobbies() -> Array[Found]:
	var list: Array[Found] = []
	list.assign(_found.values())
	return list


func _ask(now: int) -> void:
	_sent_at_ms = now
	var number := _next
	_next = _next % 0x7FFF_FFFF + 1
	_queries[number] = now
	while _queries.size() > QUERIES_KEPT:
		_queries.erase(_queries.keys()[0])
	var bytes := LobbyBeacon.query(number)
	for target: String in targets:
		_socket.set_dest_address(target, port)
		_socket.put_packet(bytes)


func _take(answer: LobbyBeacon.Answer, address: String, now: int) -> void:
	if answer == null or answer.protocol != protocol or not _queries.has(answer.query):
		rejected += 1
		return
	var found: Found = _found.get(answer.host)
	if found == null:
		if _found.size() >= MOST_LOBBIES:
			rejected += 1
			return
		found = Found.new()
		found.address = address
		_found[answer.host] = found
	elif found.address != address:
		# One host heard on two addresses (the broadcast and this machine) is one lobby at the
		# first: the row's Join never jumps, and no other address can take its place.
		return
	found.answer = answer
	found.ping_ms = now - _queries[answer.query]
	found.heard_ms = now
