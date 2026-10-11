extends GdUnitTestSuite
## The zone task's rules (ZoneTask.tick; ARCHITECTURE §9.5; the zone task ADR §2 and its §4
## interruption table, row by row): a zone counts one tick a tick while a living player with a
## fresh claim (at most 10 host ticks old, ZE10) stands in it, keeps its ticks when nobody does, and
## is done at its time. Driven by MoveClaims, PickUp, PutDown, Swap, Use, Raise and PeerLeft on a
## seeded match whose deal ran; a test puts a player only before its first claim (FixtureZoneModes).

const P1 := 1
const P2 := 2
const A := Vector3(0, 0, 20)
const B := Vector3(3, 0, 20)
const NORTH := Vector3(0, 0, 1)
const EAST := Vector3(1, 0, 0)
const OUTSIDE := Vector3(0, 0, 25)


func test_a_living_player_inside_counts_one_tick_a_tick() -> void:
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 5)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(5)
	assert_bool(FixtureZoneModes.state_of(game).counting[0]).is_true()
	assert_int(FixtureZoneModes.ticks_of(game, 1)).is_equal(0)


func test_a_player_who_never_claimed_does_not_count() -> void:
	# Its position is the host's placement, not a claim (claim_age -1).
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, A)
	FixtureModes.run_ticks(game, 30)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(0)
	assert_array(game.view_of(P1).events_named(&"ZoneProgress")).is_empty()


func test_walking_out_pauses_and_keeps_the_ticks_and_walking_back_goes_on() -> void:
	# A push moves a player out the same way: the zone reads only the accepted claim.
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 4)
	var edge := A + EAST * 1.5
	var inside_steps := FixtureZoneModes.walk(game, P1, edge)
	var at_edge := FixtureZoneModes.ticks_of(game, 0)
	assert_int(at_edge).is_equal(4 + inside_steps)
	FixtureZoneModes.walk(game, P1, edge + EAST * 0.2)
	FixtureZoneModes.hold(game, [P1], 10)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(at_edge)
	assert_bool(FixtureZoneModes.state_of(game).counting[0]).is_false()
	FixtureZoneModes.walk(game, P1, edge)
	FixtureZoneModes.hold(game, [P1], 3)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(at_edge + 4)


func test_a_jump_above_the_height_stops_it_and_a_landing_inside_counts_again() -> void:
	var mode := FixtureZoneModes.basic(2)
	FixtureZoneModes.zone_task_of(mode).zone.height_m = 0.5
	var game := FixtureZoneModes.in_round(mode, [P1])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 3)
	var corrected := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.claim(game, P1, A + Vector3(0, 0.8, 0), FixtureMoves.jumped(game, P1))
	FixtureModes.run_ticks(game, 1)
	assert_float(game.state.player(P1).position.y).is_equal_approx(0.8, 1e-4)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(3)
	FixtureMoves.claim(game, P1, A + Vector3(0, 0.4, 0), {"on_floor": false})
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(4)
	FixtureMoves.claim(game, P1, A)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(5)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(corrected)


func test_a_hit_that_does_not_knock_down_changes_nothing_and_a_knockdown_stops_it_at_once() -> void:
	var game := _round([P1, P2])
	FixtureZoneModes.put(game, P1, A)
	FixtureCombatModes.arm(game, P2, A - NORTH)
	FixtureZoneModes.hold(game, [P1], 3)
	var sent := FixtureZoneModes.progress(game, P1).size()
	FixtureCombatModes.use(game, P2, NORTH)
	FixtureZoneModes.hold(game, [P1], 1)
	assert_float(FixtureCombatModes.health(game, P1)).is_equal(50.0)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(4)
	assert_int(FixtureZoneModes.progress(game, P1).size()).is_equal(sent)
	FixtureZoneModes.hold(game, [P1], FixtureCombatModes.COOLDOWN_TICKS - 1)
	var ticks_before := FixtureZoneModes.ticks_of(game, 0)
	assert_int(ticks_before).is_equal(3 + FixtureCombatModes.COOLDOWN_TICKS)
	# The second hit's command and LifeTicks run before TaskTicks: the knockdown tick gains nothing.
	FixtureMoves.claim(game, P1, A)
	FixtureCombatModes.use(game, P2, NORTH)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(ticks_before)
	var stopped := FixtureZoneModes.progress(game, P2).back() as Dictionary
	assert_dict(stopped).is_equal(
		FixtureZoneModes.sent(_zone_id(game, 0), ticks_before, false, game.ticked_through())
	)
	# Downed, then dead: it never counts again.
	FixtureZoneModes.hold(game, [P1], 5)
	FixtureWinModes.run_out(game, P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DEAD)
	FixtureModes.run_ticks(game, 20)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(ticks_before)


func test_a_player_who_leaves_stops_it() -> void:
	var game := _round([P1, P2])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 6)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureModes.run_ticks(game, 10)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(6)
	assert_bool(FixtureZoneModes.state_of(game).counting[0]).is_false()


func test_a_downed_player_crawling_in_does_not_count_and_counts_once_raised() -> void:
	# P1 is knocked down just outside zone A and crawls in; P2 stands in zone B, which counts on
	# while P2 raises P1 (a raise changes nothing); zone A counts from the tick P1 is living again.
	var game := FixtureZoneModes.in_round(FixtureZoneModes.basic(2, 10.0), [P1, P2])
	var start := A + Vector3(1.2, 0, -1)
	FixtureZoneModes.put(game, P1, start)
	FixtureCombatModes.arm(game, P2, start - NORTH)
	FixtureZoneModes.hold(game, [P1], 1)
	FixtureCombatModes.use(game, P2, NORTH)
	FixtureZoneModes.hold(game, [P1], FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P2, NORTH)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DOWNED)
	FixtureZoneModes.walk(game, P1, A + EAST * 1.2, [], 0.04)
	FixtureZoneModes.hold(game, [P1], 5)
	assert_bool(game.state.stations[_zone_id(game, 0)].contains(game.state.player(P1).position))
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(0)
	FixtureZoneModes.walk(game, P2, B - EAST * 0.2, [P1])
	var b_before := FixtureZoneModes.ticks_of(game, 1)
	FixtureCombatModes.raise(game, P2, P1)
	var held := 0
	while not game.state.player(P1).is_alive() and held < 200:
		FixtureZoneModes.hold(game, [P1, P2])
		held += 1
	assert_bool(game.state.player(P1).is_alive()).is_true()
	assert_int(FixtureZoneModes.ticks_of(game, 1)).is_equal(b_before + held)
	# Revived in ChannelTicks, before TaskTicks: the revive's tick counts.
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(1)
	FixtureZoneModes.hold(game, [P1, P2], 4)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(5)


func test_a_respawn_inside_counts_from_its_first_claim() -> void:
	# Built behaviour (ZE10 with the epoch): a respawn is a placement, so its position is the host's
	# until the player's first claim in the new epoch, about a round trip later.
	# Each zone 0.5 m beside a respawn marker (a marker holds one tag): a respawn lands inside one.
	var spots: Array[Vector3] = []
	for spot: Vector3 in FixtureModes.RESPAWNS:
		spots.append(spot + EAST * 0.5)
	var found := FixtureZoneModes.layouts(spots)
	var game := FixtureZoneModes.in_round(FixtureZoneModes.basic(3), [P1, P2], found)
	var far := Vector3(40, 0, 40)
	FixtureZoneModes.put(game, P1, far)
	FixtureCombatModes.arm(game, P2, far - NORTH)
	FixtureCombatModes.use(game, P2, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P2, NORTH)
	FixtureWinModes.run_out(game, P1)
	assert_int(game.state.player(P1).life).is_equal(PlayerState.Life.DEAD)
	while game.state.player(P1).life != PlayerState.Life.ALIVE and game.ticked_through() < 5000:
		FixtureModes.run_ticks(game, 1)
	assert_bool(FixtureModes.RESPAWNS.has(game.state.player(P1).position)).is_true()
	FixtureModes.run_ticks(game, 5)
	assert_array(Array(FixtureZoneModes.state_of(game).ticks)).is_equal([0, 0, 0])
	FixtureZoneModes.hold(game, [P1], 3)
	var counted := Array(FixtureZoneModes.state_of(game).ticks)
	counted.sort()
	assert_array(counted).is_equal([0, 0, 3])


func test_carrying_using_swapping_and_putting_down_inside_change_nothing() -> void:
	var mode := FixtureItemModes.swapping(FixtureZoneModes.basic(2))
	var game := FixtureZoneModes.in_round(mode, [P1])
	FixtureZoneModes.put(game, P1, A)
	var tool := FixtureItemModes.lay(game, &"tool", A + EAST * 0.5)
	FixtureZoneModes.hold(game, [P1], 2)
	var sent := FixtureZoneModes.progress(game, P1).size()
	FixtureItemModes.pick_up(game, P1, tool)
	FixtureZoneModes.hold(game, [P1], 1)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureZoneModes.hold(game, [P1], 1)
	FixtureItemModes.swap(game, P1)
	FixtureZoneModes.hold(game, [P1], 1)
	FixtureItemModes.swap(game, P1)
	FixtureZoneModes.hold(game, [P1], 1)
	FixtureItemModes.put_down(game, P1, EAST)
	FixtureZoneModes.hold(game, [P1], 1)
	assert_int(tool.where).is_equal(ItemState.Where.GROUND)
	assert_array(FixtureModes.notes(game)).contains(["tool used"])
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(7)
	assert_int(FixtureZoneModes.progress(game, P1).size()).is_equal(sent)


func test_two_players_inside_count_one_tick_a_tick_and_one_leaving_changes_nothing() -> void:
	var game := _round([P1, P2])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.put(game, P2, A + EAST)
	FixtureZoneModes.hold(game, [P1, P2], 5)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(5)
	var sent := FixtureZoneModes.progress(game, P1).size()
	var steps := FixtureZoneModes.walk(game, P2, A + Vector3(1, 0, -2), [P1])
	FixtureZoneModes.hold(game, [P1, P2], 3)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(5 + steps + 3)
	assert_int(FixtureZoneModes.progress(game, P1).size()).is_equal(sent)


func test_a_frozen_client_counts_10_ticks_after_its_last_claim_and_its_credit_buys_no_more(
) -> void:
	# The freeze row: 200 silent ticks inside, then one claim that spends the stored credit to walk
	# 20 m away. The zone counts while the claim is at most 10 host ticks old: ages 1 to 10 after
	# the tick of the last claim, not age 11.
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 5)
	var last := game.ticked_through()
	var ticks_before := FixtureZoneModes.ticks_of(game, 0)
	FixtureModes.run_ticks(game, 10)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(ticks_before + 10)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(ticks_before + 10)
	FixtureModes.run_ticks(game, 189)
	var corrected := FixtureMoves.corrections(game, P1).size()
	FixtureMoves.claim(game, P1, A + EAST * 20, {"client_tick": last + 200})
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(corrected)
	assert_vector(game.state.player(P1).position).is_equal(A + EAST * 20)
	FixtureZoneModes.hold(game, [P1], 5)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(ticks_before + 10)


func test_a_slow_claimer_counts_while_it_stores_at_most_10_ticks_and_its_credit_buys_no_more(
) -> void:
	# The drip (the netcode review of #647): a claim every 10 host ticks covering one client tick
	# keeps the claim young but stores 9 ticks of credit each time. The zone counts the first
	# claim's tick and the 9 after it (stored 0 to 9), the second claim's tick (9) and the next (10),
	# and nothing once 11 are stored: 12 ticks, not the 220 the drip lasts. Then one claim spends
	# 200 ticks of credit to walk 20 m away, as in the freeze row.
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 5)
	var ticks_before := FixtureZoneModes.ticks_of(game, 0)
	for i in 22:
		_claim_next(game, P1, A, 1)
		FixtureModes.run_ticks(game, 9)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(ticks_before + 12)
	var corrected := FixtureMoves.corrections(game, P1).size()
	_claim_next(game, P1, A + EAST * 20, 200)
	assert_int(FixtureMoves.corrections(game, P1).size()).is_equal(corrected)
	assert_vector(game.state.player(P1).position).is_equal(A + EAST * 20)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(ticks_before + 12)


func test_a_zone_at_its_time_is_done_and_counts_no_more() -> void:
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], FixtureZoneModes.NEEDED - 1)
	assert_int(FixtureZoneModes.state_of(game).done_count()).is_equal(0)
	FixtureZoneModes.hold(game, [P1], 1)
	var task := FixtureZoneModes.task_of(game)
	var zone := FixtureZoneModes.zone_of(game, 0)
	assert_bool(zone.done).is_true()
	assert_array(FixtureZoneModes.state_of(game).done).is_equal([true, false])
	assert_bool(FixtureZoneModes.state_of(game).counting[0]).is_false()
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(FixtureZoneModes.NEEDED)
	assert_that(Tasks.progress(game.state)).is_equal(Vector2i(1, 2))
	assert_array(FixtureModes.notes(game)).is_equal(
		[FixtureSubtaskNote.text(task.id, {"subtask": 0, "station": zone.id})]
	)
	var sent := FixtureZoneModes.progress(game, P1).size()
	FixtureZoneModes.hold(game, [P1], 10)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(FixtureZoneModes.NEEDED)
	assert_int(FixtureZoneModes.progress(game, P1).size()).is_equal(sent)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_zone_done_in_the_clocks_last_tick_wins_for_the_crew() -> void:
	var game := FixtureZoneModes.in_round(
		FixtureZoneModes.winning(1), [P1, P2], FixtureZoneModes.layouts([A])
	)
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], FixtureZoneModes.NEEDED - 1)
	game.state.clock_ticks_left = 1
	FixtureZoneModes.hold(game, [P1], 1)
	assert_bool(game.state.clock_ended).is_true()
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureWinModes.ended(game, P2)).is_equal([&"crew"])


func test_round_end_stops_counting_and_reset_match_clears_the_time() -> void:
	var game := FixtureZoneModes.in_round(
		FixtureZoneModes.winning(1), [P1, P2], FixtureZoneModes.layouts([A])
	)
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 5)
	game.state.clock_ticks_left = 1
	FixtureZoneModes.hold(game, [P1], 1)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureWinModes.ended(game, P2)).is_equal([&"dissidents"])
	var sent := FixtureZoneModes.progress(game, P1).size()
	FixtureModes.run_ticks(game, 30)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(6)
	assert_int(FixtureZoneModes.progress(game, P1).size()).is_equal(sent)
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_dict(game.state.tasks).is_empty()
	assert_dict(game.state.stations).is_empty()
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_array(Array(FixtureZoneModes.state_of(game).ticks)).is_equal([0])
	assert_array(FixtureZoneModes.state_of(game).counting).is_equal([false])


## A round of the zone fixture mode (two zones, A and B) with `peers`.
func _round(peers: Array[int]) -> Match:
	return FixtureZoneModes.in_round(FixtureZoneModes.basic(2), peers)


func _zone_id(game: Match, index: int) -> int:
	return FixtureZoneModes.state_of(game).stations[index]


## A claim of `peer` at `at`, `covered` client ticks after its last accepted one, applied on the
## next host tick.
func _claim_next(game: Match, peer: int, at: Vector3, covered: int) -> void:
	var client_tick := game.state.player(peer).claim_tick + covered
	FixtureMoves.claim(game, peer, at, {"client_tick": client_tick})
	FixtureModes.run_ticks(game, 1)
