extends GdUnitTestSuite
## The car's drop in the middle of a command (the car repair ADR's §4 and RE17; §7's R3 list;
## #807): the drop's kills wait until the command, the tick system or the channel's step has
## finished, so no condition or effect runs on a player the drop killed halfway. The panel stands
## beside the car (FixtureCarRepairModes.NEAR_PANEL_AT), so a holder can stand inside the footprint
## box and still within the panel's cylinder.
## Planted once in CarRepair.hold_stopped (LifeRules.kill in place of kill_later): the knockdown,
## the two-target swing and the pick-up tests failed; reverted (#807).
## The ADR's §4 row "the holder sends Raise at a knocked-down player in the box" expects the raise
## to stop the hold and start; ChannelFree (one channel per actor) refuses it `busy` instead, so
## the raise case here is another player's raise on the victim (listed for the engineer, #807).

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
## Inside the footprint box (half-width 1.2 m) and 0.9 m from the near panel's marker.
const HOLDER_IN_BOX := Vector3(1.1, 0, 30)
const LIFE_EVENTS: Array[StringName] = [
	&"LiftChanged", &"Damaged", &"KnockedDown", &"RaiseStarted", &"RaiseStopped", &"Died"
]


func test_a_holder_in_the_box_knocked_down_dies_once_with_no_knockdown_after() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureItemModes.stand(game, P1, HOLDER_IN_BOX)
	# Struck from beside the car, so the striker stands outside the box.
	_hit(game, P4, P1)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	# The hold runs on with its holder inside the box.
	assert_array(_ups(game)).is_equal([true])
	_hit(game, P4, P1)
	assert_int(game.state.players[P1].life).is_equal(PlayerState.Life.DEAD)
	assert_int(game.state.bodies.size()).is_equal(1)
	assert_bool(game.state.bodies.has(P1)).is_true()
	for peer: int in [P2, P3, P4]:
		assert_bool(game.state.players[peer].is_alive()).is_true()
	# LiftChanged(false), then the holder's KnockedDown, then its one Died, nothing after.
	assert_array(_order(game, P3)).is_equal(
		[&"LiftChanged", &"LiftChanged", &"KnockedDown", &"Died"]
	)
	assert_array(game.view_of(P1).events_named(&"Died")).has_size(1)
	# The holder's own view has the ADR's order: the drop, its knockdown and Correction, its death.
	var own := FixtureCarRepairModes.stream(
		game, P1, [&"LiftChanged", &"KnockedDown", &"Correction", &"Died"]
	)
	assert_array(own.slice(own.size() - 4)).is_equal(
		[&"LiftChanged", &"KnockedDown", &"Correction", &"Died"]
	)


func test_a_raise_on_a_downed_player_in_the_box_stops_before_its_death() -> void:
	var game := _round()
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under(0.5, 0.5))
	_hit(game, P4, P2)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	_hit(game, P4, P2)
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DOWNED)
	FixtureCarRepairModes.hold(game, P1)
	FixtureModes.run_ticks(game, 2)
	# The holder's own Raise, within reach of P2: ChannelFree (one channel per actor) refuses it
	# `busy`, so it stops nothing and the hold runs on.
	FixtureCombatModes.raise(game, P1, P2, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"busy"])
	assert_array(_ups(game, P3)).is_equal([true])
	# Another player raises P2 from beside the car; the holder lets go.
	FixtureItemModes.stand(game, P3, Vector3(2, 0, 31))
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 2)
	FixtureCombatModes.stop_raise(game, P1, 2)
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	# The drop, then the kill stops the raise on the dead before its Died.
	var order := _order(game, P4)
	assert_array(order.slice(order.size() - 4)).is_equal(
		[&"RaiseStarted", &"LiftChanged", &"RaiseStopped", &"Died"]
	)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_object(Channels.on_target(game.state, P2)).is_null()
	FixtureModes.run_ticks(game, FixtureCombatModes.RAISE_TICKS + 1)
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)


func test_a_two_target_swing_from_the_box_damages_all_before_the_swingers_death() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureModes.run_ticks(game, 1)
	# P1 holds at the panel's edge, P2 beside it; P3 swings at both from inside the box.
	FixtureItemModes.stand(game, P1, Vector3(2.2, 0, 30))
	FixtureItemModes.stand(game, P2, Vector3(2.2, 0, 30.3))
	FixtureCombatModes.arm(game, P3, Vector3(0.9, 0, 30))
	FixtureCombatModes.use(game, P3, Vector3.RIGHT)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	assert_array(_ups(game)).is_equal([true])
	FixtureCombatModes.use(game, P3, Vector3.RIGHT, 1)
	assert_int(game.state.players[P1].life).is_equal(PlayerState.Life.DOWNED)
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DOWNED)
	assert_int(game.state.players[P3].life).is_equal(PlayerState.Life.DEAD)
	var order := _order(game, P4)
	assert_array(order.slice(order.size() - 4)).is_equal(
		[&"LiftChanged", &"KnockedDown", &"KnockedDown", &"Died"]
	)
	assert_int((game.view_of(P4).events_named(&"Died")[0] as DiedEvent).peer).is_equal(P3)
	# Nobody, the hit players and the swinger included, is told of a hit after the swinger's death.
	for peer: int in [P1, P2, P3, P4]:
		var seen := _order(game, peer)
		var last: StringName = seen[seen.size() - 1]
		assert_str(String(last)).override_failure_message("%d: %s" % [peer, seen]).is_equal("Died")
	# Both swings damaged P2 (the second also knocked it down), each before the swinger's Died.
	assert_array(game.view_of(P2).events_named(&"Damaged")).has_size(2)


func test_the_holders_own_pick_up_in_the_box_leaves_the_item_at_its_body() -> void:
	var game := _round()
	FixtureCarRepairModes.hold(game, P1)
	FixtureModes.run_ticks(game, 1)
	FixtureItemModes.stand(game, P1, HOLDER_IN_BOX)
	var knife := FixtureItemModes.lay(game, &"knife", HOLDER_IN_BOX)
	FixtureItemModes.pick_up(game, P1, knife)
	assert_int(game.state.players[P1].life).is_equal(PlayerState.Life.DEAD)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(_ups(game)).is_equal([true, false])
	assert_int(game.state.players[P1].held_item).is_equal(-1)
	assert_int(knife.where).is_equal(ItemState.Where.GROUND)
	assert_int(knife.holder).is_equal(0)
	assert_float(knife.position.distance_to(game.state.bodies[P1])).is_less(0.5)


## A round of basic() with P1 to P4 and the lift panel beside the car.
func _round() -> Match:
	return FixtureCarRepairModes.in_round(
		FixtureCarRepairModes.basic(),
		[P1, P2, P3, P4],
		FixtureCarRepairModes.layouts(
			FixtureCarRepairModes.CAR_END_AT, FixtureCarRepairModes.NEAR_PANEL_AT
		)
	)


## The names of the life and lift events `peer` received, in order.
func _order(game: Match, peer: int) -> Array[StringName]:
	return FixtureCarRepairModes.stream(game, peer, LIFE_EVENTS)


## The `up` of each LiftChanged `peer` received, in order.
func _ups(game: Match, peer: int = P2) -> Array[bool]:
	var found: Array[bool] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"LiftChanged"):
		found.append((event as LiftChangedEvent).up)
	return found


## `striker` strikes `victim` once with a knife from 1 m to its +x side, facing -x: outside the
## footprint box for a victim inside it.
func _hit(game: Match, striker: int, victim: int) -> void:
	var at := game.state.players[victim].position + Vector3.RIGHT
	if game.state.players[striker].held_item < 0:
		FixtureCombatModes.arm(game, striker, at)
	FixtureItemModes.stand(game, striker, at)
	FixtureCombatModes.use(game, striker, Vector3.LEFT)
