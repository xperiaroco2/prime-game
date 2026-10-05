extends GdUnitTestSuite
## The host's debug counters of the voice relay and the upload (ARCHITECTURE §4.5 "The host's
## counters"; the M5 ADR's E47 as amended, M5-4): HostSession.relay_counters() counts the frames
## relayed, the frames sent and the VoiceBatches carrying them, the backlog dropped and the voice
## frames over budget, the relay's time, and what went out during the voice sends, the snapshot
## sends and otherwise, apart. Over the loopback the upload is the frames sent to remote peers; the
## host's own client never counts.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_frames_relayed_batches_sent_and_their_upload_without_the_own_client() -> void:
	# Lobby markers 2 m apart, heard within 3 m: 1 and 2 hear each other, 2 and 3 too, 1 and 3 not.
	_h = Harness.new()
	var second := _h.join()
	var third := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(3)
	var before := _h.session.relay_counters()
	assert_int(before[&"voice_relayed"]).is_equal(0)
	assert_int(before[&"voice_sent"]).is_equal(0)
	assert_int(before[&"voice_up_datagrams"]).is_equal(0)
	_h.own.send_voice(PackedByteArray([1, 1]))
	second.send_voice(PackedByteArray([2, 2, 2]))
	third.send_voice(PackedByteArray([3]))
	_h.pump()
	var after := _h.session.relay_counters()
	assert_int(after[&"voice_relayed"]).is_equal(3)
	# 1 -> 2; 2 -> 1 and 3; 3 -> 2: four frames in three VoiceBatches, one per listener (M5-4b).
	assert_int(after[&"voice_sent"]).is_equal(4)
	assert_int(after[&"voice_batches"]).is_equal(3)
	# A VoiceBatch: NetFrame's header, tick 4, count 1, then per frame speaker 4, seq 2, length 2
	# and the bytes. The one to the host's own client (2's frame to 1) never reaches a network.
	var batch := NetFrame.HEADER_BYTES + 5
	assert_int(after[&"voice_up_datagrams"]).is_equal(2)
	assert_int(after[&"voice_up_bytes"]).is_equal((batch + 8 + 2 + 8 + 1) + (batch + 8 + 3))
	assert_int(after[&"voice_relay_usec"]).is_greater_equal(after[&"voice_send_usec"])
	assert_int(after[&"voice_dropped"]).is_equal(0)
	assert_int(after[&"voice_over_budget"]).is_equal(0)
	assert_int(after[&"session_ms"]).is_greater(0)


func test_snapshots_and_the_rest_of_the_upload_are_counted_apart() -> void:
	_h = Harness.new()
	_h.join()
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(1.0)
	var counted := _h.session.relay_counters()
	# Every present player gets one per tick in the lobby; the own client's never reaches a network.
	var snapshots: int = counted[&"snapshots_sent"]
	assert_int(snapshots).is_greater(Ticks.RATE / 2)
	assert_int(counted[&"snapshot_up_datagrams"]).is_greater(0)
	assert_int(counted[&"snapshot_up_datagrams"]).is_less(snapshots)
	assert_int(counted[&"snapshot_up_bytes"]).is_greater(counted[&"snapshot_up_datagrams"])
	# The Welcomes and the other events to the two remote players.
	assert_int(counted[&"other_up_datagrams"]).is_greater(0)
	assert_int(counted[&"voice_up_datagrams"]).is_equal(0)


func test_a_backlog_s_old_part_and_frames_over_the_voice_bucket_are_counted() -> void:
	_h = Harness.new()
	var second := _h.join()
	var stranger := _h.raw()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_frames(3)
	for i in VoiceRelay.NEWEST_PER_POLL + 2:
		second.send_voice(PackedByteArray([i]))
	# A peer that is no player: its frames go nowhere, and the one past its bucket is over budget.
	for i in int(PeerBudget.VOICE_FRAMES) + 1:
		stranger.send(WireMessage.new(&"VoiceUp", {"seq": i, "opus": PackedByteArray([9])}))
	_h.pump()
	var counted := _h.session.relay_counters()
	assert_int(counted[&"voice_dropped"]).is_equal(2)
	assert_int(counted[&"voice_relayed"]).is_equal(VoiceRelay.NEWEST_PER_POLL)
	assert_int(counted[&"voice_sent"]).is_equal(VoiceRelay.NEWEST_PER_POLL)
	assert_int(counted[&"voice_over_budget"]).is_equal(1)
	assert_int(_h.session.over_budget).is_equal(1)
	# The live part (HostNode.counters(), shown on F3 in a Round too) leaves the voice frame out.
	assert_int(_h.session.over_budget_but_voice()).is_equal(0)


func test_host_node_s_live_over_budget_leaves_out_the_voice_frames() -> void:
	# One peer over its intent bucket with a SetReady and over its voice bucket with a VoiceUp.
	_h = Harness.new()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	# Long enough for its Hello's intent to refill: both buckets are full.
	_h.pump_seconds(1.0)
	for i in int(PeerBudget.INTENTS) + 1:
		second.send_intent(Intents.SET_READY, {"ready": i % 2 == 0})
	for i in int(PeerBudget.VOICE_FRAMES) + 1:
		second.send_voice(PackedByteArray([i & 0xFF]))
	_h.pump()
	assert_int(_h.session.over_budget).is_equal(2)
	assert_int(_h.session.over_budget_but_voice()).is_equal(1)
	assert_int(_h.session.voice_over_budget).is_equal(1)
	# What the F3 overlay shows at any time, a Round included (the M5 ADR §3 item 11).
	var node: HostNode = auto_free(HostNode.new(_h.session))
	assert_int(node.counters()[&"over_budget"]).is_equal(1)
	assert_int(node.relay_counters()[&"voice_over_budget"]).is_equal(1)
