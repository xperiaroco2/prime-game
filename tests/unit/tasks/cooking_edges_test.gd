extends GdUnitTestSuite
## Cooking's edge rows beside other parts (the cooking ADR §4, #773): a downed player at the
## grill is not accepted (the allowlist), a raiser's take applies and stops its raise, the last
## serve in the clock's last tick wins for the crew (the command runs before the clock; the last
## ingredient before #1101, when a burger was done on its plate), and a
## round that ends while a patty fries changes nothing more until ResetMatch clears it. Driven by
## commands through a seeded Match on FixtureCookingModes.

const P1 := 1
const P2 := 2
const P3 := 3


func test_a_downed_player_at_the_grill_is_not_accepted() -> void:
	var game := FixtureCookingModes.in_round(FixtureCookingModes.basic(), [P1, P2])
	FixtureCookingModes.take(game, P1, &"raw_a")
	var patty := FixtureCookingModes.held(game, P1)
	FixtureModes.run_ticks(game, 1)
	game.state.player(P1).life = PlayerState.Life.DOWNED
	FixtureCookingModes.use(game, P1, FixtureCookingModes.grill_of(game), 5)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted"])
	assert_object(FixtureCookingModes.held(game, P1)).is_same(patty)
	assert_int(FixtureCookingModes.state_of(game).grill_item).is_equal(-1)
	assert_array(game.view_of(P2).events_named(&"GrillLoaded")).is_empty()


func test_a_raiser_s_take_applies_and_stops_the_raise() -> void:
	var game := FixtureCookingModes.in_round(FixtureCookingModes.basic(), [P1, P2, P3])
	var box := FixtureCookingModes.box_giving(game, &"bun_a")
	FixtureItemModes.stand(game, P2, box.position + Vector3(0, 0, 2))
	FixtureItemModes.stand(game, P3, box.position + Vector3(0, 0, 1))
	var downed := game.state.player(P2)
	downed.life = PlayerState.Life.DOWNED
	downed.life_deadline = game.ticked_through() + 1000
	FixtureCombatModes.raise(game, P3, P2)
	assert_object(Channels.of_actor(game.state, P3)).is_not_null()
	FixtureModes.run_ticks(game, 1)
	var seen := game.view_of(P1).events.size()
	FixtureGiveModes.interact_item(game, P3, box.id)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"ItemSpawned", &"ItemPickedUp"]
	)
	assert_str(FixtureCookingModes.held(game, P3).kind.id).is_equal("bun_a")
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_last_serve_in_the_clock_s_last_tick_wins_for_the_crew() -> void:
	var game := FixtureCookingModes.in_round(FixtureCookingModes.winning(1), [P1, P2])
	var order := FixtureCookingModes.state_of(game).orders[0]
	FixtureCookingModes.plate(game, P1, 0)
	FixtureCookingModes.take_burger(game, P1, 0)
	assert_bool(order.done).is_false()
	# The clock's last tick: without the burger, time up would win for the dissidents.
	game.state.clock_ticks_left = 1
	FixtureCookingModes.use(game, P1, FixtureCookingModes.board_of(game))
	FixtureModes.run_ticks(game, 1)
	assert_bool(order.done).is_true()
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureWinModes.ended(game, P2)).is_equal([&"crew"])


func test_round_end_while_a_patty_fries_changes_nothing_until_reset_match() -> void:
	var game := FixtureCookingModes.in_round(FixtureCookingModes.winning(1), [P1, P2])
	FixtureCookingModes.take(game, P1, &"raw_a")
	var patty := FixtureCookingModes.held(game, P1)
	FixtureCookingModes.use(game, P1, FixtureCookingModes.grill_of(game))
	FixtureModes.run_ticks(game, 1)
	game.state.clock_ticks_left = 1
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	assert_array(FixtureWinModes.ended(game, P2)).is_equal([&"dissidents"])
	var type := FixtureCookingModes.type_of(game.mode)
	FixtureModes.run_ticks(game, type.burnt_ticks() + 1)
	assert_str(patty.kind.id).is_equal("raw_a")
	assert_int(FixtureCookingModes.state_of(game).grill_item).is_equal(patty.id)
	assert_array(game.view_of(P2).events_named(&"ItemChanged")).is_empty()
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_bool(game.state.items.has(patty.id)).is_false()
	assert_dict(game.state.tasks).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()
