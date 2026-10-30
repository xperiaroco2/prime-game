extends GdUnitTestSuite
## The hand-over offer (#1389, #1434; ARCHITECTURE §7.1, §9.4; GDD §6 "Handing over"), driven by
## HandOver commands through a seeded Match: the item stays in the giver's hand and everyone gets
## OfferMade; every refusal goes to the sender alone with its reason, and nothing moves. The take
## and the offer's ends: take_offer_test.gd.

const P1 := 1
const P2 := 2
const P3 := 3
const NOBODY := 999
const NEAR := Vector3(0, 0, 1.5)
const FAR := Vector3(0, 0, 30)


func test_a_hand_over_only_opens_an_offer_and_everyone_sees_it() -> void:
	var game := _game()
	var gift := FixtureHandOverModes.hold(game, P1, &"gift")
	var before := FixtureHandOverModes.signature(game)
	var seen := _counts(game)
	FixtureHandOverModes.hand_over(game, P1, P2)
	for peer: int in [P1, P2, P3]:
		var names := FixtureItemModes.names_after(game, peer, seen[peer])
		assert_array(names).override_failure_message(str(peer)).is_equal([&"OfferMade"])
		var made: OfferMadeEvent = game.view_of(peer).events_named(&"OfferMade").back()
		assert_int(made.giver).is_equal(P1)
		assert_int(made.target).is_equal(P2)
	assert_str(FixtureHandOverModes.signature(game)).is_equal(before)
	assert_int(gift.holder).is_equal(P1)
	assert_int(game.state.player(P1).held_item).is_equal(gift.id)
	var offer := Offers.live(game.state, P1)
	assert_object(offer).is_not_null()
	assert_int(offer.target).is_equal(P2)
	assert_int(offer.item).is_equal(gift.id)
	assert_array(Array(game.diagnostics)).is_empty()


func test_any_item_kind_may_be_offered() -> void:
	for kind_id: StringName in [&"tool", &"package", &"cup"]:
		var game := _game()
		FixtureHandOverModes.hold(game, P1, kind_id)
		FixtureHandOverModes.hand_over(game, P1, P2)
		assert_object(Offers.live(game.state, P1)).override_failure_message(kind_id).is_not_null()


func test_an_empty_hand_is_refused_even_with_a_belt_item() -> void:
	var game := _game()
	_refused(game, P2, HoldsItem.EMPTY_HAND)
	FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureItemModes.swap(game, P1)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	_refused(game, P2, HoldsItem.EMPTY_HAND)


func test_a_second_offer_while_one_is_open_is_not_allowed() -> void:
	var game := _game()
	FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureItemModes.stand(game, P3, Vector3(1.5, 0, 0))
	FixtureHandOverModes.hand_over(game, P1, P2)
	_refused(game, P3, RejectReasons.NOT_ALLOWED)
	assert_int(Offers.live(game.state, P1).target).is_equal(P2)


func test_the_receiver_must_be_another_living_standing_present_player() -> void:
	var game := _game()
	FixtureHandOverModes.hold(game, P1, &"gift")
	_refused(game, P1, RejectReasons.BAD_ARGS)
	_refused(game, 0, TargetLiving.NOT_LIVING)
	_refused(game, NOBODY, TargetLiving.NOT_LIVING)
	for life: PlayerState.Life in [
		PlayerState.Life.DOWNED, PlayerState.Life.DEAD, PlayerState.Life.LEFT
	]:
		game.state.player(P2).life = life
		_refused(game, P2, TargetLiving.NOT_LIVING)
	game.state.player(P2).life = PlayerState.Life.ALIVE
	FixtureHandOverModes.make_limp(game, P2)
	_refused(game, P2, TargetLiving.NOT_LIVING)


func test_the_receiver_must_be_in_reach_and_in_sight() -> void:
	var game := _game()
	FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureItemModes.stand(game, P2, Vector3(0, 0, FixtureHandOverModes.REACH_M + 0.1))
	_refused(game, P2, TargetInReach.OUT_OF_REACH)
	var walled := FlatWorldQuery.new().add_wall(AABB(Vector3(-2, 0, 0.7), Vector3(4, 3, 0.1)))
	var behind := _game(walled)
	FixtureHandOverModes.hold(behind, P1, &"gift")
	_refused(behind, P2, TargetInSight.BLOCKED)


func test_a_waist_high_counter_does_not_block_it_when_the_sight_aims_at_the_eye() -> void:
	var counter := AABB(Vector3(-2, 0, 0.7), Vector3(4, 1, 0.1))
	var game := _game(FlatWorldQuery.new().add_wall(counter))
	FixtureHandOverModes.hold(game, P1, &"gift")
	FixtureHandOverModes.hand_over(game, P1, P2)
	assert_object(Offers.live(game.state, P1)).is_not_null()
	# The raise's sight (at the feet) is blocked by the same counter.
	var low := FixtureHandOverModes.basic()
	for rule: Rule in low.actions:
		if rule.trigger == Intents.HAND_OVER:
			rule.conditions[4].set(&"at_eye", false)
	var feet := _game(FlatWorldQuery.new().add_wall(counter), low)
	FixtureHandOverModes.hold(feet, P1, &"gift")
	_refused(feet, P2, TargetInSight.BLOCKED)


func test_a_phase_without_the_accept_row_and_a_dead_or_limp_sender_are_not_accepted() -> void:
	var mode := FixtureHandOverModes.basic()
	var round_spec := mode.find_phase(&"round")
	for accept: AcceptSpec in round_spec.accepts.duplicate():
		if accept.intent == Intents.HAND_OVER:
			round_spec.accepts.erase(accept)
	var game := _game(null, mode)
	FixtureHandOverModes.hold(game, P1, &"gift")
	_refused(game, P2, RejectReasons.NOT_ACCEPTED)
	var dead := _game()
	FixtureHandOverModes.hold(dead, P1, &"gift")
	dead.state.player(P1).life = PlayerState.Life.DEAD
	_refused(dead, P2, RejectReasons.NOT_ACCEPTED)
	var limp := _game()
	FixtureHandOverModes.hold(limp, P1, &"gift")
	FixtureHandOverModes.make_limp(limp, P1)
	_refused(limp, P2, RejectReasons.NOT_ACCEPTED)


func test_an_applied_hand_over_stops_the_senders_raise() -> void:
	# Any applied action of a raiser stops its raise (RuleRunner, M4-4): RaiseStopped, then the offer.
	var game := _raising()
	var seen := game.view_of(P1).events.size()
	FixtureHandOverModes.hand_over(game, P3, P1)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"OfferMade"]
	)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_refused_hand_over_does_not_stop_the_raise() -> void:
	var game := _raising()
	FixtureHandOverModes.hand_over(game, P3, P3)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([RejectReasons.BAD_ARGS])
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	assert_array(game.view_of(P1).events_named(&"RaiseStopped")).is_empty()


func test_the_offer_is_deterministic_for_a_seed() -> void:
	var logs: Array[String] = []
	for i in 2:
		var game := _game()
		FixtureHandOverModes.hold(game, P2, &"tool")
		FixtureHandOverModes.hold(game, P1, &"gift")
		FixtureHandOverModes.hand_over(game, P1, P2)
		FixtureHandOverModes.take_offer(game, P2, P1)
		logs.append(str(game.view_of(P3).event_names()) + FixtureHandOverModes.signature(game))
	assert_str(logs[0]).is_equal(logs[1])


## The hand-over mode in the round with P1 at the origin, P2 1.5 m away and P3 far off.
func _game(world: WorldQuery = null, mode: GameMode = null) -> Match:
	var used := mode if mode != null else FixtureHandOverModes.basic()
	var game := FixtureItemModes.in_round(used, [P1, P2, P3], world)
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, NEAR)
	FixtureItemModes.stand(game, P3, FAR)
	return game


## P1 armed at the origin downs P2 (1 m north), and P3 (1.8 m from P1), holding a gift (taken
## before the raise, as a take would stop it), starts raising P2.
func _raising() -> Match:
	var mode := FixtureHandOverModes.handing(
		FixtureItemModes.swapping(FixtureCombatModes.raising())
	)
	var game := FixtureCombatModes.in_round(mode, [P1, P2, P3])
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(1.5, 0, 1))
	FixtureHandOverModes.hold(game, P3, &"gift")
	FixtureCombatModes.use(game, P1, Vector3(0, 0, 1))
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, Vector3(0, 0, 1))
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	FixtureCombatModes.raise(game, P3, P2)
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	return game


## A HandOver from P1 to `target` is refused with `reason` to P1 alone, and nothing moves.
func _refused(game: Match, target: int, reason: StringName) -> void:
	var before := FixtureHandOverModes.signature(game)
	var seen := _counts(game)
	FixtureHandOverModes.hand_over(game, P1, target)
	var label := "%d %s" % [target, reason]
	(
		assert_array(FixtureItemModes.names_after(game, P1, seen[P1]))
		. override_failure_message(label)
		. is_equal([&"Rejected"])
	)
	assert_array(FixtureModes.rejections(game, P1).slice(-1)).is_equal([reason])
	for peer: int in [P2, P3]:
		assert_array(FixtureItemModes.names_after(game, peer, seen[peer])).is_empty()
	assert_str(FixtureHandOverModes.signature(game)).override_failure_message(label).is_equal(
		before
	)
	assert_array(Array(game.diagnostics)).is_empty()


func _counts(game: Match) -> Dictionary[int, int]:
	var counts: Dictionary[int, int] = {}
	for peer: int in [P1, P2, P3]:
		counts[peer] = game.view_of(peer).event_names().size()
	return counts
