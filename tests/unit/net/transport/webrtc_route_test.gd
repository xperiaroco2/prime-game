extends GdUnitTestSuite
## The kind of a WebRTC client's own connection (the M6 design §3 item 4, #431). webrtc-native
## reports no selected candidate pair (webrtc_native_addon_test), so the kind follows from the ICE
## servers the joiner was given: without a TURN server no relay candidate exists and the
## connection is direct (host or server-reflexive); with one it may be either.


func test_no_ice_servers_or_stun_alone_is_direct() -> void:
	assert_int(WebRtcTransport.route_of([])).is_equal(NetTransport.Route.DIRECT)
	var stun: Array = [{"urls": ["stun:stun.cloudflare.com:3478"]}]
	assert_int(WebRtcTransport.route_of(stun)).is_equal(NetTransport.Route.DIRECT)


func test_a_turn_server_may_relay() -> void:
	for url: String in ["turn:turn.example.net:3478", "TURNS:turn.example.net:5349"]:
		var servers: Array = [
			{"urls": ["stun:stun.cloudflare.com:3478"]},
			{"urls": [url], "username": "u", "credential": "c"},
		]
		assert_int(WebRtcTransport.route_of(servers)).override_failure_message(url).is_equal(
			NetTransport.Route.DIRECT_OR_RELAYED
		)


func test_urls_as_one_string_count_too() -> void:
	var servers: Array = [{"urls": "turn:turn.example.net:3478"}]
	assert_int(WebRtcTransport.route_of(servers)).is_equal(NetTransport.Route.DIRECT_OR_RELAYED)


func test_entries_that_are_not_servers_are_ignored() -> void:
	var servers: Array = [7, "turn:x", {"urls": [3]}, {"other": ["turn:x"]}]
	assert_int(WebRtcTransport.route_of(servers)).is_equal(NetTransport.Route.DIRECT)
