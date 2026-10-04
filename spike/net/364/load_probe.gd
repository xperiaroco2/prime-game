extends SceneTree
## M6-1 spike (#364): does webrtc-native load headless? Prints the classes it registers.


func _init() -> void:
	var pc := WebRTCPeerConnection.new()
	var err := pc.initialize({})
	print("SPIKE load: initialize=%d state=%d" % [err, pc.get_connection_state()])
	var ch := pc.create_data_channel("probe", {"negotiated": true, "id": 1})
	print("SPIKE load: channel=%s" % [ch])
	for c: StringName in [&"WebRTCPeerConnectionExtension", &"WebRTCDataChannelExtension", &"WebRTCLibPeerConnection", &"WebRTCLibDataChannel"]:
		print("SPIKE load: class %s exists=%s" % [c, ClassDB.class_exists(c)])
	print("SPIKE load: pc class=%s ch class=%s" % [pc.get_class(), ch.get_class() if ch else "null"])
	pc.close()
	quit(0)
