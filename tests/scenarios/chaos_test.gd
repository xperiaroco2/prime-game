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
		budget.poll(NOW + i * int(HostSession.MALFORMED_WINDOW_USEC * 0.1), 0, [bad])
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
		[&"MoveClaim", {}, &"pregame", living, ChaosOracle.SILENT],
		[&"Use", facing, &"pregame", living, &"not_accepted"],
		[&"PickUp", {"item": ChaosOracle.NO_ITEM}, &"pregame", living, &"not_accepted"],
		[&"LoadAck", {"match_id": 1234}, &"pregame", living, &"not_accepted"],
		[&"MoveClaim", {}, &"round", dead, ChaosOracle.SILENT],
		[&"SetReady", {"ready": true}, &"lobby", null, &"not_accepted"],
		[&"MoveClaim", {}, &"lobby", null, ChaosOracle.SILENT],
		[&"NextStage", {}, &"lobby", living, &"not_accepted"],
		[&"NextStage", {}, &"round", living, &"not_accepted"],
		[&"NextStage", {}, &"round", downed, &"not_accepted"],
		[&"NextStage", {}, &"end", dead, &"not_accepted"],
	]
	for case: Array in cases:
		var player: PlayerState = case[3]
		var intent: StringName = case[0]
		var args: Dictionary = case[1]
		var phase: StringName = case[2]
		var answer := ChaosOracle.answer(intent, args, 4, phase, player, 0)
		assert_str(str(answer)).override_failure_message("%s" % [case]).is_equal(str(case[4]))
	assert_bool(ChaosOracle.accepts(&"MoveClaim", 4, &"round", downed)).is_true()


func test_every_intent_has_an_oracle_answer_and_next_stage_is_refused_even_from_the_host() -> void:
	# #599: every intent is in a phase of ACCEPTS or in NEVER_ACCEPTED, so a new intent forces a
	# decision here; NextStage is refused in every base-mode phase, peer 1's included.
	for intent: StringName in Intents.ALL:
		var listed := ChaosOracle.NEVER_ACCEPTED.has(intent)
		for phase: StringName in ChaosOracle.ACCEPTS:
			listed = listed or (ChaosOracle.ACCEPTS[phase] as Dictionary).has(intent)
		assert_bool(listed).override_failure_message(str(intent)).is_true()
	assert_array(ChaosOracle.NEVER_ACCEPTED).contains([Intents.NEXT_STAGE])
	var host := PlayerState.new(NetTransport.HOST_ID, "Player1")
	for phase: StringName in ChaosOracle.ACCEPTS:
		(
			assert_bool(ChaosOracle.accepts(Intents.NEXT_STAGE, NetTransport.HOST_ID, phase, host))
			. is_false()
		)
		for intent: StringName in ChaosOracle.NEVER_ACCEPTED:
			assert_bool((ChaosOracle.ACCEPTS[phase] as Dictionary).has(intent)).is_false()


func test_the_oracle_answers_a_pick_up_by_the_items_place_and_the_senders_reach() -> void:
	var state := MatchState.new(1)
	var me := state.add_player(4, "Player4")
	me.position = Vector3(1.0, 0.0, 1.0)
	var knife := load("res://content/items/knife.tres") as ItemKind
	state.items[0] = ItemState.new(0, knife, Vector3(12.0, 0.0, 1.0))
	state.items[1] = ItemState.new(1, knife, Vector3(2.0, 0.0, 1.0))
	state.items[2] = ItemState.new(2, knife, Vector3(30.0, 0.0, 1.0))
	state.items[2].where = ItemState.Where.HAND
	state.items[2].holder = 2
	var cases: Array[Array] = [
		[0, &"out_of_reach"],
		[1, &"?"],
		[2, &"unavailable"],
		[ChaosOracle.NO_ITEM, &"unavailable"],
	]
	for case: Array in cases:
		var args := {"item": case[0]}
		var answer := ChaosOracle.answer(&"PickUp", args, 4, &"round", me, 0, state)
		assert_str(str(answer)).override_failure_message("%s" % [case]).is_equal(str(case[1]))
	# Within reach of the sender's position (the host's, not a claimed one) a pick-up could be
	# taken: the oracle has no answer, so the run reports it as a race.
	me.position = Vector3(11.0, 0.0, 1.0)
	var near := ChaosOracle.answer(&"PickUp", {"item": 0}, 4, &"round", me, 0, state)
	assert_str(str(near)).is_equal("?")


func test_the_oracle_answers_a_raise_by_the_targets_life_alone() -> void:
	var state := MatchState.new(1)
	var me := state.add_player(4, "Player4")
	var dissident := state.add_player(1, "Player1")
	dissident.role = &"dissident"
	var crew := state.add_player(3, "Player3")
	crew.role = &"crew"
	var downed := state.add_player(2, "Player2")
	downed.life = PlayerState.Life.DOWNED
	for target: int in [1, 3, 4]:
		var answer := ChaosOracle.answer(&"Raise", {"target": target}, 4, &"round", me, 0, state)
		assert_str(str(answer)).override_failure_message("target %d" % target).is_equal(
			"not_downed"
		)
	var at_downed := ChaosOracle.answer(&"Raise", {"target": 2}, 4, &"round", me, 0, state)
	assert_str(str(at_downed)).is_equal("?")


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


func test_over_enet_a_chaos_peers_counts_are_bounded_by_what_it_sent() -> void:
	var run := ChaosRun.new()
	run.ledger = RejectLedger.new()
	run.ledger.count(4, NetRejects.Reason.TRUNCATED)
	run.ledger.count(4, NetRejects.Reason.OVER_BUDGET)
	run.ledger.count(4, NetRejects.Reason.UNKNOWN_PEER)
	var found := run.check_bounded("hostile", 4)
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("1 TRUNCATED from the hostile, which sent 0")
	var rng := RandomNumberGenerator.new()
	var truncated := ChaosFrames.malformed(ChaosFrames.Shape.TRUNCATED, rng, run.schema, 4)
	var honest := ChaosFrames.malformed(ChaosFrames.Shape.TRUNCATED, rng, run.schema, 4)
	honest.label = "honest"
	run._note_chaos_sent(4, [honest])
	assert_array(run.check_bounded("hostile", 4)).has_size(1)
	run._note_chaos_sent(4, [truncated])
	assert_array(run.check_bounded("hostile", 4)).is_empty()


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


func test_the_malformed_peer_sends_no_force_role_while_bot_2_has_no_peer() -> void:
	var schema := WireSchema.game(true)
	# Bot 2 lost its join (#483): its peer id is 0, which no ForceRole may name.
	var without := _first_words(schema, 0)
	assert_array(without["errors"] as PackedStringArray).is_empty()
	assert_array(without["labels"] as Array).not_contains(["intent ForceRole"])
	assert_array(without["labels"] as Array).contains(["intent SetReady", "intent VoiceUp"])
	var with := _first_words(schema, 22)
	var force_roles := (with["packets"] as Array).filter(
		func(packet: ChaosFrames.Packet) -> bool: return packet.label == "intent ForceRole"
	)
	assert_array(force_roles).has_size(1)
	var force_role: ChaosFrames.Packet = force_roles[0] if not force_roles.is_empty() else null
	assert_int(force_role.expect if force_role != null else -1).is_equal(
		NetRejects.Reason.BAD_PAYLOAD
	)


## What a connected malformed peer sends in its first START_AFTER_FRAMES frames, bot 2's peer being
## `crew_peer`: {packets, labels, errors (the error lines logged meanwhile)}.
func _first_words(schema: WireSchema, crew_peer: int) -> Dictionary:
	var packets: Array[ChaosFrames.Packet] = []
	var send_raw := func(packet: ChaosFrames.Packet) -> bool:
		packets.append(packet)
		return true
	var malformed := ChaosMalformed.new(
		LoopbackTransport.new(schema.kind_table()), send_raw, schema, 1
	)
	malformed.peer = 7
	var chaos_log := ChaosLog.new()
	chaos_log.start()
	for _i in ChaosMalformed.START_AFTER_FRAMES:
		malformed.act(crew_peer)
	chaos_log.stop()
	var labels: Array = packets.map(func(packet: ChaosFrames.Packet) -> String: return packet.label)
	return {"packets": packets, "labels": labels, "errors": chaos_log.errors()}
