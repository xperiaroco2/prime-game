extends RefCounted
## One WebRTCPeerConnection kept for a whole run, so the WebRTC library sets itself up once,
## before any timed wait (#472). It does so when a process makes its first connection, and again
## after the last one is gone, and a new connection's offer waits for it: under
## `tools\run.cmd load --loops 128` the first offer of a GdUnit process came after 9 to 11 s
## (about 30 ms on an idle PC), while later offers took under 10 ms as long as one connection
## stayed open and often 0.5 to 1 s when none did. A suite or a run whose waits time the
## transport makes one first, waits until is_ready() (or error is not OK: the library or the
## addon failed, so no offer will come), and closes it only at its end. Its offer is never sent
## anywhere.

## The first call that failed, or OK; set in _init(), so a caller can fail at once with its name.
var error := OK
var error_text := ""

var _pc := WebRTCPeerConnection.new()
var _made_offer := false


func _init() -> void:
	var err := _pc.initialize({"iceServers": []})
	if err != OK:
		_fail("initialize", err)
		return
	if _pc.create_data_channel("warm_up", {"negotiated": true, "id": 1}) == null:
		error = ERR_CANT_CREATE
		error_text = "create_data_channel gave null (is the webrtc_native addon loaded?)"
		return
	_pc.session_description_created.connect(_on_description)
	err = _pc.create_offer()
	if err != OK:
		_fail("create_offer", err)


## Polls the connection; true once its offer is made, so the library is set up.
func is_ready() -> bool:
	_pc.poll()
	return _made_offer


func close() -> void:
	_pc.close()


func _fail(call_name: String, err: Error) -> void:
	error = err
	error_text = "%s failed: %s" % [call_name, error_string(err)]


func _on_description(_type: String, _sdp: String) -> void:
	_made_offer = true
