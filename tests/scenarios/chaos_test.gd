extends GdUnitTestSuite
## The chaos bots' own oracle (tests/harness/chaos/, #188), without a match: ChaosBudget replays the
## host's §4.5 bookkeeping (a burst past a bucket, the malformed limit and what comes after it),
## ChaosOracle answers from §3.2's table, ChaosRun's exemption of the leak test's host counts is
## scoped to the two chaos peers, and the comparison of two runs' Rejected streams sees a
## difference. The runs themselves: tools\run.cmd bots --chaos (a verify step).

const NOW := 5_000_000


func test_a_burst_past_the_intents_bucket_is_over_budget_from_the_hundred_and_first() -> void:
	var budget := ChaosBudget.new()
	var packets: Array[ChaosFrames.Packet] = []
	var schema := WireSchema.game(true)
	for i in 130:
		packets.append(ChaosFrames.message(schema, &"ReturnToLobby", {}, ChaosFrames.CHAOS_SEQ + i))
	budget.poll(NOW, BotsRunner.FRAME_USEC, packets)
	assert_int(budget.reached.size()).is_equal(int(PeerBudget.INTENTS))
	assert_int(budget.expected[NetRejects.Reason.OVER_BUDGET]).is_equal(30)
	assert_bool(budget.over_budget_seqs.has(ChaosFrames.CHAOS_SEQ + 100)).is_true()
	assert_bool(budget.over_budget_seqs.has(ChaosFrames.CHAOS_SEQ + 99)).is_false()
	assert_bool(budget.disconnected).is_false()


func test_the_fiftieth_malformed_message_disconnects_and_the_rest_is_from_nobody() -> void:
	var budget := ChaosBudget.new()
	var rng := RandomNumberGenerator.new()
	var schema := WireSchema.game(true)
	var packets: Array[ChaosFrames.Packet] = []
	for _i in HostSession.MALFORMED_LIMIT + 2:
		packets.append(ChaosFrames.malformed(ChaosFrames.Shape.TOO_SHORT, rng, schema, 2))
	budget.poll(NOW, BotsRunner.FRAME_USEC, packets.slice(0, HostSession.MALFORMED_LIMIT - 1))
	assert_bool(budget.disconnected).is_false()
	budget.poll(NOW, BotsRunner.FRAME_USEC, packets.slice(HostSession.MALFORMED_LIMIT - 1))
	assert_bool(budget.disconnected).is_true()
	assert_int(budget.expected[NetRejects.Reason.TOO_SHORT]).is_equal(HostSession.MALFORMED_LIMIT)
	assert_int(budget.expected[NetRejects.Reason.UNKNOWN_PEER]).is_equal(2)


func test_malformed_messages_older_than_the_window_do_not_count() -> void:
	var budget := ChaosBudget.new()
	var rng := RandomNumberGenerator.new()
	var schema := WireSchema.game(true)
	var bad := ChaosFrames.malformed(ChaosFrames.Shape.BAD_BOOL, rng, schema, 2)
	for i in HostSession.MALFORMED_LIMIT:
		budget.poll(NOW + i * HostSession.MALFORMED_WINDOW_USEC / 10, 0, [bad])
	assert_bool(budget.disconnected).is_false()
	assert_int(budget.malformed_within(NOW + HostSession.MALFORMED_LIMIT * 100000)).is_less(
		HostSession.MALFORMED_LIMIT
	)


func test_the_oracle_answers_from_the_base_modes_table() -> void:
	var living := PlayerState.new(4, "Player4")
	living.ready = true
	var downed := PlayerState.new(4, "Player4")
	downed.life = PlayerState.Life.DOWNED
	var dead := PlayerState.new(4, "Player4")
	dead.life = PlayerState.Life.DEAD
	var facing := {"facing": Vector3.FORWARD}
	var cases: Array[Array] = [
		[&"SetReady", {"ready": true}, &"lobby", living, &"unchanged"],
		[&"SetReady", {"ready": true}, &"countdown", living, &"not_accepted"],
		[&"ChangeSettings", {}, &"lobby", living, &"not_accepted"],
		[&"PutDown", facing, &"lobby", living, &"not_accepted"],
		[&"PutDown", facing, &"round", living, &"empty_hand"],
		[&"PutDown", facing, &"round", downed, &"not_accepted"],
		[&"Use", facing, &"round", living, &"nothing_to_do"],
		[&"Swap", {}, &"round", living, &"nothing_to_swap"],
		[&"StopRaise", {}, &"round", living, &"not_channeling"],
		[&"Raise", {"target": 4}, &"round", living, &"not_downed"],
		[&"PickUp", {"item": ChaosOracle.NO_ITEM}, &"round", living, &"unavailable"],
		[&"GiveUp", {}, &"round", living, &"not_accepted"],
		[&"GiveUp", {}, &"round", dead, &"not_accepted"],
		[&"Use", facing, &"round", dead, &"not_accepted"],
		[&"LoadAck", {"match_id": 1234}, &"loading", living, ChaosOracle.SILENT],
		[&"LoadAck", {"match_id": 1234}, &"round", living, &"not_accepted"],
		[&"ReturnToLobby", {}, &"end", living, &"not_accepted"],
		[&"Hello", {}, &"lobby", living, &"not_accepted"],
		[&"MoveClaim", {}, &"loading", living, ChaosOracle.SILENT],
		[&"MoveClaim", {}, &"round", dead, ChaosOracle.SILENT],
		[&"SetReady", {"ready": true}, &"lobby", null, &"not_accepted"],
		[&"MoveClaim", {}, &"lobby", null, ChaosOracle.SILENT],
	]
	for case: Array in cases:
		var player: PlayerState = case[3]
		var intent: StringName = case[0]
		var args: Dictionary = case[1]
		var phase: StringName = case[2]
		var answer := ChaosOracle.answer(intent, args, 4, phase, player, 0)
		assert_str(str(answer)).override_failure_message("%s" % [case]).is_equal(str(case[4]))
	assert_bool(ChaosOracle.accepts(&"MoveClaim", 4, &"round", downed)).is_true()


func test_the_host_counts_are_exempt_for_the_two_chaos_peers_only() -> void:
	var run := ChaosRun.new()
	run.ledger = RejectLedger.new()
	run.session = HostSession.new(LoopbackTransport.new(run.schema.kind_table()), run.schema)
	run.peers.set_peer(ChaosScenario.HOSTILE, 4)
	run.malformed = ChaosMalformed.new(
		LoopbackTransport.new(run.schema.kind_table()), Callable(), run.schema, 1
	)
	run.malformed.peer = 7
	run.ledger.count(4, NetRejects.Reason.TOO_SHORT)
	run.ledger.count(7, NetRejects.Reason.BAD_PAYLOAD)
	assert_array(run.host_problems()).is_empty()
	run.ledger.count(2, NetRejects.Reason.TRUNCATED)
	assert_array(run.host_problems()).has_size(1)
	assert_str(run.host_problems()[0]).contains("honest peers")
	run.chaos_mode = ChaosRun.Mode.BASELINE
	assert_array(run.host_problems()).has_size(2)


func test_two_rejected_streams_that_differ_are_reported() -> void:
	var a := ChaosRun.new()
	var b := ChaosRun.new()
	a.hostile_rejected = PackedStringArray(["1000000 not_accepted", "1000001 empty_hand"])
	b.hostile_rejected = PackedStringArray(["1000000 not_accepted", "1000001 not_accepted"])
	assert_array(ChaosRun.compare_rejected(a, a)).is_empty()
	var found := ChaosRun.compare_rejected(a, b)
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("from answer 1")
	assert_array(ChaosRun.compare_rejected(ChaosRun.new(), ChaosRun.new())).has_size(1)
