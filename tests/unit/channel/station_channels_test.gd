extends GdUnitTestSuite
## Channels on stations (the car repair ADR's RE2 to RE5 and RE9, #805; ARCHITECTURE §9.3, §9.4):
## Interact on a panel whose rule ends in HoldStation starts a channel on that station (station
## set, no player target) and hands its start, stop and completion to the station's task type; its
## station conditions find the station through the channel on every re-check; ChannelFree allows
## one channel per station; an endless hold never completes; a timed one stops once its holder
## stops claiming (ZE10), an endless one does not; a hit stops it only when hit_stops; a knockdown
## of the peer whose number is the station's stops nothing; StopRaise, walking away, a use_problem,
## a leave and the holder's knockdown stop it; a phase's end marks it phase_ended. Driven by
## commands on a seeded match of FixtureStationModes.holding() (stations 1 at (0, 0, 20) and 2 at
## (6, 0, 20); task 1), asserted on the notes the fixture type emits to everyone and on view_of.

const P1 := 1
const P2 := 2
const P3 := 3
## Inside station 1's cylinder (radius 1 m), 0.9 m short of its marker.
const NEAR_1 := Vector3(0, 0, 19.1)
## Inside station 2's cylinder.
const NEAR_2 := Vector3(6, 0, 19.1)
const FAR := Vector3(0, 0, 10)
const NORTH := Vector3(0, 0, 1)
## Far from the stations: where P3 strikes P1 (1 m north of it).
const BRAWL := Vector3(20, 0, 5)
const STARTED := "hold started 1 by 2 task 1"


func test_an_endless_hold_runs_on_its_station_never_completes_and_passes_its_re_checks() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureStationModes.interact(game, P2, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	var channel := Channels.of_actor(game.state, P2)
	assert_int(channel.station).is_equal(1)
	assert_int(channel.target).is_equal(0)
	assert_object(Channels.on_station(game.state, 1)).is_same(channel)
	assert_object(Channels.on_station(game.state, 2)).is_null()
	# 30 s with no claim at all: the endless hold is exempt from the claim age (RE2).
	FixtureModes.run_ticks(game, 600)
	assert_object(Channels.of_actor(game.state, P2)).is_same(channel)
	assert_int(channel.done_ticks).is_equal(600)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED])
	assert_array(_notes_seen_by(game, P1)).is_equal([STARTED])
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_timed_hold_completes_while_its_holder_keeps_claiming() -> void:
	var game := _round(FixtureStationModes.hold(1.0))
	_claim(game, P2)
	FixtureStationModes.interact(game, P2, 1)
	_hold(game, P2, 19)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED])
	_hold(game, P2, 1)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED, "hold completed 1 by 2 after 20"])
	assert_object(Channels.of_actor(game.state, P2)).is_null()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_timed_hold_stops_once_its_holders_last_claim_is_too_old() -> void:
	var game := _round(FixtureStationModes.hold(5.0))
	_claim(game, P2)
	FixtureStationModes.interact(game, P2, 1)
	_hold(game, P2, 5)
	# The last claim is now 0 ticks old at the next re-check; PUSH_TICKS more pass with none.
	FixtureModes.run_ticks(game, MovementRule.PUSH_TICKS)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED])
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED, "hold stopped 1 by 2 after 15"])


func test_a_timed_hold_with_no_claim_since_its_placement_stops_at_its_first_re_check() -> void:
	var game := _round(FixtureStationModes.hold(1.0))
	FixtureStationModes.interact(game, P2, 1)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED, "hold stopped 1 by 2 after 0"])


func test_a_timed_hold_stops_once_its_holder_stored_more_than_the_push_allowance_of_credit(
) -> void:
	# The drip (#647's bound): a claim every 10 host ticks covering one client tick keeps the claim
	# young but stores 9 ticks of credit each time, which a later claim would spend as travel.
	var game := _round(FixtureStationModes.hold(30.0))
	_claim(game, P2)
	FixtureStationModes.interact(game, P2, 1)
	var channel := Channels.of_actor(game.state, P2)
	for i in 4:
		var covered := game.state.player(P2).claim_tick + 1
		FixtureMoves.claim(game, P2, NEAR_1, {"client_tick": covered})
		FixtureModes.run_ticks(game, 10)
		if i == 0:
			# 9 stored: within the allowance (PUSH_TICKS = 10), the hold goes on.
			assert_object(Channels.of_actor(game.state, P2)).is_same(channel)
	assert_object(Channels.of_actor(game.state, P2)).is_null()
	assert_str(" ".join(FixtureModes.notes(game))).contains("hold stopped 1 by 2")


func test_a_second_holder_of_the_same_station_is_busy_and_another_station_is_free() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureItemModes.stand(game, P3, NEAR_1)
	FixtureItemModes.stand(game, P1, NEAR_2)
	FixtureStationModes.interact(game, P2, 1)
	FixtureStationModes.interact(game, P3, 1)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([ChannelFree.BUSY])
	FixtureStationModes.interact(game, P1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	FixtureModes.run_ticks(game, 3)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED, "hold started 2 by 1 task 1"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_holder_pressing_again_is_busy_and_keeps_its_hold() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureStationModes.interact(game, P2, 1)
	FixtureStationModes.interact(game, P2, 1, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([ChannelFree.BUSY])
	assert_array(FixtureModes.notes(game)).is_equal([STARTED])
	assert_object(Channels.of_actor(game.state, P2)).is_not_null()


func test_a_knockdown_of_the_peer_numbered_as_the_station_stops_no_hold() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureStationModes.interact(game, P2, 1)
	_knock_down(game, P3, P1)
	assert_bool(game.state.player(P1).life == PlayerState.Life.DOWNED).is_true()
	assert_object(Channels.of_actor(game.state, P2)).is_not_null()
	assert_array(FixtureModes.notes(game)).is_equal([STARTED])
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_hit_stops_a_hold_only_when_hit_stops_and_a_knockdown_always() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true, false))
	FixtureStationModes.interact(game, P2, 1)
	FixtureCombatModes.arm(game, P3, NEAR_1 - NORTH)
	FixtureCombatModes.use(game, P3, NORTH)
	assert_float(FixtureCombatModes.health(game, P2)).is_less(100.0)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED])
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P3, NORTH)
	assert_bool(game.state.player(P2).life == PlayerState.Life.DOWNED).is_true()
	assert_array(FixtureModes.notes(game)).is_equal(
		[STARTED, "hold stopped 1 by 2 after %d" % FixtureCombatModes.COOLDOWN_TICKS]
	)
	# The control: a hold whose hits stop it stops at the first hit.
	var stopping := _round(FixtureStationModes.hold(0.0, true, true))
	FixtureStationModes.interact(stopping, P2, 1)
	FixtureCombatModes.arm(stopping, P3, NEAR_1 - NORTH)
	FixtureCombatModes.use(stopping, P3, NORTH)
	assert_bool(stopping.state.player(P2).is_alive()).is_true()
	assert_array(FixtureModes.notes(stopping)).is_equal([STARTED, "hold stopped 1 by 2 after 0"])


func test_stop_raise_stops_a_hold() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureStationModes.interact(game, P2, 1)
	FixtureModes.run_ticks(game, 4)
	FixtureCombatModes.stop_raise(game, P2)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	assert_array(FixtureModes.notes(game)).is_equal([STARTED, "hold stopped 1 by 2 after 4"])
	assert_object(Channels.on_station(game.state, 1)).is_null()


func test_walking_out_of_the_cylinder_stops_a_hold_on_its_next_re_check() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureStationModes.interact(game, P2, 1)
	FixtureModes.run_ticks(game, 2)
	FixtureItemModes.stand(game, P2, FAR)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED, "hold stopped 1 by 2 after 2"])


func test_a_wall_across_the_line_of_sight_stops_a_hold_on_its_next_re_check() -> void:
	var world := FlatWorldQuery.new()
	var game := FixtureStationModes.in_round(
		FixtureStationModes.holding(FixtureStationModes.hold(0.0, true)), [P1, P2, P3], world
	)
	FixtureItemModes.stand(game, P2, NEAR_1)
	FixtureStationModes.interact(game, P2, 1)
	FixtureModes.run_ticks(game, 2)
	world.add_wall(AABB(Vector3(-1, 0, 19.3), Vector3(2, 3, 0.1)))
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED, "hold stopped 1 by 2 after 2"])


func test_a_use_problem_the_type_now_returns_stops_a_hold_on_its_next_re_check() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureStationModes.interact(game, P2, 1)
	FixtureModes.run_ticks(game, 2)
	FixtureStationModes.type_of(game.mode).problem = StationUsable.UNAVAILABLE
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.notes(game)).is_equal([STARTED, "hold stopped 1 by 2 after 2"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_its_holder_leaving_stops_a_hold() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureStationModes.interact(game, P2, 1)
	FixtureModes.run_ticks(game, 3)
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	# Then the mode's own notes of the leave, if any.
	assert_array(FixtureModes.notes(game).slice(0, 2)).is_equal(
		[STARTED, "hold stopped 1 by 2 after 3"]
	)


func test_the_phase_ending_stops_a_hold_marked_phase_ended() -> void:
	var game := _round(FixtureStationModes.hold(0.0, true))
	FixtureStationModes.interact(game, P2, 1)
	FixtureModes.run_ticks(game, 3)
	game.state.set_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(String(game.phase_id())).is_equal("end")
	var notes := FixtureModes.notes(game)
	# The tick's ChannelTicks ran before its win check: 4 ticks.
	assert_array(notes.slice(0, 2)).is_equal([STARTED, "hold stopped 1 by 2 after 4 phase_ended"])
	assert_array(Channels.running(game.state)).is_empty()


## A round of FixtureStationModes.holding(`effect`) with P1 to P3, P2 standing in station 1's
## cylinder (no claim yet: placed there).
func _round(effect: HoldStation) -> Match:
	var game := FixtureStationModes.in_round(FixtureStationModes.holding(effect), [P1, P2, P3])
	FixtureItemModes.stand(game, P2, NEAR_1)
	return game


## `peer` claims where the host has it, applied in the next tick.
func _claim(game: Match, peer: int) -> void:
	FixtureMoves.claim(game, peer, game.state.player(peer).position)


## `ticks` ticks, each run after `peer` claims where it stands.
func _hold(game: Match, peer: int, ticks: int) -> void:
	for i in ticks:
		FixtureModes.run_ticks(game, 1)
		if i < ticks - 1:
			_claim(game, peer)


## `striker` strikes `victim` twice from 1 m south of it, at BRAWL, far from the stations: the
## second hit knocks it down.
func _knock_down(game: Match, striker: int, victim: int) -> void:
	FixtureItemModes.stand(game, victim, BRAWL + NORTH)
	FixtureCombatModes.arm(game, striker, BRAWL)
	FixtureCombatModes.use(game, striker, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, striker, NORTH)


## The texts of the FixtureNote events `peer` received.
func _notes_seen_by(game: Match, peer: int) -> Array[String]:
	var found: Array[String] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"FixtureNote"):
		found.append((event as FixtureNoteEvent).text)
	return found
