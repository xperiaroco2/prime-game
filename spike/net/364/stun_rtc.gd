extends SceneTree
## M6-1 spike (#364), throwaway: does libdatachannel gather a server-reflexive (srflx) candidate
## through stun:stun.cloudflare.com:3478 from this machine? Prints every candidate for 12 s.

var pc: WebRTCPeerConnection
var t0: int = 0
var srflx: int = 0
var host: int = 0


func _init() -> void:
	pc = WebRTCPeerConnection.new()
	var err: Error = pc.initialize({"iceServers": [{"urls": ["stun:stun.cloudflare.com:3478"]}]})
	print("SPIKE stun: initialize=%d" % err)
	pc.ice_candidate_created.connect(_on_cand)
	pc.session_description_created.connect(
		func(t: String, s: String) -> void: pc.set_local_description(t, s)
	)
	pc.create_data_channel("probe", {"negotiated": true, "id": 1})
	pc.create_offer()
	t0 = Time.get_ticks_msec()


func _on_cand(_media: String, _index: int, cand: String) -> void:
	print("SPIKE stun: %d ms candidate %s" % [Time.get_ticks_msec() - t0, cand])
	if cand.contains("typ srflx"):
		srflx += 1
	elif cand.contains("typ host"):
		host += 1


func _process(_delta: float) -> bool:
	pc.poll()
	if Time.get_ticks_msec() - t0 > 12000:
		print("SPIKE stun: host=%d srflx=%d gathering=%d" % [host, srflx, pc.get_gathering_state()])
		pc.close()
		return true
	return false
