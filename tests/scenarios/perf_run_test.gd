extends GdUnitTestSuite
## The perf harness (tests/harness/perf/, ARCHITECTURE §9.7, #187) on a short match: PerfRun plays
## a PerfScenario to its end through HostSession over the loopback, WireMeter counts what the
## host's transport carried per remote peer and tick (never peer 1), and the simulated clock makes
## two runs carry the same bytes. `tools\run.cmd perf` plays the 10-bot match.


func test_a_short_match_ends_by_time_up_and_every_table_is_filled() -> void:
	var run := _play(3, 5)
	assert_array(Array(run.failures)).is_empty()
	assert_array(run.ends).contains_exactly([&"dissidents"])
	assert_bool(run.done()).is_true()
	assert_int(run.tick_usec.size()).is_greater(0)
	var data := run.to_dict()
	assert_str(str(data["transport"])).is_equal("loopback")
	var host_ticks: int = data["host_ticks"]
	assert_int(host_ticks).is_greater(Ticks.from_seconds(5))
	var events: Array = data["events_per_tick"]
	assert_int(events.size()).is_equal(host_ticks + 1)
	(
		assert_int(events.reduce(func(sum: int, count: int) -> int: return sum + count, 0))
		. is_greater(0)
	)
	for table: String in ["down", "snapshots", "up", "down_voice", "up_voice_frames"]:
		var peers: Dictionary = data[table]
		# The two remote bots; peer 1, the host's own client, uses no network.
		assert_array(peers.keys()).contains_exactly_in_any_order([2, 3])
	var budgets: Dictionary = data["budgets"]
	assert_int(budgets["snapshot_payload_cap"]).is_equal(1024)
	assert_int(budgets["frame_header_bytes"]).is_equal(NetFrame.HEADER_BYTES)


func test_two_runs_on_the_simulated_clock_carry_the_same_bytes() -> void:
	var first := _play(2, 5)
	var second := _play(2, 5)
	assert_array(Array(first.failures)).is_empty()
	assert_bool(first.meter.to_dict() == second.meter.to_dict()).is_true()
	assert_bool(first.to_dict()["events_per_tick"] == second.to_dict()["events_per_tick"]).is_true()


func test_the_meter_counts_frame_bytes_per_peer_and_tick_and_skips_the_own_client() -> void:
	var schema := WireSchema.game(true)
	var meter := WireMeter.new(schema)
	var payload := PackedByteArray()
	payload.resize(10)
	meter.tick = 7
	meter.sent(2, schema.kind_of(&"Snapshot"), payload)
	meter.sent(2, schema.kind_of(&"VoiceDown"), payload)
	meter.sent(NetTransport.HOST_ID, schema.kind_of(&"Snapshot"), payload)
	meter.received(3, schema.kind_of(&"VoiceUp"), payload)
	meter.received(3, schema.kind_of(&"SetReady"), payload)
	meter.received(NetTransport.HOST_ID, schema.kind_of(&"SetReady"), payload)
	assert_dict(meter.down).is_equal({2: {7: 2 * (10 + NetFrame.HEADER_BYTES)}})
	assert_dict(meter.down_voice).is_equal({2: {7: 10 + NetFrame.HEADER_BYTES}})
	assert_dict(meter.snapshots).is_equal({2: {7: 10}})
	assert_dict(meter.up).is_equal({3: {7: 10}})
	assert_dict(meter.up_voice).is_equal({3: {7: 1}})


func test_the_metered_transport_counts_only_what_it_sent() -> void:
	var schema := WireSchema.game(true)
	var meter := WireMeter.new(schema)
	var hub := LoopbackHub.new()
	var host := MeteredLoopback.new(schema.kind_table(), hub, meter)
	assert_int(host.host(7401, 4)).is_equal(OK)
	var client := LoopbackTransport.new(schema.kind_table(), hub)
	assert_int(client.join("loopback", 7401)).is_equal(OK)
	host.poll()
	client.poll()
	var payload := PackedByteArray([1, 2, 3])
	# Not a connected peer: not sent, not counted.
	assert_int(host.send(9, schema.kind_of(&"Snapshot"), payload)).is_not_equal(OK)
	assert_dict(meter.down).is_empty()
	var peer := client.own_id()
	assert_int(host.send(peer, schema.kind_of(&"Snapshot"), payload)).is_equal(OK)
	assert_dict(meter.down).is_equal({peer: {0: 3 + NetFrame.HEADER_BYTES}})
	client.close()
	host.close()


func _play(bots: int, seconds: int) -> PerfRun:
	var run := PerfRun.new(PerfScenario.build(bots, seconds, 0))
	assert_bool(run.start()).is_true()
	while not run.done():
		run.frame()
	run.finish()
	return run
