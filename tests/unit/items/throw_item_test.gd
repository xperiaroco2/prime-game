extends GdUnitTestSuite
## The Throw intent and ThrowItem (ARCHITECTURE §7.1.16, §9.4; the throwing ADR, TE4): the host
## takes only the facing, launches the hand item from its own eye with the rule's numbers, tells
## everyone with ItemThrown, and refuses what is not a throw, each refusal to the sender alone.
## Driven by commands through a seeded match of FixtureThrowModes.basic() (10 m/s, 9.8 m/s²,
## radius 0.15 m, 3 s; the eye 1.6 m above the floor) on a flat floor at 0.

const P1 := 1
const P2 := 2
const P3 := 3
const HERE := Vector3(1, 0, 2)
const AHEAD := Vector3(0, 1.8, -2.4)
## A unit facing other than any test's claim: the last accepted claim's.
const LAST := Vector3(0.6, 0, -0.8)


func test_a_throw_launches_the_hand_item_from_the_eye_along_the_facing() -> void:
	var game := _round()
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, AHEAD)
	var launch := game.ticked_through() + 1
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	assert_int(item.holder).is_equal(0)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	var flight := item.flight
	assert_vector(flight.origin).is_equal(Vector3(1, 1.6, 2))
	assert_vector(flight.velocity).is_equal(AHEAD.normalized() * 10.0)
	assert_vector(flight.gravity).is_equal(Vector3(0, -9.8, 0))
	assert_vector(flight.fallback).is_equal(Vector3(1, 0, 2))
	assert_int(flight.thrower).is_equal(P1)
	assert_float(flight.radius).is_equal(0.15)
	assert_int(flight.max_ticks).is_equal(60)
	assert_int(flight.launch_tick).is_equal(launch)
	var expected := {
		"item": item.id,
		"peer": P1,
		"origin": flight.origin,
		"velocity": flight.velocity,
		"gravity": flight.gravity,
		"tick": launch,
	}
	for peer: int in [P1, P2, P3]:
		var seen := FixtureThrowModes.thrown_seen_by(game, peer)
		assert_array(seen).has_size(1)
		assert_dict(seen[0].to_dict()).is_equal(expected)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_throwers_own_velocity_is_not_added() -> void:
	var game := _round()
	var item := FixtureFlightModes.holding(game, P1, HERE)
	game.state.player(P1).velocity = Vector3(30, 5, -30)
	FixtureThrowModes.throw(game, P1, AHEAD)
	assert_vector(item.flight.velocity).is_equal(AHEAD.normalized() * 10.0)


func test_a_jump_does_not_raise_the_origin() -> void:
	# The last accepted position is 1.5 m above the floor (a jump): the eye stays the floor's.
	var game := _round()
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureItemModes.stand(game, P1, HERE + Vector3(0, 1.5, 0))
	FixtureThrowModes.throw(game, P1, AHEAD)
	assert_vector(item.flight.origin).is_equal(Vector3(1, 1.6, 2))


func test_a_facing_that_is_not_a_unit_vector_takes_the_last_claims() -> void:
	# Not finite, zero, absent, or a finite one whose squared length under- or overflows in single
	# precision: each normalizes to no unit vector.
	var claims: Array[Variant] = [
		Vector3.ZERO,
		Vector3(NAN, 0, 0),
		Vector3(INF, 0, 0),
		Vector3(0, -INF, 1),
		Vector3(1e-30, 0, 0),
		Vector3(1e38, 0, 0),
		Vector3(-1e-30, 1e-30, 0),
		null,
	]
	for claim: Variant in claims:
		var game := _round()
		var item := FixtureFlightModes.holding(game, P1, HERE)
		game.state.player(P1).facing = LAST
		var args := {} if claim == null else {"facing": claim}
		FixtureModes.send(game, Intents.THROW, P1, args)
		assert_vector(item.flight.velocity).override_failure_message("claim %s" % [claim]).is_equal(
			LAST * 10.0
		)
	# The control: a finite facing far from 1 in length that normalizes is taken as claimed.
	var big := _round()
	var thrown := FixtureFlightModes.holding(big, P1, HERE)
	big.state.player(P1).facing = LAST
	FixtureThrowModes.throw(big, P1, Vector3(0, 3e10, -4e10))
	assert_vector(thrown.flight.velocity).is_equal(Vector3(0, 3e10, -4e10).normalized() * 10.0)


func test_unit_facing_takes_a_unit_vector_only() -> void:
	assert_vector(ThrowItem.unit_facing(Vector3(3, 0, 4), LAST)).is_equal(Vector3(0.6, 0, 0.8))
	assert_vector(ThrowItem.unit_facing(Vector3.UP, LAST)).is_equal(Vector3.UP)
	assert_vector(ThrowItem.unit_facing(Vector3(1e-10, 0, 0), LAST)).is_equal_approx(
		Vector3.RIGHT, Vector3(1e-6, 1e-6, 1e-6)
	)
	assert_vector(ThrowItem.unit_facing(Vector3(1e-30, 0, 0), LAST)).is_equal(LAST)
	assert_vector(ThrowItem.unit_facing(Vector3(1e38, 0, 0), LAST)).is_equal(LAST)
	assert_vector(ThrowItem.unit_facing(Vector3(NAN, 1, 0), LAST)).is_equal(LAST)
	assert_vector(ThrowItem.unit_facing(Vector3.ZERO, LAST)).is_equal(LAST)


func test_the_dead_host_never_throws_even_under_host() -> void:
	var living_or_host := AcceptSpec.From.LIVING | AcceptSpec.From.HOST
	var game := _round(null, FixtureThrowModes.basic(living_or_host))
	var item := FixtureFlightModes.holding(game, P1, HERE)
	game.state.player(P1).life = PlayerState.Life.DEAD
	FixtureThrowModes.throw(game, P1, AHEAD, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	_assert_still_held(game, P1, item)
	# The control: the same phase takes it from the living host.
	game.state.player(P1).life = PlayerState.Life.ALIVE
	FixtureThrowModes.throw(game, P1, AHEAD, 6)
	assert_int(item.where).is_equal(ItemState.Where.FLYING)


func test_a_downed_player_cannot_throw() -> void:
	var game := _round()
	var item := FixtureFlightModes.holding(game, P2, HERE)
	game.state.player(P2).life = PlayerState.Life.DOWNED
	FixtureThrowModes.throw(game, P2, AHEAD, 5)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted"])
	_assert_still_held(game, P2, item)


func test_an_empty_hand_is_refused_to_the_sender_only() -> void:
	var game := _round()
	FixtureThrowModes.throw(game, P1, AHEAD, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"empty_hand"])
	assert_array(game.view_of(P2).events_named(&"Rejected")).is_empty()
	assert_array(game.view_of(P2).events_named(&"ItemThrown")).is_empty()


func test_a_belt_item_is_never_thrown() -> void:
	var game := _round(null, FixtureItemModes.swapping(FixtureThrowModes.basic()))
	FixtureItemModes.stand(game, P1, HERE)
	var tool := FixtureItemModes.lay(game, &"tool", HERE)
	FixtureItemModes.pick_up(game, P1, tool)
	FixtureItemModes.swap(game, P1)
	FixtureThrowModes.throw(game, P1, AHEAD, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"empty_hand"])
	assert_int(tool.where).is_equal(ItemState.Where.BELT)
	assert_int(game.state.player(P1).belt_item).is_equal(tool.id)
	assert_array(game.view_of(P1).events_named(&"ItemThrown")).is_empty()


func test_a_phase_that_does_not_accept_it_refuses_it() -> void:
	# The rule is there, but Round does not accept Throw.
	var mode := FixtureItemModes.basic()
	mode.actions.append(FixtureThrowModes.throw_rule(FixtureThrowModes.effect()))
	var game := _round(null, mode)
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, AHEAD, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	_assert_still_held(game, P1, item)


func test_a_thrower_over_no_floor_is_refused_with_no_floor() -> void:
	# Past x = 2 the level has no floor: a jump over a pit, or a client that walked out of the level.
	var game := _round(FixtureFlightWorld.new(0.0, 2.0))
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureItemModes.stand(game, P1, Vector3(5, 0, 2))
	FixtureThrowModes.throw(game, P1, AHEAD, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([OverFloor.NO_FLOOR])
	_assert_still_held(game, P1, item)
	for peer: int in [P2, P3]:
		assert_array(game.view_of(peer).events_named(&"Rejected")).is_empty()
	# The control: back over the floor, the same throw goes.
	FixtureItemModes.stand(game, P1, Vector3(1.9, 0, 2))
	FixtureThrowModes.throw(game, P1, AHEAD, 6)
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	assert_vector(item.flight.fallback).is_equal(Vector3(1.9, 0, 2))


func test_a_refused_throw_stops_no_raise_and_an_applied_one_stops_it() -> void:
	# The mode's Use, with any hand, starts a 1 s channel (the raise's primitive).
	var mode := FixtureThrowModes.basic()
	mode.actions.append(
		FixtureModes.rule(Intents.USE, [ChannelFree.new()], [FixtureChannel.of(1.0)])
	)
	mode.find_phase(&"round").tick_systems.append(ChannelTicks.new())
	var game := _round(FixtureFlightWorld.new(0.0, 2.0), mode)
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureModes.send(game, Intents.USE, P1, {"facing": AHEAD})
	FixtureModes.run_ticks(game, 3)
	FixtureItemModes.stand(game, P1, Vector3(5, 0, 2))
	FixtureThrowModes.throw(game, P1, AHEAD, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([OverFloor.NO_FLOOR])
	assert_object(Channels.of_actor(game.state, P1)).is_not_null()
	FixtureItemModes.stand(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, AHEAD, 6)
	assert_int(item.where).is_equal(ItemState.Where.FLYING)
	assert_object(Channels.of_actor(game.state, P1)).is_null()
	assert_array(FixtureModes.notes(game)).is_equal(["started 1", "stopped 1 after 3"])


func test_the_rule_is_the_hand_kinds_then_the_roles_then_the_modes() -> void:
	var mode := FixtureThrowModes.basic()
	mode.find_item_kind(&"tool").actions.append(
		FixtureThrowModes.throw_rule(FixtureThrowModes.effect(5.0))
	)
	mode.find_role(&"crew").actions = [FixtureThrowModes.throw_rule(FixtureThrowModes.effect(7.0))]
	var speeds: Array[float] = []
	for case: Array in [[&"tool", &"crew"], [&"package", &"crew"], [&"package", &"dissident"]]:
		var game := _round(null, mode)
		game.state.player(P1).role = case[1] as StringName
		FixtureItemModes.stand(game, P1, HERE)
		var item := FixtureItemModes.lay(game, case[0] as StringName, HERE)
		FixtureItemModes.pick_up(game, P1, item)
		FixtureThrowModes.throw(game, P1, Vector3.FORWARD)
		speeds.append(item.flight.velocity.length())
	assert_array(speeds).is_equal([5.0, 7.0, 10.0])


func test_with_no_throw_rule_for_the_hand_it_is_nothing_to_do() -> void:
	# Only the tool kind can be thrown: a package in hand finds no rule.
	var mode := FixtureItemModes.basic()
	mode.find_item_kind(&"tool").actions.append(
		FixtureThrowModes.throw_rule(FixtureThrowModes.effect())
	)
	var round_spec := mode.find_phase(&"round")
	round_spec.accepts.append(AcceptSpec.of(Intents.THROW, AcceptSpec.From.LIVING))
	round_spec.tick_systems.append(FlightTicks.new())
	var game := _round(null, mode)
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, AHEAD, 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"nothing_to_do"])
	_assert_still_held(game, P1, item)


func test_with_no_floor_after_all_the_effect_logs_it_and_throws_nothing() -> void:
	# A rule that forgot OverFloor, which ModeCheck refuses, so run straight through RuleRunner.
	var game := _round(FixtureFlightWorld.new(0.0, 2.0))
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureItemModes.stand(game, P1, Vector3(5, 0, 2))
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.world = FixtureFlightWorld.new(0.0, 2.0)
	ctx.tick = game.ticked_through() + 1
	ctx.actor = P1
	ctx.command = MatchCommand.new(Intents.THROW, P1, ctx.tick, {"facing": AHEAD})
	var rule := FixtureModes.rule(Intents.THROW, [HoldsItem.new()], [FixtureThrowModes.effect()])
	assert_str(String(RuleRunner.run(rule, ctx))).is_empty()
	_assert_still_held(game, P1, item)
	assert_array(game.view_of(P2).events_named(&"ItemThrown")).is_empty()
	assert_bool(game.diagnostics.is_empty()).is_false()
	assert_str(game.diagnostics[game.diagnostics.size() - 1]).contains("no floor below player 1")


func test_a_thrown_package_lands_and_rests_with_the_cause_thrown() -> void:
	var game := _round()
	var item := FixtureFlightModes.holding(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, Vector3(0, 1, -1))
	FixtureModes.run_ticks(game, 60)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)
	for peer: int in [P1, P2, P3]:
		var placed := game.view_of(peer).events_named(&"ItemPlaced")
		assert_array(placed).has_size(1)
		assert_str(String((placed[0] as ItemPlacedEvent).cause)).is_equal(String(Items.THROWN))
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_same_commands_throw_it_the_same_way() -> void:
	var runs: Array[Match] = []
	for i in 2:
		var world := FixtureFlightWorld.new()
		world.add_wall(AABB(Vector3(-1, 0, -4), Vector3(3, 3, 1)))
		var game := _round(world)
		FixtureFlightModes.holding(game, P1, HERE)
		FixtureThrowModes.throw(game, P1, AHEAD)
		FixtureModes.run_ticks(game, 60)
		runs.append(game)
	assert_array(FixtureModes.describe(runs[1])).is_equal(FixtureModes.describe(runs[0]))
	assert_array(runs[1].command_log.world_answers).is_equal(runs[0].command_log.world_answers)
	assert_array(FixtureModes.names(runs[0])).contains([&"ItemThrown", &"ItemPlaced"])


## A round of `mode` (FixtureThrowModes.basic() by default) asking `world` (flat by default),
## with P1, P2 and P3.
func _round(world: WorldQuery = null, mode: GameMode = null) -> Match:
	var game := FixtureItemModes.in_round(
		mode if mode != null else FixtureThrowModes.basic(), [P1, P2, P3], world
	)
	assert_array(Array(game.diagnostics)).is_empty()
	return game


func _assert_still_held(game: Match, peer: int, item: ItemState) -> void:
	assert_int(item.where).is_equal(ItemState.Where.HAND)
	assert_int(game.state.player(peer).held_item).is_equal(item.id)
	for watcher: int in [P1, P2, P3]:
		assert_array(game.view_of(watcher).events_named(&"ItemThrown")).is_empty()
