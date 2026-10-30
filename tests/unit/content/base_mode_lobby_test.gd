extends GdUnitTestSuite
## The base mode's Lobby and Countdown in `content/` (#1388, provisional data): both take Interact,
## PickUp, PutDown, Swap, Draw, Use and UseSecondary from the living, never Throw, Raise,
## StopRaise, GiveUp or Pose; both run LifeTicks (its Respawn on the hall's `lobby_player`
## markers), ChannelTicks and VanishTicks, which ModeCheck demands of those intents mode-wide; the
## `countdown_done` row runs ClearItems, so a package picked up in the hall is gone in Loading and
## never reaches the round.
## The bar (#1390, provisional numbers): both also run StationTicks (the tap, on the hall's `tap`
## marker) and DrunkTicks; `countdown_done` runs ClearStations after ClearItems, and the drunk are
## sober again once placed on the map.
## The hand-over (#1389, provisional; an offer since #1434): the Lobby, the Countdown and the Round
## take HandOver, TakeOffer and CancelOffer from the living and run OfferTicks (5 s, 2 m); the
## HandOver rule holds a negated Offering, reach 2 m and the sight at the eye; every row out of
## those phases runs EndOffers.
## Loads `content/` and the levels on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const GREYBOX := "res://levels/greybox/greybox.tscn"
const P1 := 1
const P2 := 2
const HALL: Array[StringName] = [&"lobby", &"countdown"]
const TAKEN: Array[StringName] = [
	Intents.INTERACT,
	Intents.PICK_UP,
	Intents.PUT_DOWN,
	Intents.SWAP,
	Intents.DRAW,
	Intents.USE,
	Intents.USE_SECONDARY,
	Intents.HAND_OVER,
	Intents.TAKE_OFFER,
	Intents.CANCEL_OFFER,
]
const REFUSED: Array[StringName] = [
	Intents.THROW, Intents.RAISE, Intents.STOP_RAISE, Intents.GIVE_UP, Intents.POSE
]


func test_the_hall_takes_the_hand_the_belt_and_interact_from_the_living() -> void:
	var mode := load(BASE_MODE) as GameMode
	for phase_id: StringName in HALL:
		var spec := mode.find_phase(phase_id)
		for intent: StringName in TAKEN:
			(
				assert_int(spec.senders_of(intent))
				. override_failure_message("%s %s" % [phase_id, intent])
				. is_equal(AcceptSpec.From.LIVING)
			)
		for intent: StringName in REFUSED:
			(
				assert_int(spec.senders_of(intent))
				. override_failure_message("%s %s" % [phase_id, intent])
				. is_equal(0)
			)


func test_the_hall_runs_life_channel_vanish_and_the_bar_s_ticks() -> void:
	var mode := load(BASE_MODE) as GameMode
	for phase_id: StringName in HALL:
		var systems := mode.find_phase(phase_id).tick_systems
		assert_int(systems.size()).is_equal(7)
		assert_object(systems[0]).is_instanceof(LifeTicks)
		assert_object(systems[1]).is_instanceof(ChannelTicks)
		assert_object(systems[2]).is_instanceof(VanishTicks)
		# The bar (#1390): the tap stands in the hall, and the drunk sober up there.
		assert_object(systems[3]).is_instanceof(StationTicks)
		assert_str(String((systems[3] as StationTicks).kind.id)).is_equal("tap")
		assert_object(systems[4]).is_instanceof(DrunkTicks)
		# The limp (#1393): its push and get-up, the base mode's provisional numbers.
		assert_object(systems[5]).is_instanceof(LimpTicks)
		var limp := systems[5] as LimpTicks
		assert_array([limp.reach_m, limp.height_m, limp.min_speed_mps, limp.gain]).is_equal(
			[1.0, 1.8, 0.5, 1.0]
		)
		assert_array([limp.max_speed_mps, limp.cooldown_s]).is_equal([3.0, 0.25])
		var respawn := (systems[0] as LifeTicks).respawn
		assert_object(respawn).is_not_null()
		assert_str(String(respawn.tag)).is_equal("lobby_player")


func test_mode_check_needs_the_hall_s_life_ticks() -> void:
	# The control: without them, Use's Strike and Interact's car repair are refused in the hall.
	var mode := (load(BASE_MODE) as GameMode).duplicate(true) as GameMode
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()
	mode.find_phase(&"lobby").tick_systems = mode.find_phase(&"lobby").tick_systems.slice(1)
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("phase lobby")
	assert_str(errors).contains("LifeTicks")


func test_countdown_done_clears_the_items_and_a_cancel_does_not() -> void:
	var mode := load(BASE_MODE) as GameMode
	for row: Transition in mode.transitions:
		if row.from != &"countdown":
			continue
		if row.outcome == CountdownPhase.COUNTDOWN_DONE:
			# The hall's items, then its tap (#1390), then everyone limp up (#1393), before the map
			# loads.
			assert_int(row.actions.size()).is_equal(4)
			assert_object(row.actions[0]).is_instanceof(ClearItems)
			assert_object(row.actions[1]).is_instanceof(ClearStations)
			assert_object(row.actions[2]).is_instanceof(EndLimps)
			# The hall's hits end with the countdown: everyone back at full health (#1439).
			assert_bool((row.actions[2] as EndLimps).restore_health).is_true()
			assert_object(row.actions[3]).is_instanceof(EndOffers)
		else:
			assert_array(row.actions).is_empty()


func test_too_much_runs_the_limp_reaction() -> void:
	# The base mode's one reaction (#1393): drunk_too_much lays the drinker limp for 6 s
	# (provisional).
	var mode := load(BASE_MODE) as GameMode
	var found: Array[GoLimp] = []
	for rule: Rule in mode.reactions:
		if rule.trigger == Facts.DRUNK_TOO_MUCH:
			for effect: RuleEffect in rule.effects:
				if effect is GoLimp:
					found.append(effect as GoLimp)
	assert_int(found.size()).is_equal(1)
	assert_float(found[0].limp_s).is_equal(6.0)


func test_a_hit_to_zero_in_the_hall_lays_limp_for_the_drinks_time() -> void:
	# #1439: Lobby and Countdown share the drink's GoLimp (one 6 s, provisional) as their hit_limp;
	# every other phase knocks down.
	var mode := load(BASE_MODE) as GameMode
	var drunk: GoLimp = null
	for rule: Rule in mode.reactions:
		if rule.trigger == Facts.DRUNK_TOO_MUCH:
			drunk = rule.effects[0] as GoLimp
	assert_object(drunk).is_not_null()
	for spec: PhaseSpec in mode.phases:
		if spec.id in [&"lobby", &"countdown"]:
			assert_object(spec.hit_limp).is_same(drunk)
		else:
			assert_object(spec.hit_limp).is_null()


func test_a_package_held_in_the_hall_never_reaches_the_round() -> void:
	var mode := load(BASE_MODE) as GameMode
	var game := Match.new(mode, 7, FlatWorldQuery.new(), _layouts_for(mode))
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	var player := game.state.player(P1)
	var at := player.position + Vector3(0, 0, -0.5)
	var package := game.state.add_item(mode.find_item_kind(&"package"), at)
	FixtureModes.send(game, Intents.PICK_UP, P1, {"item": package.id})
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(player.held_item).is_equal(package.id)
	assert_int(package.kind.hands).is_equal(2)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	for i in 200:
		if game.phase_id() != &"countdown":
			break
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("loading")
	assert_bool(game.state.items.is_empty()).is_true()
	assert_int(player.held_item).is_equal(-1)
	var vanished := game.view_of(P2).events_named(&"ItemVanished")
	assert_int(vanished.size()).is_equal(1)
	assert_int((vanished[0] as ItemVanishedEvent).item).is_equal(package.id)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	for i in 200:
		if game.phase_id() == &"round":
			break
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.items.values().has(package)).is_false()
	for peer: int in [P1, P2]:
		assert_int(game.state.player(peer).held_item).is_equal(-1)
	assert_array(Array(game.diagnostics)).is_empty()


## The tap's flood guard (like the cooking boxes' CE17): its pour pays a Cooldown last, so a client
## spamming Interact at the tap gets `too_soon`, not a pour (and its events to everyone) per tick.
func test_the_tap_s_pour_has_a_cooldown_as_its_flood_guard() -> void:
	var mode := load(BASE_MODE) as GameMode
	var taps := Stations.kinds_in(mode).filter(
		func(kind: StationKind) -> bool: return kind.id == &"tap"
	)
	assert_array(taps).has_size(1)
	var pours := (taps[0] as StationKind).actions.filter(
		func(rule: Rule) -> bool: return rule.trigger == Intents.INTERACT
	)
	assert_array(pours).has_size(1)
	var conditions := (pours[0] as Rule).conditions
	assert_object(conditions[0]).is_instanceof(AtStation)
	var guard := conditions[conditions.size() - 1] as Cooldown
	assert_object(guard).is_not_null()
	assert_str(String(guard.key)).is_equal("tap_pour")
	assert_bool(Ticks.from_seconds(guard.seconds) >= 2).is_true()
	var game := Match.new(mode, 7, FlatWorldQuery.new(), _layouts_for(mode))
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	var marker := _layouts_for(mode)[mode.lobby_level].positions(&"tap")[0]
	FixtureItemModes.stand(game, P1, marker + Vector3(0.5, 0, 0.5))
	FixtureBar.pour(game, P1, 1)
	FixtureBar.pour(game, P1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"too_soon"])


func test_the_hall_s_tap_pours_a_beer_that_lasts_into_the_countdown_only() -> void:
	var mode := load(BASE_MODE) as GameMode
	var layouts := _layouts_for(mode)
	var game := Match.new(mode, 7, FlatWorldQuery.new(), layouts)
	assert_array(Array(game.refusals)).is_empty()
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	# The tap stands on the hall's one `tap` marker.
	var tap := FixtureBar.tap_id(game)
	assert_int(tap).is_equal(1)
	var marker := layouts[mode.lobby_level].positions(&"tap")
	assert_int(marker.size()).is_equal(1)
	assert_vector(game.state.stations[tap].position).is_equal(marker[0])
	FixtureItemModes.stand(game, P1, marker[0] + Vector3(0.5, 0, 0.5))
	FixtureBar.pour(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	var mug := Items.held_by(game.state, P1)
	assert_str(String(mug.kind.id)).is_equal("mug")
	# The left button's Use finds no rule on a full mug (#1438): it drinks on UseSecondary only.
	FixtureModes.send(game, Intents.USE, P1, {"facing": Vector3.FORWARD}, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([RejectReasons.NOTHING_TO_DO])
	assert_str(String(mug.kind.id)).is_equal("mug")
	assert_int(game.state.player(P1).drunk).is_equal(0)
	FixtureBar.drink(game, P1, 3)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([RejectReasons.NOTHING_TO_DO])
	assert_str(String(mug.kind.id)).is_equal("mug_empty")
	# One mug: 40 of 100, below the 90 of too much (provisional numbers).
	var drunk := game.state.player(P1).drunk
	assert_int(drunk).is_equal(40)
	var avatars: Dictionary = game.view_of(P2).snapshots[game.ticked_through()]["avatars"]
	assert_int(avatars[P1]["drunk"] as int).is_equal(drunk)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	for i in 200:
		if game.phase_id() != &"countdown":
			break
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("loading")
	# The tap and the empty mug are gone with the hall; the next station is number 1 again.
	assert_bool(game.state.stations.is_empty()).is_true()
	assert_bool(game.state.items.is_empty()).is_true()
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	for i in 200:
		if game.phase_id() == &"round":
			break
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("round")
	assert_int(game.state.player(P1).drunk).is_equal(0)
	assert_bool(game.state.stations.has(1)).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_mug_cap_is_two_per_player_and_one_over() -> void:
	var mode := load(BASE_MODE) as GameMode
	var mug := mode.find_item_kind(&"mug")
	assert_int(mug.max_items).is_equal(2 * mode.max_players + 1)
	assert_array(Array(DispenserCapCheck.problems(mode))).is_empty()
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_four_hoarders_with_three_mugs_each_leave_a_fifth_pour_available() -> void:
	var mode := load(BASE_MODE) as GameMode
	var layouts := _layouts_for(mode)
	var game := Match.new(mode, 7, FlatWorldQuery.new(), layouts)
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	var peers: Array[int] = [P1, P2, 3, 4, 5]
	for peer: int in peers:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	var marker := layouts[mode.lobby_level].positions(&"tap")[0]
	for peer: int in peers:
		FixtureItemModes.stand(game, peer, marker + Vector3(0.2 * peer, 0, 0.5))
	# The hand and the two belt places: three mugs held by each of four players.
	for round_no in 3:
		for peer: int in peers.slice(0, 4):
			FixtureBar.pour(game, peer, round_no + 1)
		FixtureModes.run_ticks(game, Ticks.from_seconds(0.3))
	for peer: int in peers.slice(0, 4):
		assert_array(FixtureModes.rejections(game, peer)).is_empty()
	FixtureBar.pour(game, peers[4], 1)
	assert_array(FixtureModes.rejections(game, peers[4])).is_empty()
	assert_object(Items.held_by(game.state, peers[4])).is_not_null()


func _layouts_for(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var levels := MarkerReader.read_levels(
		mode, FlatWorldQuery.new(), ScenarioLevels.unsnapped(mode)
	)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts


func test_every_held_phase_offers_takes_and_cancels() -> void:
	# The offer (#1434, provisional): a base rule wherever items are held, the Round included.
	var mode := load(BASE_MODE) as GameMode
	for phase_id: StringName in [&"lobby", &"countdown", &"round"]:
		var phase := mode.find_phase(phase_id)
		for intent: StringName in [Intents.HAND_OVER, Intents.TAKE_OFFER, Intents.CANCEL_OFFER]:
			(
				assert_int(phase.senders_of(intent))
				. override_failure_message("%s %s" % [phase_id, intent])
				. is_equal(AcceptSpec.From.LIVING)
			)
		var ticks := phase.tick_systems.filter(func(s: TickSystem) -> bool: return s is OfferTicks)
		assert_int(ticks.size()).is_equal(1)
		(
			assert_array([(ticks[0] as OfferTicks).timeout_s, (ticks[0] as OfferTicks).reach_m])
			. is_equal([5.0, 2.0])
		)
	assert_object(mode.find_phase(&"round").tick_systems.back()).is_instanceof(OfferTicks)
	var classes: Array[Script] = []
	var rule := _rule_of(mode, Intents.HAND_OVER)
	for condition: Condition in rule.conditions:
		classes.append(condition.get_script() as Script)
	# One offer per giver: a negated Offering before the receiver and the geometry.
	assert_array(classes).is_equal(
		[HoldsItem, Offering, TargetLiving, TargetInReach, TargetInSight]
	)
	assert_bool(rule.conditions[1].negate).is_true()
	assert_float((rule.conditions[3] as TargetInReach).reach_m).is_equal(2.0)
	assert_bool((rule.conditions[4] as TargetInSight).at_eye).is_true()
	assert_object(rule.effects[0]).is_instanceof(HandOver)
	rule = _rule_of(mode, Intents.TAKE_OFFER)
	classes.clear()
	for condition: Condition in rule.conditions:
		classes.append(condition.get_script() as Script)
	assert_array(classes).is_equal(TakeOffer.required_conditions())
	assert_float((rule.conditions[2] as TargetInReach).reach_m).is_equal(2.0)
	assert_bool((rule.conditions[3] as TargetInSight).at_eye).is_true()
	assert_object(rule.effects[0]).is_instanceof(TakeOffer)
	rule = _rule_of(mode, Intents.CANCEL_OFFER)
	assert_object(rule.conditions[0]).is_instanceof(Offering)
	assert_bool(rule.conditions[0].negate).is_false()
	assert_object(rule.effects[0]).is_instanceof(CancelOffer)
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_the_rows_out_of_the_offering_phases_end_the_offers() -> void:
	var mode := load(BASE_MODE) as GameMode
	for row: Transition in mode.transitions:
		var ends := row.actions.any(func(a: RuleEffect) -> bool: return a is EndOffers)
		var leaves := (
			[&"lobby", &"countdown", &"round"].has(row.from)
			and not [&"lobby", &"countdown"].has(row.to)
		)
		assert_bool(ends).override_failure_message(String(row.outcome)).is_equal(leaves)


func _rule_of(mode: GameMode, intent: StringName) -> Rule:
	var rules := mode.actions.filter(func(rule: Rule) -> bool: return rule.trigger == intent)
	assert_int(rules.size()).is_equal(1)
	return rules[0]
