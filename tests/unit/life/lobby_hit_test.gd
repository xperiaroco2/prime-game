extends GdUnitTestSuite
## Hits in the hall (#1439; ARCHITECTURE §7.1.10, §7.1.21): in a phase with a PhaseSpec.hit_limp
## (the base mode's Lobby and Countdown) a strike damages as in the round, and the hit to 0 health
## lays the victim limp for the GoLimp's limp_s instead of down; it gets up by itself at full
## health, and nobody is knocked down, dies or respawns there. The countdown's end gets everyone up
## and back at full health (EndLimps.restore_health). Driven by FixtureLobbyHit with the knife's
## Strike.

const P1 := FixtureLobbyHit.P1
const P2 := FixtureLobbyHit.P2
const P3 := FixtureLobbyHit.P3
const HEALTH := FixtureLobbyHit.HEALTH
const HIT := FixtureLobbyHit.HIT
const LIFE_EVENTS: Array[StringName] = [&"KnockedDown", &"Died", &"Respawned", &"Revived"]


func test_a_lobby_hit_damages_as_in_the_round() -> void:
	var game := FixtureLobbyHit.armed(FixtureLobbyHit.mode(), [P1, P2, P3])
	FixtureLobbyHit.hit(game, 10)
	var victim := game.state.player(P2)
	assert_int(victim.health).is_equal(HEALTH - HIT)
	var damaged := FixtureCombatModes.received(game, P2, &"Damaged")
	assert_array(damaged).has_size(1)
	assert_int((damaged[0] as DamagedEvent).amount).is_equal(HIT)
	assert_int((damaged[0] as DamagedEvent).health).is_equal(HEALTH - HIT)
	var status := FixtureCombatModes.received(game, P2, &"SelfStatus")
	assert_int((status[-1] as SelfStatusEvent).health).is_equal(HEALTH - HIT)
	for peer: int in [P1, P3]:
		assert_array(FixtureCombatModes.received(game, peer, &"Damaged")).is_empty()
		assert_array(FixtureCombatModes.received(game, peer, &"Swung")).has_size(1)
	assert_bool(victim.is_limp()).is_false()
	assert_int(victim.life).is_equal(PlayerState.Life.ALIVE)
	assert_array(Array(game.diagnostics)).is_empty()


func test_zero_health_in_the_lobby_goes_limp_not_down() -> void:
	var game := FixtureLobbyHit.armed(FixtureLobbyHit.mode(), [P1, P2, P3])
	var victim := game.state.player(P2)
	var epoch := victim.epoch
	FixtureLobbyHit.hit(game, 10)
	FixtureCombatModes.use(game, P1, FixtureLobbyHit.FACING, 11)
	var went := game.ticked_through() + 1
	assert_bool(victim.is_limp()).is_true()
	assert_int(victim.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(victim.health).is_equal(0)
	assert_int(victim.life_deadline).is_equal(-1)
	assert_int(victim.epoch).is_equal(epoch + 1)
	assert_bool(victim.limp.refill).is_true()
	assert_int(victim.limp.until).is_equal(went + Ticks.from_seconds(FixtureLobbyHit.LIMP_S))
	assert_array(FixtureCombatModes.received(game, P2, &"Correction")).is_not_empty()
	assert_array(_emitted(game, &"LaunchBody")).has_size(1)
	assert_array(_emitted(game, &"LaunchBody")[0].recipients).is_empty()
	_assert_no_life_events(game)
	for peer: int in [P1, P3]:
		var avatar: Dictionary = Snapshots.avatars_for(game.state, peer, went)[P2]
		assert_bool(avatar["limp"] as bool).is_true()
		assert_bool(avatar["downed"] as bool).is_false()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_knock_out_blow_launches_the_limp_body_as_a_knockdown_would() -> void:
	var made := FixtureLobbyHit.mode()
	var strike := _knife_strike(made)
	strike.launch_mps = 3.0
	var game := FixtureLobbyHit.armed(made, [P1, P2])
	FixtureLobbyHit.hit(game, 10)
	FixtureCombatModes.use(game, P1, FixtureLobbyHit.FACING, 11)
	var launched := _emitted(game, &"LaunchBody")
	assert_array(launched).has_size(1)
	var velocity := (launched[0].event as LaunchBodyEvent).velocity
	assert_vector(velocity).is_equal_approx(Vector3(0, 0, 3), Vector3(0.001, 0.001, 0.001))
	assert_vector(game.state.player(P2).velocity).is_equal(velocity)


func test_a_limp_player_is_not_hit_further() -> void:
	var game := FixtureLobbyHit.armed(FixtureLobbyHit.mode(), [P1, P2])
	FixtureLobbyHit.hit(game, 10)
	FixtureLobbyHit.hit(game, 11)
	var corrections := FixtureCombatModes.received(game, P2, &"Correction").size()
	FixtureCombatModes.use(game, P1, FixtureLobbyHit.FACING, 12)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureCombatModes.received(game, P1, &"Swung")).has_size(3)
	assert_array(FixtureCombatModes.received(game, P2, &"Damaged")).has_size(2)
	assert_int(game.state.player(P2).health).is_equal(0)
	assert_int(FixtureCombatModes.received(game, P2, &"Correction").size()).is_equal(corrections)
	assert_array(Array(game.diagnostics)).is_empty()


func test_it_gets_up_by_itself_with_full_health() -> void:
	var game := FixtureLobbyHit.armed(FixtureLobbyHit.mode(), [P1, P2])
	FixtureLobbyHit.hit(game, 10)
	FixtureCombatModes.use(game, P1, FixtureLobbyHit.FACING, 11)
	var victim := game.state.player(P2)
	var corrections := FixtureCombatModes.received(game, P2, &"Correction").size()
	FixtureModes.run_ticks(game, victim.limp.until - game.ticked_through() - 1)
	assert_bool(victim.is_limp()).is_true()
	assert_int(victim.health).is_equal(0)
	FixtureModes.run_ticks(game, 1)
	assert_bool(victim.is_limp()).is_false()
	assert_int(victim.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(victim.health).is_equal(HEALTH)
	var status := FixtureCombatModes.received(game, P2, &"SelfStatus")
	assert_int((status[-1] as SelfStatusEvent).health).is_equal(HEALTH)
	var after := FixtureCombatModes.received(game, P2, &"Correction").size()
	assert_int(after).is_equal(corrections + 1)
	# Long after: still standing, never downed, dead or respawned.
	FixtureModes.run_ticks(game, Ticks.from_seconds(40.0))
	assert_int(victim.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(victim.health).is_equal(HEALTH)
	_assert_no_life_events(game)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_countdown_end_gets_everyone_up_and_restores_health() -> void:
	var game := _limp_and_hurt(FixtureLobbyHit.mode())
	_through_countdown(game)
	assert_str(String(game.phase_id())).is_equal("loading")
	for peer: int in [P2, P3]:
		var player := game.state.player(peer)
		assert_bool(player.is_limp()).is_false()
		assert_int(player.health).is_equal(HEALTH)
		var status := FixtureCombatModes.received(game, peer, &"SelfStatus")
		assert_int((status[-1] as SelfStatusEvent).health).is_equal(HEALTH)
	_assert_no_life_events(game)
	assert_array(Array(game.diagnostics)).is_empty()


func test_without_restore_health_the_countdown_end_leaves_the_hurt_hurt() -> void:
	var game := _limp_and_hurt(FixtureLobbyHit.mode(false))
	_through_countdown(game)
	assert_str(String(game.phase_id())).is_equal("loading")
	# The hit's limp still gets up at full health; the merely hurt keep their health.
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	assert_int(game.state.player(P3).health).is_equal(HEALTH - HIT)


func test_a_placement_or_a_knockdown_ends_a_hits_limp() -> void:
	var game := FixtureLobbyHit.armed(FixtureLobbyHit.mode(), [P1, P2, P3])
	FixtureLobbyHit.hit(game, 10)
	FixtureLobbyHit.hit(game, 11)
	var ctx := _ctx(game)
	# A placement (PlacePlayers) ends the limp with no get-up: the player stands refilled.
	LifeRules.clear_limp(ctx, game.state.player(P2))
	assert_bool(game.state.player(P2).is_limp()).is_false()
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	# A knockdown (the tutorial's KnockDown) of a hit's limp keeps its 0: the downed are not healed.
	FixtureItemModes.stand(game, P2, Vector3(0, 0, -3))
	FixtureItemModes.stand(game, P3, FixtureLobbyHit.AT_P2)
	FixtureLobbyHit.hit(game, 12)
	FixtureLobbyHit.hit(game, 13)
	assert_bool(game.state.player(P3).is_limp()).is_true()
	LifeRules.knock_down(_ctx(game), P3)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(game.state.player(P3).health).is_equal(0)


func test_a_phase_without_hit_limp_still_knocks_down() -> void:
	var made := FixtureLobbyHit.mode()
	for phase_id: StringName in [&"lobby", &"countdown"]:
		made.find_phase(phase_id).hit_limp = null
	var game := FixtureLobbyHit.armed(made, [P1, P2])
	FixtureLobbyHit.hit(game, 10)
	FixtureCombatModes.use(game, P1, FixtureLobbyHit.FACING, 11)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_bool(game.state.player(P2).is_limp()).is_false()
	assert_array(FixtureCombatModes.received(game, P1, &"KnockedDown")).has_size(1)


func test_the_drinks_limp_gets_up_with_its_health() -> void:
	var game := FixtureLobbyHit.armed(FixtureLobbyHit.mode(), [P1, P2])
	FixtureLobbyHit.hit(game, 10)
	var drinker := game.state.player(P2)
	FixtureItemModes.stand(game, P2, FixtureBar.TAP + Vector3(0.3 * P2, 0, 0.5))
	FixtureLimp.drink_to_limp(game, P2)
	assert_bool(drinker.is_limp()).is_true()
	assert_bool(drinker.limp.refill).is_false()
	FixtureModes.run_ticks(game, drinker.limp.until - game.ticked_through())
	assert_bool(drinker.is_limp()).is_false()
	assert_int(drinker.health).is_equal(HEALTH - HIT)


func test_hit_limp_is_checked() -> void:
	var made := FixtureLobbyHit.mode()
	assert_array(Array(ModeCheck.run(made).errors)).is_empty()
	var lobby := made.find_phase(&"lobby")
	lobby.tick_systems = lobby.tick_systems.filter(
		func(s: TickSystem) -> bool: return not s is LimpTicks
	)
	assert_str(" ".join(lobby.check(made))).contains(
		"phase lobby: hit_limp needs a LimpTicks in its tick_systems"
	)
	var short := FixtureLobbyHit.mode()
	short.find_phase(&"countdown").hit_limp.limp_s = 0.1
	assert_str("\n".join(ModeCheck.run(short).errors)).contains("limp_s")


func test_the_same_seed_and_commands_give_the_same_hit_limp() -> void:
	var histories: Array[Array] = []
	for run in 2:
		var game := FixtureLobbyHit.armed(FixtureLobbyHit.mode(), [P1, P2, P3])
		FixtureLobbyHit.hit(game, 10)
		FixtureLobbyHit.hit(game, 11)
		FixtureModes.run_ticks(game, Ticks.from_seconds(FixtureLobbyHit.LIMP_S) + 2)
		histories.append(FixtureModes.describe(game))
	assert_array(histories[0]).is_equal(histories[1])


## P2 limp at 0 health and P3 hurt by one hit, everyone ready: the countdown runs.
func _limp_and_hurt(made: GameMode) -> Match:
	var game := FixtureLobbyHit.armed(made, [P1, P2, P3])
	# P3 takes one hit in P2's place, then P2 takes two: limp last, so its own time outlasts the
	# countdown.
	FixtureItemModes.stand(game, P2, FixtureLobbyHit.AT_P3)
	FixtureItemModes.stand(game, P3, FixtureLobbyHit.AT_P2)
	FixtureLobbyHit.hit(game, 10)
	FixtureItemModes.stand(game, P3, FixtureLobbyHit.AT_P3)
	FixtureItemModes.stand(game, P2, FixtureLobbyHit.AT_P2)
	FixtureLobbyHit.hit(game, 11)
	FixtureCombatModes.use(game, P1, FixtureLobbyHit.FACING, 12)
	assert_bool(game.state.player(P2).is_limp()).is_true()
	assert_int(game.state.player(P3).health).is_equal(HEALTH - HIT)
	for peer: int in [P1, P2, P3]:
		FixtureBaseMode.ready(game, peer, true, 300)
	return game


## The countdown runs out before the hit's limp would end by itself.
func _through_countdown(game: Match) -> void:
	assert_str(String(game.phase_id())).is_equal("countdown")
	FixtureModes.run_ticks(game, Ticks.from_seconds(5.0) + 2)


func _assert_no_life_events(game: Match) -> void:
	for peer: int in [P1, P2, P3]:
		if game.state.player(peer) == null:
			continue
		for event_name: StringName in LIFE_EVENTS:
			assert_array(game.view_of(peer).events_named(event_name)).is_empty()


func _knife_strike(made: GameMode) -> Strike:
	for effect: RuleEffect in made.find_item_kind(&"knife").actions[0].effects:
		if effect is Strike:
			return effect as Strike
	return null


func _ctx(game: Match) -> MatchContext:
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	return ctx


func _emitted(game: Match, event_name: StringName) -> Array[EmittedEvent]:
	var found: Array[EmittedEvent] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event.event_name() == event_name:
			found.append(emitted)
	return found
