extends GdUnitTestSuite
## The channel primitive (ARCHITECTURE §9.2, §9.4; M4-4): an action that takes time. Its rule's
## conditions are checked at the start and again every tick (not its costs), ChannelTicks advances
## it and completes it in the tick that reaches its time, and an applied action of its actor, a
## hit, a knockdown, a death or a leave stops it. Driven by FixtureChannel (1 s, 20 ticks) on the
## mode's Use with an empty hand, in FixtureItemModes.basic() (PickUp and PutDown from the living).

const P1 := 1
const P2 := 2
const HERE := Vector3.ZERO
const TICKS := 20


func test_a_channel_completes_in_the_tick_that_reaches_its_time() -> void:
	var game := _round()
	_use(game, P1)
	var started_at := game.ticked_through() + 1
	var channel := Channels.of_actor(game.state, P1)
	assert_int(channel.started_tick).is_equal(started_at)
	assert_int(channel.total_ticks).is_equal(TICKS)
	FixtureModes.run_ticks(game, TICKS - 1)
	assert_array(FixtureModes.notes(game)).is_equal(["started 1"])
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal(["started 1", "completed 1 after 20"])
	assert_object(Channels.of_actor(game.state, P1)).is_null()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_condition_that_fails_on_a_later_tick_stops_it() -> void:
	var game := _round()
	_use(game, P1)
	FixtureModes.run_ticks(game, 5)
	game.state.set_counter(0, &"halt", 1)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal(["started 1", "stopped 1 after 5"])
	assert_object(Channels.of_actor(game.state, P1)).is_null()


func test_its_costs_are_paid_once_and_not_checked_again() -> void:
	var game := _round(true)
	_use(game, P1)
	FixtureModes.run_ticks(game, TICKS)
	# The cooldown (5 s) it paid at the start would refuse it on every later tick.
	assert_array(FixtureModes.notes(game)).is_equal(["started 1", "completed 1 after 20"])


func test_one_channel_per_actor_a_second_start_is_busy_and_stops_nothing() -> void:
	var game := _round()
	_use(game, P1)
	FixtureModes.run_ticks(game, 3)
	_use(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"busy"])
	FixtureModes.run_ticks(game, TICKS - 3)
	assert_array(FixtureModes.notes(game)).is_equal(["started 1", "completed 1 after 20"])


func test_two_actors_run_their_own_channels_and_end_in_actor_order() -> void:
	var game := _round()
	_use(game, P2)
	_use(game, P1)
	FixtureModes.run_ticks(game, TICKS)
	assert_array(FixtureModes.notes(game)).is_equal(
		["started 2", "started 1", "completed 1 after 20", "completed 2 after 20"]
	)


func test_an_applied_action_of_its_actor_stops_it_first() -> void:
	var game := _round()
	var package := FixtureItemModes.lay(game, &"package", HERE)
	_use(game, P1)
	FixtureModes.run_ticks(game, 4)
	var seen := game.view_of(P2).events.size()
	FixtureItemModes.pick_up(game, P1, package)
	assert_array(FixtureItemModes.names_after(game, P2, seen)).is_equal(
		[&"FixtureNote", &"ItemPickedUp"]
	)
	assert_array(FixtureModes.notes(game)).is_equal(["started 1", "stopped 1 after 4"])


func test_a_refused_action_of_its_actor_stops_nothing() -> void:
	var game := _round()
	_use(game, P1)
	FixtureModes.run_ticks(game, 4)
	FixtureItemModes.put_down(game, P1, Vector3.FORWARD)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"empty_hand"])
	assert_object(Channels.of_actor(game.state, P1)).is_not_null()


func test_another_players_action_stops_nothing() -> void:
	var game := _round()
	var package := FixtureItemModes.lay(game, &"package", HERE)
	_use(game, P1)
	FixtureItemModes.pick_up(game, P2, package)
	FixtureModes.run_ticks(game, TICKS)
	assert_array(FixtureModes.notes(game)).is_equal(["started 1", "completed 1 after 20"])


func test_its_actor_leaving_stops_it() -> void:
	var game := _round()
	_use(game, P1)
	FixtureModes.run_ticks(game, 2)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	assert_array(FixtureModes.notes(game)).is_equal(
		["started 1", "stopped 1 after 2", "task player_left"]
	)
	assert_object(Channels.of_actor(game.state, P1)).is_null()


func test_a_channel_without_channel_ticks_never_advances_and_reset_match_clears_it() -> void:
	var game := _round()
	game.mode.find_phase(&"round").tick_systems = []
	_use(game, P1)
	FixtureModes.run_ticks(game, TICKS * 2)
	assert_array(FixtureModes.notes(game)).is_equal(["started 1"])
	game.state.reset_match()
	assert_array(Channels.running(game.state)).is_empty()


func test_a_channel_ended_in_the_tick_by_an_earlier_ones_end_is_skipped() -> void:
	var game := _round(false, FixtureStoppingChannel.stopping(1.0))
	_use(game, P1)
	_use(game, P2)
	FixtureModes.run_ticks(game, TICKS)
	# P1's completes first (actor-id order) and stops P2's, which then neither runs on nor ends
	# a second time in that tick.
	assert_array(FixtureModes.notes(game)).is_equal(
		["started 1", "started 2", "completed 1 after 20", "stopped 2 after 19"]
	)
	assert_array(Channels.running(game.state)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_swap_refused_for_a_two_handed_item_stops_nothing() -> void:
	var game := _round(false, null, true)
	var package := FixtureItemModes.lay(game, &"package", HERE)
	FixtureItemModes.pick_up(game, P1, package)
	_use(game, P1)
	FixtureModes.run_ticks(game, 3)
	FixtureItemModes.swap(game, P1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([HandNotTwoHanded.TWO_HANDED])
	# Refused by the condition, before the channel stops: not by the swap's own guard after it.
	assert_object(Channels.of_actor(game.state, P1)).is_not_null()
	assert_array(FixtureModes.notes(game)).is_equal(["started 1"])
	assert_array(Array(game.diagnostics)).is_empty()


## A round of FixtureItemModes.basic() whose mode's Use (from the living, with an empty hand)
## starts `effect` (a FixtureChannel of 1 s when null), under ChannelFree and "peer 0's counter
## `halt` below 1" (checked every tick); `cooldown`: also a Cooldown of 5 s; `swap`: the mode has
## the base mode's Swap (FixtureItemModes.swapping). Round lists ChannelTicks.
func _round(cooldown: bool = false, effect: ChannelEffect = null, swap: bool = false) -> Match:
	var mode := FixtureItemModes.basic()
	if swap:
		mode = FixtureItemModes.swapping(mode)
	var halt := FixtureCounterAtLeast.of(&"halt")
	halt.negate = true
	var conditions: Array[Condition] = [ChannelFree.new(), halt]
	if cooldown:
		conditions.append(FixtureCombatModes.cooldown(&"hold", 5.0))
	var channel: ChannelEffect = effect if effect != null else FixtureChannel.of(1.0)
	mode.actions.append(FixtureModes.rule(Intents.USE, conditions, [channel]))
	mode.find_phase(&"round").tick_systems.append(ChannelTicks.new())
	var game := FixtureItemModes.in_round(mode, [P1, P2])
	FixtureItemModes.stand(game, P1, HERE)
	FixtureItemModes.stand(game, P2, HERE + Vector3(1, 0, 0))
	return game


func _use(game: Match, peer: int) -> void:
	FixtureModes.send(game, Intents.USE, peer, {"facing": Vector3.FORWARD})
