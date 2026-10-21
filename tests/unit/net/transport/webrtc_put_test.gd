extends GdUnitTestSuite
## What a failed write to a WebRTC channel returns (#1232): on a connection that opened, a
## channel no longer OPEN is a peer on its way out (ERR_DOES_NOT_EXIST, which HostSession._send
## drops quietly), whatever state it reads, before the send or after put_packet() failed; never
## an error the host reports as an engine error (the bots-webrtc lanes fail on one).

const OPEN := WebRTCDataChannel.STATE_OPEN
const STATES: Array[WebRTCDataChannel.ChannelState] = [
	WebRTCDataChannel.STATE_CONNECTING,
	WebRTCDataChannel.STATE_CLOSING,
	WebRTCDataChannel.STATE_CLOSED,
]


func test_a_channel_not_open_on_an_opened_connection_is_a_peer_on_its_way_out() -> void:
	for state: WebRTCDataChannel.ChannelState in STATES:
		for err: Error in [ERR_CONNECTION_ERROR, FAILED, ERR_UNAVAILABLE]:
			(
				assert_int(WebRtcTransport.failed_put(true, state, err))
				. override_failure_message("state %d, err %d" % [state, err])
				. is_equal(ERR_DOES_NOT_EXIST)
			)


func test_a_put_packet_failure_on_an_open_channel_stands() -> void:
	for opened: bool in [true, false]:
		assert_int(WebRtcTransport.failed_put(opened, OPEN, FAILED)).is_equal(FAILED)
		assert_int(WebRtcTransport.failed_put(opened, OPEN, ERR_BUSY)).is_equal(ERR_BUSY)


func test_before_the_connection_opened_only_a_closing_channel_is_a_peer_going() -> void:
	var connecting := WebRTCDataChannel.STATE_CONNECTING
	assert_int(WebRtcTransport.failed_put(false, connecting, ERR_CONNECTION_ERROR)).is_equal(
		ERR_CONNECTION_ERROR
	)
	assert_int(WebRtcTransport.failed_put(false, connecting, FAILED)).is_equal(FAILED)
	for state: WebRTCDataChannel.ChannelState in STATES.slice(1):
		assert_int(WebRtcTransport.failed_put(false, state, ERR_CONNECTION_ERROR)).is_equal(
			ERR_DOES_NOT_EXIST
		)
		assert_int(WebRtcTransport.failed_put(false, state, FAILED)).is_equal(ERR_DOES_NOT_EXIST)
