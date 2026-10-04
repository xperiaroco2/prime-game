extends RefCounted
## One valid message of every type each side sends (ARCHITECTURE §4.8), for the codec's round
## trips and the decoder's fuzz test: [side, type, fields].

const CONTENT := "0123456789abcdef"
const SDP := "v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\n"
const CAND := "candidate:1 1 UDP 2122317823 127.0.0.1 50000 typ host"
const STUN := [{"urls": ["stun:stun.cloudflare.com:3478"]}]
const TURN := [{"urls": ["turn:turn.example:3478", "turns:turn.example:5349"], "username": "u"}]


static func all() -> Array[Array]:
	var unset := SignalCodec.Side.UNSET
	var host := SignalCodec.Side.HOST
	var joiner := SignalCodec.Side.JOINER
	var to_host := SignalCodec.Side.TO_HOST
	var to_joiner := SignalCodec.Side.TO_JOINER
	var candidate := {"mid": "0", "index": 0, "cand": CAND}
	return [
		[unset, "open", {"protocol": 7, "content": CONTENT, "max": 9}],
		[unset, "join", {"code": "ABCDEF"}],
		[host, "offer", {"to": 1, "id": 2, "sdp": SDP}],
		[host, "candidate", _with(candidate, {"to": 1})],
		[host, "close", {}],
		[host, "reopen", {}],
		[joiner, "answer", {"sdp": SDP}],
		[joiner, "candidate", candidate],
		[to_host, "room", {"code": "Z9Z9Z9", "ice_servers": STUN}],
		[to_host, "join", {"from": 3}],
		[to_host, "answer", {"from": 3, "sdp": SDP}],
		[to_host, "candidate", _with(candidate, {"from": 3})],
		[to_host, "error", {"why": SignalCodec.WHY_FULL}],
		[to_joiner, "found", {"protocol": 65535, "content": CONTENT}],
		[to_joiner, "offer", {"id": 2, "sdp": SDP, "ice_servers": TURN}],
		[to_joiner, "candidate", candidate],
		[to_joiner, "error", {"why": SignalCodec.WHY_VERSION}],
	]


static func _with(fields: Dictionary, more: Dictionary) -> Dictionary:
	var merged := fields.duplicate()
	merged.merge(more)
	return merged
