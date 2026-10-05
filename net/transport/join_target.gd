class_name JoinTarget
extends RefCounted
## What a player typed to join (the M6 design §2.3, E51): a room's code for WebRTC through the
## signalling service, or a host's `address[:port]` for ENet (Direct, LAN or VPN). Host names are
## allowed, so a playit.gg address works. Parsing lives here so game code has one join path: the
## game hands the target to transport() and calls join() on what comes back.
##
## parse() (the command line's --join=) reads 6 characters of SignalCodec's alphabet, in any case,
## as a code; anything else, or a name forced with a port ("server:24600"), is an address. The
## menu knows which field was typed in and calls of_code() or of_direct() instead.

enum Kind { CODE, DIRECT }

## The signalling service the game uses for codes: the engineer's Worker (tools/signal/README.md),
## empty until it is deployed. Empty, a code join fails as service_unreachable (use Direct).
const SERVICE_URL := ""

var kind := Kind.DIRECT
## The room's code, upper case (Kind.CODE).
var code := ""
## The host's address or name and its port (Kind.DIRECT).
var address := ""
var port := 0
## The signalling service's URL (Kind.CODE).
var service_url := SERVICE_URL
## What is wrong with the text, in words; empty when nothing is.
var problem := ""


## `text` from the command line: a code, or `address[:port]` with `default_port` when none is given.
static func parse(text: String, default_port: int, service := SERVICE_URL) -> JoinTarget:
	var squeezed := _squeezed(text)
	if SignalCodec.is_code(squeezed):
		return of_code(text, service)
	return of_direct(text, default_port)


## `text` typed under "Join with a code": spaces and dashes are dropped, the case does not matter.
static func of_code(text: String, service := SERVICE_URL) -> JoinTarget:
	var target := JoinTarget.new()
	target.kind = Kind.CODE
	target.code = _squeezed(text)
	target.service_url = service
	if target.code.is_empty():
		target.problem = "type the code the host gave you"
	elif not SignalCodec.is_code(target.code):
		target.problem = (
			"a code is %d characters of letters and digits, without 0, O, 1, I or L"
			% SignalCodec.CODE_LENGTH
		)
	return target


## `text` typed under "Direct (LAN or VPN)": an IPv4 or IPv6 address or a host name, with an
## optional ":port" (IPv6 with a port in brackets, "[::1]:24600"); `default_port` otherwise.
static func of_direct(text: String, default_port: int) -> JoinTarget:
	var target := JoinTarget.new()
	target.kind = Kind.DIRECT
	target.port = default_port
	var typed := text.strip_edges()
	var port_text := ""
	if typed.begins_with("["):
		var close := typed.find("]")
		if close < 0:
			target.problem = "an IPv6 address in brackets needs its closing ]"
			return target
		port_text = typed.substr(close + 1)
		typed = typed.substr(1, close - 1)
		if not port_text.is_empty() and not port_text.begins_with(":"):
			target.problem = "after ] comes :port"
			return target
		port_text = port_text.trim_prefix(":")
	elif typed.count(":") == 1:
		port_text = typed.get_slice(":", 1)
		typed = typed.get_slice(":", 0)
	target.address = typed
	if not port_text.is_empty():
		var number := port_text.to_int() if port_text.is_valid_int() else 0
		if number < 1 or number > 65535:
			target.problem = "the port is a number from 1 to 65535, not '%s'" % port_text
			return target
		target.port = number
	if typed.is_empty():
		target.problem = "type the host's address"
	elif not typed.is_valid_ip_address() and not _is_host_name(typed):
		target.problem = "'%s' is neither an address nor a host name" % typed
	return target


func is_code() -> bool:
	return kind == Kind.CODE


## What the player typed, as the connecting screen names it: the code, or address:port.
func label() -> String:
	if is_code():
		return code
	if address.contains(":"):
		return "[%s]:%d" % [address, port]
	return "%s:%d" % [address, port]


## The transport that joins this target, with `kinds`: a WebRtcTransport for a code, an
## EnetTransport for an address. Its join(join_address(), port) starts the join.
func transport(kinds: NetKindTable) -> NetTransport:
	if is_code():
		var webrtc := WebRtcTransport.new(kinds)
		webrtc.signal_url = service_url
		# A service on this machine (the runner's --signal=lan host, the tests): the host is here too,
		# so host candidates on 127.0.0.1 only, as in every headless test.
		webrtc.local_candidates = service_url.begins_with("ws://127.0.0.1:")
		return webrtc
	return EnetTransport.new(kinds)


## What the transport's join() takes as its address: the code, or the host's address.
func join_address() -> String:
	return code if is_code() else address


static func _squeezed(text: String) -> String:
	return text.strip_edges().replace(" ", "").replace("-", "").to_upper()


## Letters, digits, dots and dashes, as DNS names are; IP.resolve_hostname decides the rest.
static func _is_host_name(text: String) -> bool:
	if text.length() > 253 or text.begins_with(".") or text.begins_with("-"):
		return false
	for character: String in text:
		var at := character.unicode_at(0)
		var letter := (at >= 97 and at <= 122) or (at >= 65 and at <= 90)
		var digit := at >= 48 and at <= 57
		if not letter and not digit and character != "." and character != "-":
			return false
	return true
