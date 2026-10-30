extends GdUnitTestSuite
## The limp (#1393; ARCHITECTURE §7.1.21): too much drink lays the drinker down as a rag-doll while
## its life stays ALIVE (GoLimp, a reaction on drunk_too_much); walkers push the body (LimpTicks),
## and the player gets up by itself at its time. A limp player acts on nothing but its claims and
## Ready, takes no damage, and no limp outlasts the Lobby and the Countdown. Driven by FixtureLimp.

const P1 := FixtureLimp.P1
const P2 := FixtureLimp.P2
const P3 := FixtureLimp.P3


func test_too_much_lays_the_drinker_limp_alive_and_not_downed() -> void:
	var game := FixtureBar.at_bar(FixtureLimp.mode(), [P1, P2])
	var drinker := game.state.player(P1)
	var epoch := drinker.epoch
	var health := drinker.health
	FixtureLimp.drink_to_limp(game, P1)
	assert_bool(drinker.is_limp()).is_true()
	assert_int(drinker.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(drinker.health).is_equal(health)
	assert_int(drinker.drunk).is_greater_equal(FixtureBar.TOO_MUCH)
	assert_int(drinker.epoch).is_equal(epoch + 1)
	assert_int(drinker.motion.epoch).is_equal(drinker.epoch)
	var went := game.ticked_through() + 1
	assert_int(drinker.limp.until).is_equal(went + Ticks.from_seconds(FixtureLimp.LIMP_S))
	var launched := _emitted(game, &"LaunchBody")
	assert_int(launched.size()).is_equal(1)
	assert_array(launched[0].recipients).is_empty()
	assert_vector((launched[0].event as LaunchBodyEvent).velocity).is_equal(Vector3.ZERO)
	for peer: int in [P1, P2]:
		assert_array(game.view_of(peer).events_named(&"KnockedDown")).is_empty()
	assert_array(game.view_of(P2).events_named(&"Correction")).is_empty()
	# The hand keeps its (empty) mug: nothing drops (provisional).
	assert_object(Items.held_by(game.state, P1)).is_not_null()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_limp_flag_reaches_every_peer_and_the_own_client() -> void:
	var game := FixtureBar.at_bar(FixtureLimp.mode(), [P1, P2])
	var now := game.ticked_through()
	assert_bool(Snapshots.avatars_for(game.state, P1, now).has(P1)).is_false()
	assert_bool(Snapshots.avatars_for(game.state, P2, now)[P1]["limp"] as bool).is_false()
	FixtureLimp.drink_to_limp(game, P1)
	now = game.ticked_through()
	var own: Dictionary = Snapshots.avatars_for(game.state, P1, now)[P1]
	assert_bool(own["limp"] as bool).is_true()
	assert_bool(own["downed"] as bool).is_false()
	assert_bool(Snapshots.avatars_for(game.state, P2, now)[P1]["limp"] as bool).is_true()


func test_a_limp_player_acts_on_nothing_but_ready() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2], P1)
	var held := Items.held_by(game.state, P1).id
	FixtureBar.pour(game, P1, 200)
	FixtureBar.drink(game, P1, 201)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"not_accepted", &"not_accepted"])
	assert_int(Items.held_by(game.state, P1).id).is_equal(held)
	FixtureBaseMode.ready(game, P1, true, 202)
	assert_bool(game.state.player(P1).ready).is_true()


func test_no_damage_or_strike_reaches_a_limp_player() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2], P1)
	var limp := game.state.player(P1)
	var health := limp.health
	var ctx := _ctx(game)
	LifeRules.damage(ctx, P1, 500)
	assert_int(limp.health).is_equal(health)
	FixtureItemModes.stand(game, P2, limp.position + Vector3(0, 0, -0.8))
	var knife := FixtureCombatModes.strike(360.0, 1.5, 50)
	assert_array(knife.targets(ctx, game.state.player(P2), Vector3.BACK)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_walker_into_the_body_pushes_it_and_one_out_of_reach_does_not() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2, P3], P1)
	var limp := game.state.player(P1)
	var epoch := limp.epoch
	var pushes := _emitted(game, &"LaunchBody").size()
	var walker := game.state.player(P2)
	walker.position = limp.position + Vector3(0, 0, FixtureLimp.REACH + 0.05)
	walker.velocity = Vector3(0, 0, -2.0)
	FixtureModes.run_ticks(game, 1)
	assert_int(_emitted(game, &"LaunchBody").size()).is_equal(pushes)
	walker.position = limp.position + Vector3(0, 0, 0.8)
	FixtureModes.run_ticks(game, 1)
	var launched := _emitted(game, &"LaunchBody")
	assert_int(launched.size()).is_equal(pushes + 1)
	var push := launched[-1].event as LaunchBodyEvent
	assert_vector(push.velocity).is_equal_approx(Vector3(0, 0, -2.0), Vector3.ONE * 1e-4)
	assert_int(push.epoch).is_equal(epoch)
	assert_int(limp.epoch).is_equal(epoch)
	assert_int(limp.motion.ticks).is_equal(0)
	# Within the cooldown nobody pushes again; walking away never pushes.
	FixtureModes.run_ticks(game, 1)
	assert_int(_emitted(game, &"LaunchBody").size()).is_equal(pushes + 1)
	walker.velocity = Vector3(0, 0, 2.0)
	FixtureModes.run_ticks(game, Ticks.from_seconds(FixtureLimp.COOLDOWN_S) + 1)
	assert_int(_emitted(game, &"LaunchBody").size()).is_equal(pushes + 1)


func test_a_forged_speed_is_held_to_the_sprint_and_the_push_to_its_cap() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2, P3], P1)
	var limp := game.state.player(P1)
	var pushes := _emitted(game, &"LaunchBody").size()
	for peer: int in [P2, P3]:
		var walker := game.state.player(peer)
		walker.position = limp.position + Vector3(0, 0, 0.6)
		walker.velocity = Vector3(0, 0, -1000.0)
	FixtureModes.run_ticks(game, 1)
	var launched := _emitted(game, &"LaunchBody")
	assert_int(launched.size()).is_equal(pushes + 1)
	var speed := (launched[-1].event as LaunchBodyEvent).velocity.length()
	assert_float(speed).is_equal_approx(FixtureLimp.MAX_SPEED, 1e-4)


func test_a_limp_or_downed_player_pushes_nothing() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2, P3], P1)
	var limp := game.state.player(P1)
	var pushes := _emitted(game, &"LaunchBody").size()
	var other := game.state.player(P2)
	other.limp = LimpState.new(game.ticked_through() + 1000)
	other.position = limp.position + Vector3(0, 0, 0.6)
	other.velocity = Vector3(0, 0, -2.0)
	var downed := game.state.player(P3)
	downed.life = PlayerState.Life.DOWNED
	downed.position = limp.position + Vector3(0.6, 0, 0)
	downed.velocity = Vector3(-2.0, 0, 0)
	FixtureModes.run_ticks(game, 1)
	assert_int(_emitted(game, &"LaunchBody").size()).is_equal(pushes)


func test_reports_move_the_limp_body_with_no_error() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2], P1)
	var limp := game.state.player(P1)
	_report(game, P1, limp.epoch, Vector3(1, 0, 2), Vector3(0, 0, 1))
	assert_vector(limp.position).is_equal(Vector3(1, 0, 2))
	_report(game, P1, limp.epoch + 5, Vector3(9, 0, 9), Vector3.ZERO)
	assert_vector(limp.position).is_equal(Vector3(1, 0, 2))
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_player_gets_up_at_its_time_where_the_body_rested_and_stays_drunk() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2], P1)
	var limp := game.state.player(P1)
	var until := limp.limp.until
	# The body rests before the get-up: the slow reports end its motion.
	for i in Ticks.from_seconds(0.5) + 1:
		_report(game, P1, limp.epoch, Vector3(2, 0, 1), Vector3.ZERO)
	assert_object(limp.motion).is_null()
	var epoch := limp.epoch
	var corrections := game.view_of(P1).events_named(&"Correction").size()
	FixtureModes.run_ticks(game, until - game.ticked_through() - 1)
	assert_bool(limp.is_limp()).is_true()
	FixtureModes.run_ticks(game, 1)
	assert_bool(limp.is_limp()).is_false()
	assert_int(limp.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(limp.epoch).is_equal(epoch + 1)
	assert_vector(limp.position).is_equal(Vector3(2, 0, 1))
	assert_int(game.view_of(P1).events_named(&"Correction").size()).is_equal(corrections + 1)
	assert_array(game.view_of(P2).events_named(&"Revived")).is_empty()
	assert_int(limp.drunk).is_greater(0)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_moving_body_rests_before_the_get_up() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2], P1)
	var limp := game.state.player(P1)
	var stops := _emitted(game, &"StopBody").size()
	FixtureModes.run_ticks(game, limp.limp.until - game.ticked_through())
	assert_bool(limp.is_limp()).is_false()
	assert_object(limp.motion).is_null()
	assert_int(_emitted(game, &"StopBody").size()).is_equal(stops + 1)


func test_the_countdown_end_gets_everyone_up_before_loading() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2], P1)
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer, true, 300)
	FixtureModes.run_ticks(game, Ticks.from_seconds(5.0) + 2)
	assert_str(String(game.phase_id())).is_equal("loading")
	var limp := game.state.player(P1)
	assert_bool(limp.is_limp()).is_false()
	assert_object(limp.motion).is_null()
	assert_bool(Snapshots.avatars_for(game.state, P1, game.ticked_through()).has(P1)).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


## The plan review's go_limp steps: a seated, crouched, sprinting drinker going limp stands from
## none of them: its seat, crouch, sneak and sprint end, its drunk value stays and no life deadline
## is set (LifeTicks would log one for a living player).
func test_a_seated_crouched_drinker_goes_limp_with_every_pose_ended() -> void:
	var game := FixtureBar.at_bar(FixtureLimp.mode(), [P1, P2])
	var drinker := game.state.player(P1)
	for i in 2:
		FixtureBar.pour(game, P1, 100 + 2 * i)
		FixtureBar.drink(game, P1, 101 + 2 * i)
	FixtureBar.pour(game, P1, 104)
	drinker.posed = true
	drinker.crouched = true
	drinker.sneaking = true
	drinker.sprinting = true
	FixtureBar.drink(game, P1, 105)
	assert_bool(drinker.is_limp()).is_true()
	assert_bool(drinker.posed or drinker.crouched or drinker.sneaking).is_false()
	assert_bool(drinker.sprinting).is_false()
	assert_int(drinker.drunk).is_greater_equal(FixtureBar.TOO_MUCH)
	assert_int(drinker.life_deadline).is_equal(-1)
	for i in 3:
		game.tick(game.ticked_through() + 1)
	var seen: Dictionary = Snapshots.avatars_for(game.state, P2, game.ticked_through())[P1]
	assert_bool(seen["posed"] as bool).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_leave_while_limp_frees_the_body() -> void:
	var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2], P1)
	var stops := _emitted(game, &"StopBody").size()
	game.apply(MatchCommand.new(Intents.PEER_LEFT, P1, game.ticked_through() + 1, {}))
	assert_int(_emitted(game, &"StopBody").size()).is_equal(stops + 1)


func test_the_same_seed_and_commands_give_the_same_limp() -> void:
	var histories: Array[Array] = []
	for run in 2:
		var game := FixtureLimp.limp(FixtureLimp.mode(), [P1, P2], P1)
		var walker := game.state.player(P2)
		walker.position = game.state.player(P1).position + Vector3(0, 0, 0.8)
		walker.velocity = Vector3(0, 0, -2.0)
		FixtureModes.run_ticks(game, 140)
		histories.append(FixtureModes.describe(game))
	assert_array(histories[0]).is_equal(histories[1])


func test_go_limp_checks_its_numbers_and_the_modes_limp_rows() -> void:
	var go := GoLimp.new()
	go.limp_s = 0.1
	var made := FixtureLimp.mode()
	assert_str(" ".join(go.check(made))).contains("limp_s")
	go.limp_s = FixtureLimp.LIMP_S
	assert_array(Array(go.check(made))).is_empty()
	for row: Transition in made.transitions:
		row.actions = row.actions.filter(func(a: RuleEffect) -> bool: return not a is EndLimps)
	assert_str(" ".join(go.check(made))).contains("EndLimps")
	assert_str(" ".join(FixtureLimp.limp_ticks().check(made))).is_empty()
	var ticks := FixtureLimp.limp_ticks()
	ticks.reach_m = 10.0
	assert_str(" ".join(ticks.check(made))).contains("reach_m")


func _ctx(game: Match) -> MatchContext:
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	return ctx


func _report(game: Match, peer: int, epoch: int, at: Vector3, velocity: Vector3) -> void:
	var args := {"epoch": epoch, "position": at, "velocity": velocity}
	game.apply(MatchCommand.new(Intents.BODY_MOVED, peer, game.ticked_through() + 1, args))


func _emitted(game: Match, event_name: StringName) -> Array[EmittedEvent]:
	var found: Array[EmittedEvent] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event.event_name() == event_name:
			found.append(emitted)
	return found
