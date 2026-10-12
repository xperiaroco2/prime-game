extends GdUnitTestSuite
## The car repair's lift and drop (the car repair ADR's §2.2, §2.3, §2.6, §4, RE4, RE7, RE17,
## RD7, RD10 (c), RD11 (a); #807): the hold at the panel raises the car, every stop drops it, the
## drop kills whoever's feet lie inside the footprint box once the command has finished, and the
## phase's end lowers it without a kill.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const NORTH := Vector3(0, 0, 1)


func test_a_hold_raises_the_car_for_everyone_and_records_its_tick() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	FixtureCarRepairModes.hold(game, P1)
	FixtureModes.run_ticks(game, 1)
	var started := game.ticked_through()
	assert_int(task_state.held_since).is_equal(started)
	for peer: int in [P1, P2, P3]:
		assert_array(_lifts(game, peer)).is_equal(
			[{"station": task_state.panel, "up": true, "tick": started}]
		)
	var type := FixtureCarRepairModes.type_of(game.mode)
	assert_int(type.rise_ticks()).is_equal(FixtureCarRepairModes.RISE_TICKS)
	assert_bool(type.is_up(task_state, started + FixtureCarRepairModes.RISE_TICKS - 1)).is_false()
	assert_bool(type.is_up(task_state, started + FixtureCarRepairModes.RISE_TICKS)).is_true()
	# The hold has no end: it runs on.
	FixtureModes.run_ticks(game, 200)
	assert_array(_lifts(game, P2)).has_size(1)
	assert_bool(game.state.players[P1].is_alive()).is_true()


func test_letting_go_drops_the_car_and_kills_only_the_feet_in_the_box() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	FixtureCarRepairModes.hold(game, P1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under(0.5, 0.3))
	# Beside the car, past its half-width, and past its far end.
	FixtureItemModes.stand(game, P3, FixtureCarRepairModes.under(0.0, 1.5))
	FixtureItemModes.stand(game, P4, FixtureCarRepairModes.under(2.4, 0.0))
	FixtureModes.run_ticks(game, 30)
	FixtureCombatModes.stop_raise(game, P1)
	FixtureModes.run_ticks(game, 1)
	var dropped := game.ticked_through()
	assert_array(_lifts(game, P3)).is_equal(
		[
			{"station": task_state.panel, "up": true, "tick": dropped - 30},
			{"station": task_state.panel, "up": false, "tick": dropped}
		]
	)
	assert_int(task_state.held_since).is_equal(-1)
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	for peer: int in [P1, P3, P4]:
		assert_bool(game.state.players[peer].is_alive()).is_true()
	# Died after the drop, for everyone, naming no cause.
	var order := FixtureCarRepairModes.stream(game, P4, [&"LiftChanged", &"Died"])
	assert_array(order).is_equal([&"LiftChanged", &"LiftChanged", &"Died"])
	assert_int((game.view_of(P4).events_named(&"Died")[0] as DiedEvent).peer).is_equal(P2)


func test_the_box_test_inside_beside_at_the_ends_and_on_the_roof() -> void:
	var type := FixtureCarRepairModes.type_of(FixtureCarRepairModes.basic())
	var car := FixtureCarRepairModes.CAR_AT
	var end := FixtureCarRepairModes.CAR_END_AT
	var inside: Array[Vector3] = [
		car,
		car + Vector3(1.19, 0, 0),
		car + Vector3(-1.19, 0, 1.99),
		car + Vector3(0, 0, -1.99),
		car + Vector3(0.5, 1.0, 1.0),
		car + Vector3(0, -0.2, 0),
	]
	var outside: Array[Vector3] = [
		car + Vector3(1.25, 0, 0),
		car + Vector3(0, 0, 2.05),
		car + Vector3(0, 0, -2.05),
		car + Vector3(0, 1.05, 0),
		car + Vector3(0, -0.3, 0),
	]
	for feet: Vector3 in inside:
		assert_bool(type.in_box(car, end, feet)).override_failure_message("in %s" % feet).is_true()
	for feet: Vector3 in outside:
		(
			assert_bool(type.in_box(car, end, feet))
			. override_failure_message("out %s" % feet)
			. is_false()
		)
	# The box turns with the axis: along +x now, so (2, 0, 0) is at its end and (0, 0, 2) beside.
	var turned := car + Vector3(2, 0, 0)
	assert_bool(type.in_box(car, turned, car + Vector3(2, 0, 0))).is_true()
	assert_bool(type.in_box(car, turned, car + Vector3(0, 0, 2))).is_false()


func test_the_drop_kills_the_downed_and_the_invulnerable_under_the_car() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under(0.5, 0.5))
	FixtureItemModes.stand(game, P3, FixtureCarRepairModes.under(-0.5))
	# Struck down from beside the car, so the striker stands outside the box.
	_knock_down(game, P4, P2, Vector3.LEFT)
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DOWNED)
	game.state.players[P3].invulnerable_until = game.ticked_through() + 1000
	FixtureCombatModes.stop_raise(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	assert_int(game.state.players[P3].life).is_equal(PlayerState.Life.DEAD)
	var died: Array[int] = []
	for event: MatchEvent in game.view_of(P1).events_named(&"Died"):
		died.append((event as DiedEvent).peer)
	assert_array(died).is_equal([P2, P3])


func test_walking_out_of_the_panels_cylinder_drops_the_car() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under())
	FixtureModes.run_ticks(game, 5)
	FixtureItemModes.stand(game, P1, FixtureCarRepairModes.PANEL_AT + Vector3(0, 0, -3))
	FixtureModes.run_ticks(game, 1)
	assert_array(_ups(game)).is_equal([true, false])
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)


func test_losing_sight_of_the_panel_drops_the_car() -> void:
	var world := FlatWorldQuery.new()
	var game := FixtureCarRepairModes.in_round(
		FixtureCarRepairModes.basic(), [P1, P2, P3, P4], {}, {}, 7, {}, world
	)
	FixtureCarRepairModes.hold(game, P1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under())
	FixtureModes.run_ticks(game, 3)
	assert_array(_ups(game)).is_equal([true])
	# A wall between the holder and the panel: ChannelTicks' StationInSight re-check fails.
	var panel_at := game.state.stations[FixtureCarRepairModes.state_of(game).panel].position
	world.add_wall(AABB(panel_at + Vector3(-1, 0, -0.3), Vector3(2, 3, 0.1)))
	FixtureModes.run_ticks(game, 1)
	assert_array(_ups(game)).is_equal([true, false])
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	assert_int(game.state.players[P1].life).is_equal(PlayerState.Life.ALIVE)
	assert_object(Channels.of_actor(game.state, P1)).is_null()


func test_the_holder_dying_drops_the_car() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under())
	FixtureModes.run_ticks(game, 3)
	assert_array(_ups(game)).is_equal([true])
	# Another part of the mode kills the holder outright (a tick system queuing its kill).
	game.mode.find_phase(&"round").tick_systems.append(FixtureKillTick.queuing([P1]))
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.players[P1].life).is_equal(PlayerState.Life.DEAD)
	assert_array(_ups(game)).is_equal([true, false])
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	assert_object(Channels.of_actor(game.state, P1)).is_null()


func test_a_hit_does_not_drop_the_car_but_a_knockdown_does() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under())
	FixtureModes.run_ticks(game, 2)
	_hit(game, P4, P1, NORTH)
	assert_float(FixtureCombatModes.health(game, P1)).is_less(100.0)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	assert_array(_ups(game)).is_equal([true])
	assert_bool(game.state.players[P2].is_alive()).is_true()
	_hit(game, P4, P1, NORTH)
	assert_int(game.state.players[P1].life).is_equal(PlayerState.Life.DOWNED)
	assert_array(_ups(game)).is_equal([true, false])
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	# LiftChanged, then the holder's KnockedDown, then the victim's Died.
	var order := FixtureCarRepairModes.stream(game, P3, [&"LiftChanged", &"KnockedDown", &"Died"])
	assert_array(order).is_equal([&"LiftChanged", &"LiftChanged", &"KnockedDown", &"Died"])


func test_another_action_of_the_holder_drops_the_car() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under())
	FixtureModes.run_ticks(game, 2)
	var knife := FixtureItemModes.lay(game, &"knife", game.state.players[P1].position)
	FixtureItemModes.pick_up(game, P1, knife)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.players[P1].held_item).is_equal(knife.id)
	assert_array(_ups(game)).is_equal([true, false])
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)


func test_the_holder_leaving_drops_the_car() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under())
	FixtureModes.run_ticks(game, 2)
	FixtureModes.send(game, Intents.PEER_LEFT, P1)
	FixtureModes.run_ticks(game, 1)
	assert_array(_ups(game, P3)).is_equal([true, false])
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	var order := FixtureCarRepairModes.stream(game, P3, [&"LiftChanged", &"PlayerLeft", &"Died"])
	assert_array(order).is_equal([&"LiftChanged", &"LiftChanged", &"PlayerLeft", &"Died"])


func test_a_second_press_is_busy_and_stops_nothing() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1, 1)
	FixtureModes.run_ticks(game, 1)
	FixtureCarRepairModes.hold(game, P1, 2)
	FixtureCarRepairModes.hold(game, P3, 3)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"busy"])
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"busy"])
	assert_array(_ups(game)).is_equal([true])


func test_a_done_task_refuses_a_new_hold_but_keeps_a_running_one() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	FixtureCarRepairModes.hold(game, P1)
	FixtureModes.run_ticks(game, 1)
	# Every part fitted (R4's fit, written here into the task state).
	task_state.fitted = task_state.needed.size()
	FixtureModes.run_ticks(game, 5)
	assert_array(_ups(game)).is_equal([true])
	FixtureCombatModes.stop_raise(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureCarRepairModes.hold(game, P1, 7)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	assert_array(_ups(game)).is_equal([true, false])


func test_the_car_takes_a_use_only_while_fully_up() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	FixtureCarRepairModes.use(game, P2, task_state.car, 1)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable"])
	FixtureCarRepairModes.hold(game, P1)
	FixtureModes.run_ticks(game, FixtureCarRepairModes.RISE_TICKS - 1)
	FixtureCarRepairModes.use(game, P2, task_state.car, 2)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"unavailable", &"unavailable"])
	FixtureModes.run_ticks(game, 1)
	FixtureCarRepairModes.use(game, P2, task_state.car, 3)
	# A timed hold stops at its first re-check with no claim since its placement (ZE10).
	FixtureMoves.claim(game, P2, game.state.players[P2].position)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P2)).has_size(2)
	# Applied, not merely not refused: the fit's hold runs at the car.
	var fit := Channels.on_station(game.state, task_state.car)
	assert_object(fit).is_not_null()
	assert_int(fit.actor).is_equal(P2)


func test_the_phases_end_lowers_the_car_without_a_kill() -> void:
	var game := FixtureCarRepairModes.in_round(
		FixtureCarRepairModes.winning(), [P1, P2, P3], {}, {}, 7, {P3: &"dissident"}
	)
	FixtureCarRepairModes.hold(game, P1)
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under())
	FixtureModes.run_ticks(game, 2)
	assert_str(String(game.phase_id())).is_equal("round")
	# Time up: the dissidents win while the car is up and P2 lies under it.
	FixtureModes.run_ticks(game, FixtureWinModes.CLOCK_TICKS)
	assert_str(String(game.phase_id())).is_equal("end")
	assert_array(_ups(game)).is_equal([true, false])
	assert_bool(game.state.players[P2].is_alive()).is_true()
	assert_array(game.view_of(P1).events_named(&"Died")).is_empty()


## A round of basic() with P1, P2 and P3, every player far from the car.
func _round() -> Match:
	return FixtureCarRepairModes.in_round(FixtureCarRepairModes.basic(), [P1, P2, P3, P4])


## The LiftChanged events `peer` received, as plain data.
func _lifts(game: Match, peer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"LiftChanged"):
		found.append(event.to_dict())
	return found


## The `up` of each LiftChanged `peer` received, in order.
func _ups(game: Match, peer: int = P2) -> Array[bool]:
	var found: Array[bool] = []
	for fields: Dictionary in _lifts(game, peer):
		found.append(fields["up"] as bool)
	return found


## `striker` strikes `victim` once with a knife, from 1 m behind it along `facing`.
func _hit(game: Match, striker: int, victim: int, facing: Vector3) -> void:
	var at := game.state.players[victim].position - facing
	if game.state.players[striker].held_item < 0:
		FixtureCombatModes.arm(game, striker, at)
	FixtureItemModes.stand(game, striker, at)
	FixtureCombatModes.use(game, striker, facing)


## `striker` knocks `victim` down: two hits, a cooldown apart.
func _knock_down(game: Match, striker: int, victim: int, facing: Vector3 = NORTH) -> void:
	_hit(game, striker, victim, facing)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	_hit(game, striker, victim, facing)
