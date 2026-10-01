extends GdUnitTestSuite
## VoiceRelay (ARCHITECTURE §4.5 "Voice relay", E11): along the routing table only, a stream seq
## per speaker and listener, the host tick, the newest frames per speaker per poll, and a peer that
## left out of the relay until the refresh after its PeerLeft.


func test_a_frame_goes_to_each_listener_that_hears_its_speaker() -> void:
	var relay := VoiceRelay.new()
	relay.refresh(_table({1: [2], 2: [1, 3], 3: [2], 4: []}), {})
	relay.hold(2, 0, PackedByteArray([7, 8]))
	assert_array(_describe(relay.flush(40))).is_equal(
		["2>1 seq 0 tick 40 0708", "2>3 seq 0 tick 40 0708"]
	)
	relay.hold(1, 9, PackedByteArray([1]))
	relay.hold(4, 0, PackedByteArray([1]))
	assert_array(_describe(relay.flush(41))).is_equal(["1>2 seq 0 tick 41 01"])


func test_a_frame_from_a_peer_that_is_not_a_present_player_is_dropped() -> void:
	var relay := VoiceRelay.new()
	relay.refresh(_table({1: [2], 2: [1]}), {})
	relay.hold(5, 0, PackedByteArray([1]))
	assert_array(relay.flush(3)).is_empty()
	assert_int(relay.dropped).is_equal(0)


func test_each_stream_counts_its_own_seq() -> void:
	var relay := VoiceRelay.new()
	relay.refresh(_table({1: [2, 3], 2: [3], 3: [2]}), {})
	for _i in 3:
		relay.hold(3, 100, PackedByteArray([3]))
		relay.flush(1)
	relay.hold(2, 0, PackedByteArray([2]))
	relay.hold(3, 200, PackedByteArray([3]))
	assert_array(_describe(relay.flush(2))).is_equal(
		["2>1 seq 0 tick 2 02", "2>3 seq 0 tick 2 02", "3>1 seq 3 tick 2 03", "3>2 seq 3 tick 2 03"]
	)


func test_only_the_newest_frames_per_speaker_per_poll() -> void:
	var relay := VoiceRelay.new()
	relay.refresh(_table({1: [2], 2: []}), {})
	# A backlog out of order, across the u16 wrap: 65530 to 65535, then 0 to 3.
	var order: Array[int] = [65531, 65530, 0, 65533, 65532, 2, 65534, 1, 65535, 3]
	for seq: int in order:
		relay.hold(2, seq, PackedByteArray([seq & 0xFF]))
	var sent := _describe(relay.flush(9))
	assert_int(sent.size()).is_equal(VoiceRelay.NEWEST_PER_POLL)
	(
		assert_array(sent)
		. is_equal(
			[
				"2>1 seq 0 tick 9 ff",
				"2>1 seq 1 tick 9 00",
				"2>1 seq 2 tick 9 01",
				"2>1 seq 3 tick 9 02",
				"2>1 seq 4 tick 9 03",
			]
		)
	)
	assert_int(relay.dropped).is_equal(order.size() - VoiceRelay.NEWEST_PER_POLL)


func test_a_peer_that_left_is_out_until_the_refresh_after_its_leave() -> void:
	var relay := VoiceRelay.new()
	relay.refresh(_table({1: [2], 2: [1]}), {})
	relay.hold(2, 0, PackedByteArray([1]))
	relay.leave(2)
	relay.hold(2, 1, PackedByteArray([1]))
	relay.hold(1, 0, PackedByteArray([1]))
	assert_array(relay.flush(5)).is_empty()
	# A refresh while its PeerLeft is still pending keeps it out, even as a listener.
	relay.refresh(_table({1: [2], 2: [1]}), {2: true})
	relay.hold(1, 1, PackedByteArray([1]))
	assert_array(relay.flush(6)).is_empty()
	# After the tick that applied it, whoever has id 2 is in the table on its own merits.
	relay.refresh(_table({1: [2], 2: [1]}), {})
	relay.hold(1, 2, PackedByteArray([1]))
	assert_array(_describe(relay.flush(7))).is_equal(["1>2 seq 0 tick 7 01"])


func _table(entries: Dictionary) -> Dictionary[int, PackedInt32Array]:
	var table: Dictionary[int, PackedInt32Array] = {}
	for listener: int in entries:
		table[listener] = PackedInt32Array(entries[listener] as Array)
	return table


func _describe(out: Array[VoiceRelay.Outgoing]) -> Array[String]:
	var found: Array[String] = []
	for each: VoiceRelay.Outgoing in out:
		var fields := each.message.fields
		var opus: PackedByteArray = fields["opus"]
		assert_int(fields["speaker"] as int).is_not_equal(each.listener)
		found.append(
			(
				"%d>%d seq %d tick %d %s"
				% [
					fields["speaker"],
					each.listener,
					fields["seq"],
					fields["tick"],
					opus.hex_encode()
				]
			)
		)
	return found
