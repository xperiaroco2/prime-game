extends RefCounted
## One WebRTCPeerConnection kept for a whole run, so the WebRTC library sets itself up once,
## before any timed wait (#472). It does so when a process makes its first connection, and again
## after the last one is gone, and a new connection's offer waits for it: under
## `tools\run.cmd load --loops 128` the first offer of a GdUnit process came after 9 to 11 s
## (about 30 ms on an idle PC), while later offers took under 10 ms as long as one connection
## stayed open and often 0.5 to 1 s when none did. A suite or a run whose waits time the
## transport makes one first, waits until is_ready(), and closes it only at its end. Its offer
## is never sent anywhere.

var _pc := WebRTCPeerConnection.new()
var _ready := false


func _init() -> void:
	_pc.initialize({"iceServers": []})
	_pc.create_data_channel("warm_up", {"negotiated": true, "id": 1})
	_pc.session_description_created.connect(_on_description)
	_pc.create_offer()


## Polls the connection; true once its offer is made, so the library is set up.
func is_ready() -> bool:
	_pc.poll()
	return _ready


func close() -> void:
	_pc.close()


func _on_description(_type: String, _sdp: String) -> void:
	_ready = true
