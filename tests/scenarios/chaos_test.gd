extends GdUnitTestSuite
## The chaos bots' own oracle (tests/harness/chaos/, #188), without a match: ChaosBudget replays the
## host's §4.5 bookkeeping (a burst past a bucket, the malformed limit and what comes after it),
## ChaosOracle answers from §3.2's table, ChaosRun's exemption of the leak test's host counts is
## scoped to the two chaos peers, and the comparison of two runs' Rejected streams sees a
## difference. The runs themselves: tools\run.cmd bots --chaos (a verify step).

const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const NOW := 5_000_000
## The chaos match's four bots as peers of a match without a network, bot 4 the hostile's.
const BOT_PEERS: Array[int] = [1, 2, 3, 4]


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
		# The hall takes the hand, the belt and Interact from the living as Round does (#1388).
		[&"PutDown", facing, &"lobby", living, &"empty_hand"],
		[&"PutDown", facing, &"countdown", living, &"empty_hand"],
		# Any hand hits (#1437): the chaos peers never send a living Use where a phase takes it.
		[&"Use", facing, &"lobby", living, &"?"],
		[&"UseSecondary", facing, &"lobby", living, &"nothing_to_do"],
		[&"Swap", {}, &"countdown", living, &"nothing_to_swap"],
		[&"PickUp", {"item": ChaosOracle.NO_ITEM}, &"lobby", living, &"unavailable"],
		[&"Draw", {"place": 0}, &"lobby", living, &"same_place"],
		[&"Draw", {"place": 7}, &"countdown", living, &"no_such_place"],
		[&"Interact", {"station": 7}, &"lobby", living, &"nothing_to_do"],
		[&"Interact", {}, &"countdown", living, &"bad_args"],
		[&"PutDown", facing, &"lobby", null, &"not_accepted"],
		[&"Throw", facing, &"lobby", living, &"not_accepted"],
		[&"Throw", facing, &"countdown", living, &"not_accepted"],
		[&"Raise", {"target": 4}, &"lobby", living, &"not_accepted"],
		[&"Pose", {"pose": 1}, &"lobby", living, &"not_accepted"],
		# Every phase that holds items takes HandOver (#1389, #1434); HoldsItem comes first.
		[&"HandOver", {"target": 3}, &"lobby", living, &"empty_hand"],
		[&"HandOver", {"target": 4}, &"countdown", living, &"empty_hand"],
		[&"HandOver", {"target": 3}, &"round", living, &"empty_hand"],
		[&"TakeOffer", {"target": 3}, &"lobby", living, &"no_offer"],
		[&"CancelOffer", {}, &"round", living, &"no_offer"],
		[&"TakeOffer", {"target": 3}, &"loading", living, &"not_accepted"],
		[&"HandOver", {"target": 3}, &"lobby", downed, &"not_accepted"],
		[&"PutDown", facing, &"round", living, &"empty_hand"],
		[&"PutDown", facing, &"round", downed, &"not_accepted"],
		[&"Use", facing, &"round", living, &"?"],
		[&"Swap", {}, &"round", living, &"nothing_to_swap"],
		[&"StopRaise", {}, &"round", living, &"not_channeling"],
		[&"Raise", {"target": 4}, &"round", living, &"not_downed"],
		[&"PickUp", {"item": ChaosOracle.NO_ITEM}, &"round", living, &"unavailable"],
		[&"GiveUp", {}, &"round", living, &"not_accepted"],
		[&"GiveUp", {}, &"round", dead, &"not_accepted"],
		[&"Use", facing, &"round", dead, &"not_accepted"],
		[&"UseSecondary", facing, &"round", dead, &"not_accepted"],
		[&"LoadAck", {"match_id": 1234}, &"loading", living, ChaosOracle.SILENT],
		[&"LoadAck", {"match_id": 1234}, &"round", living, &"not_accepted"],
		[&"ReturnToLobby", {}, &"end", living, &"not_accepted"],
		[&"Hello", {}, &"lobby", living, &"not_accepted"],
		[&"MoveClaim", {}, &"loading", living, ChaosOracle.SILENT],
		[&"MoveClaim", {}, &"pregame", living, ChaosOracle.SILENT],
		[&"Use", facing, &"pregame", living, &"not_accepted"],
		[&"UseSecondary", facing, &"pregame", living, &"not_accepted"],
		[&"PickUp", {"item": ChaosOracle.NO_ITEM}, &"pregame", living, &"not_accepted"],
		[&"LoadAck", {"match_id": 1234}, &"pregame", living, &"not_accepted"],
		[&"MoveClaim", {}, &"round", dead, ChaosOracle.SILENT],
		[&"SetReady", {"ready": true}, &"lobby", null, &"not_accepted"],
		[&"MoveClaim", {}, &"lobby", null, ChaosOracle.SILENT],
		[&"NextStage", {}, &"lobby", living, &"not_accepted"],
		[&"NextStage", {}, &"round", living, &"not_accepted"],
		[&"NextStage", {}, &"round", downed, &"not_accepted"],
		[&"NextStage", {}, &"end", dead, &"not_accepted"],
		[&"SetProfile", {"name": "Player4", "colour": 0}, &"lobby", living, &"unchanged"],
		[&"SetProfile", {"name": "Hacked", "colour": 3}, &"countdown", living, &"not_accepted"],
		[&"SetProfile", {"name": "Hacked", "colour": 3}, &"loading", living, &"not_accepted"],
		[&"SetProfile", {"name": "Hacked", "colour": 3}, &"round", living, &"not_accepted"],
		[&"SetProfile", {"name": "Hacked", "colour": 3}, &"end", dead, &"not_accepted"],
		[&"SetProfile", {"name": "Player4", "colour": 0}, &"lobby", null, &"not_accepted"],
		# The machine takes Flippers from the living in Lobby and Countdown only (#1398); a chaos
		# peer never sits, so PinballSeated answers not_seated.
		[&"Flippers", {"left": true, "right": false}, &"lobby", living, &"not_seated"],
		[&"Flippers", {"left": false, "right": true}, &"countdown", living, &"not_seated"],
		[&"Flippers", {"left": true, "right": true}, &"round", living, &"not_accepted"],
		[&"Flippers", {"left": true, "right": false}, &"lobby", dead, &"not_accepted"],
		[&"Flippers", {"left": true, "right": false}, &"lobby", null, &"not_accepted"],
		# The pose wheel everywhere a living player stands (#1485): a hostile's half or
		# out-of-range pick is no_such_pose; the frozen phases and the dead are not accepted.
		[&"WheelPose", {"legs": 15, "arms": 0}, &"lobby", living, &"no_such_pose"],
		[&"WheelPose", {"legs": 0, "arms": 200}, &"countdown", living, &"no_such_pose"],
		[&"WheelPose", {"legs": 255, "arms": 255}, &"round", living, &"no_such_pose"],
		[&"WheelPose", {"legs": 15, "arms": 0}, &"pregame", living, &"not_accepted"],
		[&"WheelPose", {"legs": 15, "arms": 0}, &"end", living, &"not_accepted"],
		[&"WheelPose", {"legs": 15, "arms": 0}, &"round", dead, &"not_accepted"],
		[&"WheelPose", {"legs": 15, "arms": 0}, &"round", downed, &"not_accepted"],
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


func test_the_oracle_refuses_pose_out_of_reach_since_no_chaos_level_holds_a_chair() -> void:
	# The base mode's Pose (#1383) is gated by its AtMarker; the oracle answers out_of_reach
	# because no level the scenario runners play has a marker of its tag. A chair on one of them
	# (or Pose's row losing its gate) must change the oracle, so this fails first.
	var living := PlayerState.new(4, "Player4")
	assert_str(str(ChaosOracle.answer(Intents.POSE, {}, 4, &"round", living, 0))).is_equal(
		str(AtMarker.OUT_OF_REACH)
	)
	var mode := load("res://content/modes/base_mode.tres") as GameMode
	var chair := PoseUse.chair_of(mode)
	assert_object(chair).is_not_null()
	var levels := MarkerReader.read_levels(
		mode, FlatWorldQuery.new(), ScenarioLevels.unsnapped(mode)
	)
	for path: String in ScenarioLevels.of(mode):
		var layout: LevelLayout = levels.layouts.get(path)
		assert_object(layout).override_failure_message(path).is_not_null()
		assert_array(Array(layout.positions(chair.tag))).override_failure_message(path).is_empty()


func test_the_oracle_leaves_flippers_from_the_seated_player_open() -> void:
	# A seated sender's Flippers goes to SetFlippers, which the chaos peers never reach (#1398).
	var state := MatchState.new(1)
	var me := state.add_player(4, "Player4")
	var args := {"left": true, "right": false}
	var answer := ChaosOracle.answer(&"Flippers", args, 4, &"lobby", me, 0, state)
	assert_str(str(answer)).is_equal("not_seated")
	Pinball.game(state).player = 4
	answer = ChaosOracle.answer(&"Flippers", args, 4, &"lobby", me, 0, state)
	assert_str(str(answer)).is_equal("?")
	Pinball.game(state).player = 3
	answer = ChaosOracle.answer(&"Flippers", args, 4, &"countdown", me, 0, state)
	assert_str(str(answer)).is_equal("not_seated")


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


func test_the_oracle_looks_for_interact_rules_where_the_host_does() -> void:
	# Match._find_action: a station tries its kind's actions, the actor's role's and the mode's;
	# an item only its kind's target_actions (never its actions, ModeCheck's GE2).
	var interact := Rule.new()
	interact.trigger = Intents.INTERACT
	var state := MatchState.new(1)
	var me := state.add_player(4, "Player4")
	me.role = &"crew"
	var bare := StationKind.new()
	var ruled := StationKind.new()
	ruled.actions = [interact]
	var shown := StationKind.new()
	shown.display = true
	shown.actions = [interact]
	state.stations[0] = StationState.new(0, bare, Vector3.ZERO, Color.WHITE)
	state.stations[1] = StationState.new(1, ruled, Vector3.ZERO, Color.WHITE)
	state.stations[2] = StationState.new(2, shown, Vector3.ZERO, Color.WHITE)
	var plain := ItemKind.new()
	var targeted := ItemKind.new()
	targeted.target_actions = [interact]
	var held := ItemKind.new()
	held.actions = [interact]
	state.items[0] = ItemState.new(0, plain, Vector3.ZERO)
	state.items[1] = ItemState.new(1, targeted, Vector3.ZERO)
	state.items[2] = ItemState.new(2, held, Vector3.ZERO)
	var role := GameRole.new()
	role.id = &"crew"
	var mode := GameMode.new()
	mode.roles = [role]
	var cases: Array[Array] = [
		[{"station": 0}, &"nothing_to_do"],
		[{"station": 1}, &"?"],
		[{"station": 2}, &"nothing_to_do"],
		[{"station": 7}, &"nothing_to_do"],
		[{"item": 0}, &"nothing_to_do"],
		[{"item": 1}, &"?"],
		[{"item": 2}, &"nothing_to_do"],
		[{"item": 9}, &"nothing_to_do"],
		[{"station": 0, "item": 0}, &"bad_args"],
		[{}, &"bad_args"],
	]
	for case: Array in cases:
		var answer := ChaosOracle.answer(
			&"Interact", case[0] as Dictionary, 4, &"round", me, 0, state, mode
		)
		assert_str(str(answer)).override_failure_message("%s" % [case]).is_equal(str(case[1]))
	# A role's or the mode's rule is tried for a station target, never for an item target.
	role.actions = [interact]
	var by_role := ChaosOracle.answer(&"Interact", {"station": 0}, 4, &"round", me, 0, state, mode)
	assert_str(str(by_role)).is_equal("?")
	var item_by_role := ChaosOracle.answer(
		&"Interact", {"item": 0}, 4, &"round", me, 0, state, mode
	)
	assert_str(str(item_by_role)).is_equal("nothing_to_do")
	role.actions = []
	mode.actions = [interact]
	var by_mode := ChaosOracle.answer(&"Interact", {"station": 0}, 4, &"round", me, 0, state, mode)
	assert_str(str(by_mode)).is_equal("?")


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


func test_the_oracle_answers_a_hand_over_by_the_held_item_then_the_target() -> void:
	var state := MatchState.new(1)
	var me := state.add_player(4, "Player4")
	var near := state.add_player(3, "Player3")
	near.position = Vector3(1.5, 0.0, 0.0)
	var far := state.add_player(1, "Player1")
	far.position = Vector3(6.0, 0.0, 0.0)
	var downed := state.add_player(2, "Player2")
	downed.life = PlayerState.Life.DOWNED
	downed.position = Vector3(0.5, 0.0, 0.0)
	var limp := state.add_player(5, "Player5")
	limp.limp = LimpState.new(1 << 30)
	limp.position = Vector3(0.5, 0.0, 0.0)
	var empty := ChaosOracle.answer(&"HandOver", {"target": 3}, 4, &"lobby", me, 0, state)
	assert_str(str(empty)).is_equal("empty_hand")
	var crate := ItemKind.new()
	crate.hands = 2
	# Every kind may be offered (#1434), a two-handed one too.
	var cases: Array[Array] = [
		[crate, 3, &"?"],
		[ItemKind.new(), 4, &"bad_args"],
		[ItemKind.new(), 2, &"not_living"],
		[ItemKind.new(), 5, &"not_living"],
		[ItemKind.new(), ChaosOracle.NO_ITEM, &"not_living"],
		[ItemKind.new(), 1, &"out_of_reach"],
		# Within reach the answer is TargetInSight's, which needs the level: no answer.
		[ItemKind.new(), 3, &"?"],
	]
	for case: Array in cases:
		_hold(state, me, case[0] as ItemKind)
		var args := {"target": case[1]}
		var answer := ChaosOracle.answer(&"HandOver", args, 4, &"round", me, 0, state)
		assert_str(str(answer)).override_failure_message("%s" % [case]).is_equal(str(case[2]))
	# With its own offer open the sender's HandOver is the negated Offering's `not_allowed`.
	_offers(state).by_giver[4] = Offers.Offer.new(4, 3, 0, 0)
	var again := ChaosOracle.answer(&"HandOver", {"target": 1}, 4, &"lobby", me, 0, state)
	assert_str(str(again)).is_equal("not_allowed")


## TakeOffer (#1434): OfferedTo first (`bad_args` naming the sender, `no_offer` without an offer of
## the named giver to the sender), then TargetLiving and TargetInReach; CancelOffer is `no_offer`
## without the sender's own offer.
func test_the_oracle_answers_a_take_and_a_cancel_by_the_open_offers() -> void:
	var state := MatchState.new(1)
	var me := state.add_player(4, "Player4")
	var giver := state.add_player(3, "Player3")
	giver.position = Vector3(1.5, 0.0, 0.0)
	var other := state.add_player(1, "Player1")
	other.position = Vector3(6.0, 0.0, 0.0)
	for target: int in [3, 1, ChaosOracle.NO_ITEM]:
		var none := ChaosOracle.answer(&"TakeOffer", {"target": target}, 4, &"round", me, 0, state)
		assert_str(str(none)).override_failure_message("target %d" % target).is_equal("no_offer")
	var own := ChaosOracle.answer(&"TakeOffer", {"target": 4}, 4, &"lobby", me, 0, state)
	assert_str(str(own)).is_equal("bad_args")
	assert_str(str(ChaosOracle.answer(&"CancelOffer", {}, 4, &"round", me, 0, state))).is_equal(
		"no_offer"
	)
	# Player3 offers its hand item to Player4: the take within reach needs the level's sight.
	_hold(state, giver, ItemKind.new())
	_offers(state).by_giver[3] = Offers.Offer.new(3, 4, 0, 0)
	var take := ChaosOracle.answer(&"TakeOffer", {"target": 3}, 4, &"countdown", me, 0, state)
	assert_str(str(take)).is_equal("?")
	giver.position = Vector3(3.0, 0.0, 0.0)
	var far := ChaosOracle.answer(&"TakeOffer", {"target": 3}, 4, &"round", me, 0, state)
	assert_str(str(far)).is_equal("out_of_reach")
	# The offer is Player3's, not Player4's: Player4 has nothing to cancel.
	assert_str(str(ChaosOracle.answer(&"CancelOffer", {}, 4, &"round", me, 0, state))).is_equal(
		"no_offer"
	)


## Puts a new item 0 of `kind` in `player`'s hand.
func _hold(state: MatchState, player: PlayerState, kind: ItemKind) -> void:
	state.items[0] = ItemState.new(0, kind, Vector3.ZERO)
	state.items[0].where = ItemState.Where.HAND
	state.items[0].holder = player.peer
	player.held_item = 0


func _offers(state: MatchState) -> Offers.Table:
	return state.part_state(Offers.PART_KEY, func() -> RefCounted: return Offers.Table.new())


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


## #674: bot 4's claim after the freeze covers the silence, a tick more when the freeze starts
## between two client ticks, and the claims a network lost just before it; past the credit the host
## corrects it and bot 4 stands corrected at ChaosScenario.STAND_AT all round, which held back
## every hostile claim over WebRTC (a 200-tick freeze, 201 covered).
func test_the_claim_after_the_freeze_fits_its_credit_with_lost_claims() -> void:
	var silent := Ticks.from_seconds(ChaosScenario.FREEZE_S)
	assert_int(silent).is_equal(ChaosScenario.FREEZE_TICKS)
	assert_int(silent).is_greater(ZoneTask.STALE_TICKS)
	var lost := MovementRule.PUSH_TICKS - 1
	assert_int(silent + 1 + lost).is_less_equal(MovementRule.MAX_TICK_CREDIT)


## #693: bot 4's script adopts no Correction outside a placement (each is taken for a chaos
## claim's), so the run checks the host's answer to each of its honest claims instead: a Correction
## of one fails the run, naming the seed; another peer's Correction or no answer passes, and a
## chaos claim or another peer's claim is not checked here.
func test_a_correction_of_the_hostile_bots_honest_claim_fails_naming_the_seed() -> void:
	var claims := ChaosHonestClaims.new()
	var fields := _claim_fields(372)
	var honest := MatchCommand.new(Intents.MOVE_CLAIM, 4, 300, fields)
	assert_int(ChaosFrames.claim_shape(honest.args)).is_equal(-1)
	var player := PlayerState.new(4, "bot 4")
	var corrected: Array[EmittedEvent] = [_correction_to(4, 3)]
	claims.check(honest, corrected, player, 4, 7)
	assert_int(claims.corrected).is_equal(1)
	assert_str(claims.failures()[0]).contains("chaos seed 7: the host corrected an honest claim")
	assert_str(claims.failures()[0]).contains("client tick 372")
	assert_str(claims.failures()[0]).ends_with("(and 0 more)")
	# A Correction to another peer, or none, is no failure.
	var none: Array[EmittedEvent] = []
	var to_another: Array[EmittedEvent] = [_correction_to(5, 3)]
	claims.check(honest, to_another, player, 4, 7)
	claims.check(honest, none, player, 4, 7)
	assert_int(claims.corrected).is_equal(1)
	# Only a claim the movement rule accepted (the player's claim_tick is the claim's) is counted.
	assert_int(claims.accepted).is_equal(0)
	player.claim_tick = 372
	claims.check(honest, none, player, 4, 7)
	assert_int(claims.accepted).is_equal(1)
	# Later corrections are counted, not reported again: the first one stays the failure.
	claims.check(honest, corrected, player, 4, 8)
	claims.check(honest, corrected, player, 4, 8)
	assert_int(claims.corrected).is_equal(3)
	assert_int(claims.failures().size()).is_equal(1)
	assert_str(claims.failures()[0]).contains("chaos seed 7").ends_with("(and 2 more)")
	var tagged := fields.duplicate()
	tagged["velocity"] = Vector3(0, ChaosFrames.CLAIM_TAG + ChaosFrames.Claim.TELEPORT, 0)
	var chaos := MatchCommand.new(Intents.MOVE_CLAIM, 4, 300, tagged)
	assert_int(ChaosFrames.claim_shape(chaos.args)).is_equal(ChaosFrames.Claim.TELEPORT)
	claims.check(chaos, corrected, player, 4, 7)
	var from_bot_1 := MatchCommand.new(Intents.MOVE_CLAIM, 1, 300, fields)
	claims.check(from_bot_1, [_correction_to(1, 3)], player, 4, 7)
	# Before bot 4 has a peer id (hostile_peer 0), nothing is bot 4's.
	claims.check(honest, corrected, player, 0, 7)
	assert_int(claims.corrected).is_equal(3)
	assert_int(claims.accepted).is_equal(1)


## The wiring (#693): ChaosRun hands bot 4's honest claim and the host's answer to the check, which
## the run reports in its failures; a chaos claim, and an honest claim of another peer, it does not.
func test_the_run_reports_a_corrected_honest_claim_of_bot_4_and_counts_the_accepted() -> void:
	var run := ChaosRun.new(false, ChaosRun.Mode.CHAOS, 188001)
	run.peers.set_peer(ChaosScenario.HOSTILE, 4)
	run.game = Match.new(GameMode.new(), 1, WorldQuery.new(), {})
	var player := run.game.state.add_player(4, "bot 4")
	player.claim_tick = 372
	var honest := MatchCommand.new(Intents.MOVE_CLAIM, 4, 300, _claim_fields(372))
	var none: Array[EmittedEvent] = []
	run._note_honest_claim(honest, none)
	assert_int(run.honest_claims.accepted).is_equal(1)
	assert_array(run.honest_claims.failures()).is_empty()
	var corrected: Array[EmittedEvent] = [_correction_to(4, 3)]
	run._note_honest_claim(honest, corrected)
	var found := run.honest_claims.failures()
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("chaos seed 188001: the host corrected an honest claim of bot 4")


## #1194, the race behind a red chaos-webrtc run (seed 188001: bot 4 corrected 1.05 m into its walk
## from its spawn, 75 times): the pregame takes no claim (E15),
## but a hostile claim sent in its last frames can reach the host in the round, before bot 4's
## first claim of its epoch. Its Correction leaves the new epoch without a client-tick baseline,
## bot 4's claims still in flight in the old one are stale, and its first claim of the new epoch,
## a round trip into the walk it began as its client saw the round start, counts one tick
## (MovementRule's fresh claim): corrected, and its script adopts no Correction (#693), so every
## claim after it too. The host is right (an honest client adopts the Correction); the quiet rule
## below keeps such a claim from going.
func test_a_pregame_claim_taken_in_the_round_gets_bot_4s_walk_corrected() -> void:
	var game := FixtureBaseMode.in_pregame(BOT_PEERS)
	var player := game.state.player(4)
	var spawn := player.position
	var epoch := player.epoch
	var teleport := Vector3(ChaosFrames.TELEPORT_M, 0, 0)
	var tagged := Vector3(0, ChaosFrames.CLAIM_TAG + ChaosFrames.Claim.TELEPORT, 0)
	assert_array(_apply(game, _move_claim(epoch, 111, spawn + teleport, tagged))).is_empty()
	FixtureBaseMode.through_pregame(game)
	assert_str(game.phase_id()).is_equal("round")
	var late := _apply(game, _move_claim(epoch, 111, spawn + teleport, tagged))
	assert_int(late.size()).is_equal(1)
	var correction := late[0].event as CorrectionEvent
	assert_object(correction).is_not_null()
	assert_int(correction.epoch).is_equal(epoch + 1)
	assert_vector(correction.position).is_equal(spawn)
	# A step of its walk to STAND_AT (Vector3(-9, 0, 7)) per tick, as at walk speed.
	var step := (ChaosScenario.STAND_AT - spawn).normalized() * 0.2
	var walking := Vector3(step.x * Ticks.RATE, 0, step.z * Ticks.RATE)
	assert_array(_apply(game, _move_claim(epoch, 171, spawn + step, walking))).is_empty()
	# Dropped as stale, not accepted (an accepted claim emits nothing either, but moves the player).
	assert_vector(game.state.player(4).position).is_equal(spawn)
	var claims := ChaosHonestClaims.new()
	var walked := _move_claim(epoch + 1, 175, spawn + step * 5, walking)
	claims.check(walked, _apply(game, walked), player, 4, 188001)
	assert_int(claims.corrected).is_equal(1)
	assert_int(claims.accepted).is_equal(0)


## #1194: bot 4 is quiet before its walk away from the pregame on, not from the round's start
## alone: the pregame's claims are dropped anyway (E15), so no hostile claim can be taken in the
## round's first ticks (above). In the countdown and loading it claims as before (it stands, and
## the placement into the pregame starts a new epoch), and after its walk away too.
func test_the_hostile_sends_no_claim_from_the_pregame_until_its_walk_away() -> void:
	var run := ChaosRun.new(false, ChaosRun.Mode.CHAOS, 188001)
	run.peers.set_peer(ChaosScenario.HOSTILE, 4)
	run.game = FixtureBaseMode.in_countdown(BOT_PEERS)
	for number in range(1, ChaosScenario.BOTS + 1):
		run.bots.append(ScenarioBot.new(number, number, run.scenario.steps_of(number), run.peers))
	var bot := run.bots[ChaosScenario.HOSTILE - 1]
	bot.position = run.game.state.player(4).position
	assert_str(run._quiet_reason()).is_empty()
	while run.game.phase_id() == &"countdown":
		FixtureModes.run_ticks(run.game, 1)
	assert_str(run.game.phase_id()).is_equal("loading")
	assert_str(run._quiet_reason()).is_empty()
	for peer: int in BOT_PEERS:
		FixtureBaseMode.load_ack(run.game, peer)
	assert_str(run.game.phase_id()).is_equal("pregame")
	bot.position = run.game.state.player(4).position
	assert_str(run._quiet_reason()).is_equal(ChaosRun.QUIET_BEFORE_AWAY)
	FixtureBaseMode.through_pregame(run.game)
	assert_str(run.game.phase_id()).is_equal("round")
	assert_str(run._quiet_reason()).is_equal(ChaosRun.QUIET_BEFORE_AWAY)
	bot.step_index = ChaosScenario.away_index(bot.steps) + 1
	assert_str(run._quiet_reason()).is_empty()


## A MoveClaim of bot 4's peer (4) as its client sends one, with `velocity` (a chaos claim's tag).
func _move_claim(epoch: int, tick: int, position: Vector3, velocity: Vector3) -> MatchCommand:
	var fields := {
		"epoch": epoch,
		"client_tick": tick,
		"position": position,
		"velocity": velocity,
		"facing": Vector3.FORWARD,
		"sprint": false,
		"moving": not velocity.is_zero_approx(),
		"on_floor": true,
		"jumps": 0,
	}
	return MatchCommand.new(Intents.MOVE_CLAIM, 4, 0, fields)


## Applies `command` stamped with the next tick; the events it emitted.
func _apply(game: Match, command: MatchCommand) -> Array[EmittedEvent]:
	var before := game.emitted().size()
	command.tick = game.ticked_through() + 1
	game.apply(command)
	return game.emitted().slice(before)


func _claim_fields(tick: int) -> Dictionary:
	return {
		"epoch": 2,
		"client_tick": tick,
		"position": Vector3(20, 0, -20),
		"velocity": Vector3(1, 0, 0)
	}


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


## The host's Correction to `peer` (MovementRule._correct's answer to a refused claim).
func _correction_to(peer: int, epoch: int) -> EmittedEvent:
	var correction := CorrectionEvent.new(peer, epoch, Vector3(-9, 0, 7), Vector3.ZERO)
	return EmittedEvent.new(300, correction, PackedInt32Array([peer]), false)


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


func test_the_oracle_refuses_throw_in_every_phase_and_life_state_whatever_the_facing() -> void:
	# §3.2, §4.6.5.3: Round takes Throw from the living only (the base mode's Throw rule, #646),
	# whose empty hand HoldsItem refuses as empty_hand; elsewhere, and from the downed, the dead
	# and a newcomer, not_accepted. A refused Throw is answered, never dropped in silence.
	var living := PlayerState.new(4, "Player4")
	var downed := PlayerState.new(4, "Player4")
	downed.life = PlayerState.Life.DOWNED
	var dead := PlayerState.new(4, "Player4")
	dead.life = PlayerState.Life.DEAD
	var host := PlayerState.new(1, "Player1")
	for phase: StringName in ChaosOracle.ACCEPTS:
		var in_round := phase == &"round"
		assert_bool(ChaosOracle.ACCEPTS[phase].has(Intents.THROW)).is_equal(in_round)
		for player: PlayerState in [living, downed, dead, host, null]:
			var peer := 1 if player == host else 4
			var expected := "not_accepted"
			if in_round and (player == living or player == host):
				expected = "empty_hand"
			for facing: Vector3 in ChaosFrames.THROW_FACINGS:
				var answer := ChaosOracle.answer(
					Intents.THROW, {"facing": facing}, peer, phase, player, 0
				)
				(
					assert_str(str(answer))
					. override_failure_message("%s %s %s" % [phase, peer, facing])
					. is_equal(expected)
				)


func test_the_oracle_leaves_a_throw_with_a_held_item_to_the_check() -> void:
	# A living player holding an item could throw it: the hostile never sends that ("?").
	var holder := PlayerState.new(4, "Player4")
	holder.held_item = 0
	var answer := ChaosOracle.answer(
		Intents.THROW, {"facing": Vector3.FORWARD}, 4, &"round", holder, 0
	)
	assert_str(str(answer)).is_equal("?")


func test_the_hostile_throws_with_each_facing_and_only_those() -> void:
	var hostile := ChaosHostile.new(null, null, WireSchema.game(true), Callable(), null, 188001)
	var seen: Dictionary[Vector3, int] = {}
	for _i in 64:
		var facing: Vector3 = hostile._args_of(Intents.THROW, &"round")["facing"]
		(
			assert_bool(ChaosFrames.THROW_FACINGS.has(facing))
			. override_failure_message(str(facing))
			. is_true()
		)
		seen[facing] = seen.get(facing, 0) + 1
	assert_int(seen.size()).is_equal(ChaosFrames.THROW_FACINGS.size())


func test_the_oracle_names_a_hostile_that_took_the_number_of_the_key_it_borrowed() -> void:
	var key := ScenarioBot.key_of(ChaosScenario.KEY_BOT)
	var state := MatchState.new(1)
	# Peers 1-3 join with their own keys, then the hostile (peer 9) with bot 2's (#639).
	for peer: int in [1, 2, 3, 9]:
		var player := PlayerState.new(peer, "")
		player.number = state.give_number(key if peer == 9 else ScenarioBot.key_of(peer))
		state.players[peer] = player
	assert_int(state.players[9].number).is_equal(4)
	assert_array(ChaosOracle.key_problems(state, 9, 2, key)).is_empty()
	state.players[9].number = 2
	var found := ChaosOracle.key_problems(state, 9, 2, key)
	assert_array(found).has_size(2)
	assert_str(found[0]).contains("the hostile peer holds number 2")
	state.players[9].number = 4
	state.numbers[ScenarioBot.key_of(7)] = 4
	found = ChaosOracle.key_problems(state, 9, 2, key)
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("number 4 is bound to a key")
	state.numbers.erase(ScenarioBot.key_of(7))
	state.players[2].number = 5
	found = ChaosOracle.key_problems(state, 9, 2, key)
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("the honest bot holds number 5, its key binds 2")
	# A hostile that is no player at the end has nothing to check: that is named, not passed.
	state.players[2].number = 2
	state.players.erase(9)
	found = ChaosOracle.key_problems(state, 9, 2, key)
	assert_array(found).has_size(1)
	assert_str(found[0]).contains("the hostile peer is no player at the end")
