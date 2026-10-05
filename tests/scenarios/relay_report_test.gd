extends GdUnitTestSuite
## RelayReport (tests/harness/bots/, M5-4): a window of the host's relay counters in the M5 ADR's
## §4 words (frames and batches per 20 ms, relay microseconds per 20 ms and per send, the upload
## in Mbit/s on the wire with IP and UDP added per datagram), and every total by name.


func test_a_window_gives_sends_per_20_ms_time_per_send_and_the_upload_on_the_wire() -> void:
	var before := _counters(1000)
	var now := _counters(6000)
	# 5 s are 250 frames of 20 ms; 49 streams of continuous talk send 49 frames in each, in 8
	# VoiceBatches (one per listener but the host's own client, which counts as a send too).
	now[&"voice_relayed"] = 2000
	now[&"voice_sent"] = 12250
	now[&"voice_batches"] = 2000
	now[&"voice_relay_usec"] = 250000
	now[&"voice_send_usec"] = 200000
	now[&"voice_up_bytes"] = 12250 * 68
	now[&"voice_up_datagrams"] = 12250
	now[&"snapshot_up_bytes"] = 1000 * 172
	now[&"snapshot_up_datagrams"] = 1000
	var line := RelayReport.window("BOTS x host relay", before, now)
	assert_str(line).starts_with("BOTS x host relay 1.0-6.0 s: relayed 2000,")
	assert_str(line).contains("sent 12250 (49.0 per 20 ms) in 2000 batches (8.0 per 20 ms)")
	assert_str(line).contains("relay 1000 us per 20 ms (125.0 us per send, 100.0 in the send)")
	# (68 + 28) B x 12250 x 8 / 5 s = 1.882 Mbit/s; (172 + 28) B x 1000 x 8 / 5 s = 0.320.
	assert_str(line).contains(
		"upload voice 1.882, snapshots 0.320, other 0.000, total 2.202 Mbit/s"
	)
	assert_str(line).contains("(12250 voice datagrams)")
	# Over WebRTC take_upload already counts IP and UDP (E56): 68 B x 12250 x 8 / 5 s = 1.333.
	var webrtc := RelayReport.window("BOTS x host relay", before, now, 0)
	assert_str(webrtc).contains("upload voice 1.333, snapshots 0.275, other 0.000, total 1.608")


func test_a_window_without_time_is_empty_and_without_sends_has_no_time_per_send() -> void:
	assert_str(RelayReport.window("x", _counters(10), _counters(10))).is_empty()
	var line := RelayReport.window("x", _counters(0), _counters(1000))
	assert_str(line).contains("sent 0 (0.0 per 20 ms) in 0 batches (0.0 per 20 ms)")
	assert_str(line).contains("(- us per send, - in the send)")


func test_the_totals_list_every_counter_by_name() -> void:
	var counters: Dictionary[StringName, int] = {&"voice_sent": 3, &"session_ms": 9}
	assert_str(RelayReport.totals("T", counters)).is_equal("T: session_ms 9, voice_sent 3")


func _counters(session_ms: int) -> Dictionary[StringName, int]:
	var found: Dictionary[StringName, int] = {&"session_ms": session_ms}
	for key: StringName in [
		&"voice_relayed",
		&"voice_sent",
		&"voice_batches",
		&"voice_dropped",
		&"voice_over_budget",
		&"voice_relay_usec",
		&"voice_send_usec",
		&"voice_up_bytes",
		&"voice_up_datagrams",
		&"snapshots_sent",
		&"snapshot_up_bytes",
		&"snapshot_up_datagrams",
		&"other_up_bytes",
		&"other_up_datagrams",
	]:
		found[key] = 0
	return found
