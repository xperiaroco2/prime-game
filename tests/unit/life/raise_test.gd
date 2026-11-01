extends GdUnitTestSuite
## The raise, the revive and the give-up (ARCHITECTURE §3.4, §7.1, §9.4; vision revision 1, Revive
## and Give up; the engineer's answers 3, 4, 7 and 8 on PR #133): a living player raises a downed
## one by holding E for the raise time (RaiseDowned, a channel); the knockdown pauses meanwhile;
## the downed player's claims move nothing (KE4); every cancel stops it with RaiseStopped, which
## names no cause, and the knockdown runs on from where it paused; a completed raise revives the
## downed player where it lay (a placement: its Correction, KE6) with the revive health and 3 s of
## invulnerability, its stamina kept; a downed player may give up and dies at once. Driven by
## FixtureCombatModes.raising(): the knife (50 damage, 1.5 m, 30°), a raise of 3 s (60 ticks) within
## 2 m and in sight, 50 revive health, a knockdown of 10 s (200 ticks).

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const NORTH := Vector3(0, 0, 1)
## Where the downed P2 lies, and where P3 stands to raise it: 1.5 m apart, out of the knife's zone.
const LIES := Vector3(0, 0, 1)
const RAISER := Vector3(1.5, 0, 1)
const RAISE_TICKS := FixtureCombatModes.RAISE_TICKS
const KNOCKDOWN_TICKS := 200
const INVULNERABLE_TICKS := 60
const FULL := 100000
const REVIVED := 50000


func test_a_raise_pauses_the_knockdown_and_revives_where_it_lay_after_its_time() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	FixtureModes.run_ticks(game, 30)
	var left := downed.life_deadline - (game.ticked_through() + 1)
	FixtureCombatModes.raise(game, P3, P2)
	assert_int(downed.life_deadline).is_equal(-1)
	assert_int(downed.knockdown_left).is_equal(left)
	var lies := downed.position
	var epoch := downed.epoch
	FixtureModes.run_ticks(game, RAISE_TICKS - 1)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	FixtureModes.run_ticks(game, 1)
	assert_int(downed.life).is_equal(PlayerState.Life.ALIVE)
	assert_int(downed.health).is_equal(REVIVED)
	assert_int(downed.life_deadline).is_equal(-1)
	assert_int(downed.knockdown_left).is_equal(-1)
	assert_vector(downed.position).is_equal(lies)
	# A placement (KE6): a new epoch, so the claims it sent while downed are dropped as stale.
	assert_int(downed.epoch).is_equal(epoch + 1)
	assert_int(downed.invulnerable_until).is_equal(game.ticked_through() + INVULNERABLE_TICKS)
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_raise_events_reach_everyone_and_the_revived_player_gets_its_status() -> void:
	var game := _downed()
	# The knockdown's tick, with the hit's SelfStatus.
	FixtureModes.run_ticks(game, 1)
	var own_seen := game.view_of(P2).events.size()
	var others := {}
	for peer: int in [P1, P3]:
		others[peer] = FixtureMoves.corrections(game, peer).size()
	var lies := game.state.player(P2).position
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, RAISE_TICKS)
	for peer: int in [P1, P2, P3]:
		var started := FixtureCombatModes.received(game, peer, &"RaiseStarted")
		assert_array(started).has_size(1)
		assert_dict(started[0].to_dict()).is_equal({"raiser": P3, "target": P2})
		var revived := FixtureCombatModes.received(game, peer, &"Revived")
		assert_array(revived).has_size(1)
		assert_dict(revived[0].to_dict()).is_equal({"peer": P2})
		assert_array(FixtureCombatModes.received(game, peer, &"RaiseStopped")).is_empty()
	# Its Correction after Revived (KE6), to the revived player only: a new epoch where it lay, so
	# its client stands up where the host has it, not where its last walking claim was.
	assert_array(FixtureItemModes.names_after(game, P2, own_seen)).is_equal(
		[&"RaiseStarted", &"Revived", &"Correction", &"SelfStatus"]
	)
	var corrections := FixtureMoves.corrections(game, P2)
	var placed := corrections[corrections.size() - 1]
	# No facing (#1522): a revive is no placement on a marker, so the client keeps its look.
	(
		assert_dict(placed.to_dict())
		. is_equal(
			{
				"epoch": game.state.player(P2).epoch,
				"position": lies,
				"velocity": Vector3.ZERO,
				"facing": Vector3.ZERO,
			}
		)
	)
	for peer: int in [P1, P3]:
		assert_int(FixtureMoves.corrections(game, peer).size()).is_equal(others[peer])
	var statuses := FixtureMoves.statuses(game, P2)
	assert_int(statuses[statuses.size() - 1].health).is_equal(REVIVED)


func test_the_revive_keeps_the_stamina_and_grants_the_invulnerability() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	downed.stamina = 0
	downed.stamina_settled_tick = game.ticked_through()
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, RAISE_TICKS)
	assert_int(downed.life).is_equal(PlayerState.Life.ALIVE)
	# It regenerated while downed, as the downed do, and was not reset to full.
	assert_int(downed.stamina).is_greater(0)
	assert_int(downed.stamina).is_less(FULL)
	# A strike within the invulnerability does nothing; nothing ends it early.
	FixtureItemModes.stand(game, P1, downed.position - NORTH)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, INVULNERABLE_TICKS - 1)
	assert_int(downed.health).is_equal(REVIVED)
	assert_array(FixtureCombatModes.received(game, P2, &"Damaged")).has_size(2)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureCombatModes.received(game, P2, &"Damaged")).has_size(3)


func test_releasing_e_stops_it_and_the_knockdown_runs_on_from_where_it_paused() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	FixtureModes.run_ticks(game, 30)
	var left := downed.life_deadline - (game.ticked_through() + 1)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, RAISE_TICKS - 1)
	var seen := game.view_of(P1).events.size()
	FixtureCombatModes.stop_raise(game, P3)
	var stopped_at := game.ticked_through() + 1
	assert_int(downed.life_deadline).is_equal(stopped_at + left)
	assert_int(downed.knockdown_left).is_equal(-1)
	for peer: int in [P1, P2, P3]:
		var stopped := FixtureCombatModes.received(game, peer, &"RaiseStopped")
		assert_array(stopped).has_size(1)
		assert_dict(stopped[0].to_dict()).is_equal({"raiser": P3, "target": P2})
	FixtureModes.run_ticks(game, left)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	FixtureModes.run_ticks(game, 1)
	assert_int(downed.life).is_equal(PlayerState.Life.DEAD)
	# The fixture's task type notes the fact player_died.
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"Died", &"FixtureNote"]
	)
	assert_array(FixtureCombatModes.received(game, P2, &"Revived")).is_empty()


func test_the_knockdown_cannot_run_out_while_a_raise_pauses_it() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	FixtureModes.run_ticks(game, downed.life_deadline - game.ticked_through() - 2)
	FixtureCombatModes.raise(game, P3, P2)
	assert_int(downed.knockdown_left).is_equal(1)
	FixtureModes.run_ticks(game, RAISE_TICKS - 1)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	FixtureCombatModes.stop_raise(game, P3)
	FixtureModes.run_ticks(game, 1)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	FixtureModes.run_ticks(game, 1)
	assert_int(downed.life).is_equal(PlayerState.Life.DEAD)


func test_the_raiser_out_of_reach_stops_it_on_the_next_tick() -> void:
	var game := _downed()
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	FixtureItemModes.stand(game, P3, LIES + Vector3(2.01, 0, 0))
	FixtureModes.run_ticks(game, 1)
	_assert_stopped_once(game)
	assert_int(game.state.player(P2).life_deadline).is_greater(game.ticked_through())


func test_the_reach_includes_its_bound() -> void:
	var game := _downed()
	FixtureItemModes.stand(game, P3, LIES + Vector3(2, 0, 0))
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, RAISE_TICKS)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.ALIVE)


func test_losing_sight_stops_it_like_moving_out_of_reach() -> void:
	var world := FlatWorldQuery.new()
	var game := _downed(world)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	world.add_wall(AABB(Vector3(0.7, 0, 0), Vector3(0.1, 3, 2)))
	FixtureModes.run_ticks(game, 1)
	_assert_stopped_once(game)


func test_a_hit_on_the_raiser_stops_it_and_names_no_cause() -> void:
	var game := _downed()
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	var attacker_seen := game.view_of(P1).events.size()
	var raiser_seen := game.view_of(P3).events.size()
	FixtureItemModes.stand(game, P1, RAISER - NORTH)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureItemModes.names_after(game, P1, attacker_seen)).is_equal(
		[&"Swung", &"RaiseStopped"]
	)
	assert_array(FixtureItemModes.names_after(game, P3, raiser_seen)).is_equal(
		[&"Swung", &"Damaged", &"RaiseStopped"]
	)
	var stopped := FixtureCombatModes.received(game, P1, &"RaiseStopped")
	assert_dict(stopped[0].to_dict()).is_equal({"raiser": P3, "target": P2})
	assert_object(Channels.of_actor(game.state, P3)).is_null()


func test_the_raiser_knocked_down_stops_it_before_its_knockdown() -> void:
	var game := _downed()
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	game.state.player(P3).health = REVIVED
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	var seen := game.view_of(P1).events.size()
	FixtureItemModes.stand(game, P1, RAISER - NORTH)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"Swung", &"RaiseStopped", &"KnockedDown"]
	)
	assert_int(game.state.player(P3).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(game.state.player(P2).life_deadline).is_greater(game.ticked_through())


func test_a_pick_up_by_the_raiser_stops_it_before_the_item_moves() -> void:
	var game := _downed()
	var package := FixtureItemModes.lay(game, &"package", RAISER)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	var seen := game.view_of(P1).events.size()
	FixtureItemModes.pick_up(game, P3, package)
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"ItemPickedUp"]
	)


func test_a_put_down_by_the_raiser_stops_it() -> void:
	var game := _downed()
	var package := FixtureItemModes.lay(game, &"package", RAISER)
	FixtureItemModes.pick_up(game, P3, package)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	var seen := game.view_of(P1).events.size()
	FixtureItemModes.put_down(game, P3, NORTH)
	# The fixture notes the fact item_rested twice: its reaction and its task type.
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"ItemPlaced", &"FixtureNote", &"FixtureNote"]
	)


func test_a_use_by_the_raiser_stops_it() -> void:
	var game := _downed()
	var tool := FixtureItemModes.lay(game, &"tool", RAISER)
	FixtureItemModes.pick_up(game, P3, tool)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	var seen := game.view_of(P1).events.size()
	FixtureCombatModes.use(game, P3, NORTH)
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"FixtureNote"]
	)


func test_a_refused_action_of_the_raiser_stops_nothing() -> void:
	var game := _downed()
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	# An empty hand: PutDown is refused, and Use has no rule without an item.
	FixtureItemModes.put_down(game, P3, NORTH)
	FixtureCombatModes.use(game, P3, NORTH)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"empty_hand", &"nothing_to_do"])
	FixtureModes.run_ticks(game, RAISE_TICKS - 10)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.ALIVE)
	assert_array(FixtureCombatModes.received(game, P1, &"RaiseStopped")).is_empty()


func test_the_raiser_may_hold_the_package() -> void:
	var game := _downed()
	var package := FixtureItemModes.lay(game, &"package", RAISER)
	FixtureItemModes.pick_up(game, P3, package)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, RAISE_TICKS)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.ALIVE)
	assert_int(game.state.player(P3).held_item).is_equal(package.id)


func test_giving_up_while_raised_stops_the_raise_then_dies() -> void:
	var game := _downed()
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	var seen := game.view_of(P1).events.size()
	FixtureCombatModes.give_up(game, P2)
	# The fixture's task type notes the fact player_died.
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"Died", &"FixtureNote"]
	)
	var dead := game.state.player(P2)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_int(dead.life_deadline).is_equal(game.ticked_through() + 1 + 600)
	assert_dict(game.state.bodies).contains_keys([P2])
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_array(Array(game.diagnostics)).is_empty()


func test_giving_up_drops_the_held_item_at_the_body_and_respawns_later() -> void:
	var game := _downed()
	var dead := game.state.player(P2)
	var package := FixtureItemModes.lay(game, &"package", dead.position)
	package.where = ItemState.Where.HAND
	package.holder = P2
	dead.held_item = package.id
	FixtureCombatModes.give_up(game, P2)
	FixtureModes.run_ticks(game, 1)
	assert_int(dead.life).is_equal(PlayerState.Life.DEAD)
	assert_int(package.where).is_equal(ItemState.Where.GROUND)
	assert_vector(package.position).is_equal(game.state.bodies[P2])
	FixtureModes.run_ticks(game, dead.life_deadline - game.ticked_through())
	assert_int(dead.life).is_equal(PlayerState.Life.ALIVE)
	assert_array(FixtureCombatModes.received(game, P1, &"Respawned")).has_size(1)


func test_the_raiser_leaving_stops_it() -> void:
	var game := _downed()
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	var seen := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P3)
	# The fixture's task type notes the fact player_left.
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"PlayerLeft", &"FixtureNote"]
	)
	assert_int(game.state.player(P2).life_deadline).is_greater(game.ticked_through())


func test_the_downed_player_leaving_stops_it_and_leaves_no_body() -> void:
	var game := _downed()
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	var seen := game.view_of(P1).events.size()
	FixtureModes.send(game, Intents.PEER_LEFT, P2)
	# The fixture's task type notes the fact player_left.
	assert_array(FixtureItemModes.names_after(game, P1, seen)).is_equal(
		[&"RaiseStopped", &"PlayerLeft", &"FixtureNote"]
	)
	assert_dict(game.state.bodies).is_empty()
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	FixtureModes.run_ticks(game, RAISE_TICKS)
	assert_array(FixtureCombatModes.received(game, P1, &"Revived")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_rejections_name_their_reasons_to_the_sender_only() -> void:
	var game := _downed(null, [P1, P2, P3, P4])
	FixtureItemModes.stand(game, P4, LIES + Vector3(-1, 0, 0))
	FixtureCombatModes.raise(game, P3, P1)
	FixtureCombatModes.stop_raise(game, P3)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureCombatModes.raise(game, P4, P2)
	assert_array(FixtureModes.rejections(game, P3)).is_equal(
		[&"not_downed", &"not_channeling", &"busy"]
	)
	assert_array(FixtureModes.rejections(game, P4)).is_equal([&"busy"])
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	# Still one raise, P3's.
	assert_array(FixtureCombatModes.received(game, P1, &"RaiseStarted")).has_size(1)


func test_a_raise_out_of_reach_or_out_of_sight_is_refused() -> void:
	var world := FlatWorldQuery.new()
	var game := _downed(world)
	FixtureItemModes.stand(game, P3, LIES + Vector3(2.01, 0, 0))
	FixtureCombatModes.raise(game, P3, P2)
	FixtureItemModes.stand(game, P3, RAISER)
	world.add_wall(AABB(Vector3(0.7, 0, 0), Vector3(0.1, 3, 2)))
	FixtureCombatModes.raise(game, P3, P2)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"out_of_reach", &"blocked"])
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_int(game.state.player(P2).life_deadline).is_greater(0)


func test_a_raise_of_a_player_who_is_not_there_is_refused() -> void:
	var game := _downed()
	FixtureCombatModes.raise(game, P3, 999)
	FixtureModes.send(game, Intents.RAISE, P3, {})
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"not_downed", &"not_downed"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_round_accepts_the_raise_from_the_living_and_the_give_up_from_the_downed() -> void:
	var game := _downed()
	FixtureCombatModes.give_up(game, P3)
	FixtureCombatModes.raise(game, P2, P2)
	FixtureCombatModes.stop_raise(game, P2)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"not_accepted"])
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"not_accepted", &"not_accepted"])
	FixtureCombatModes.give_up(game, P2)
	FixtureCombatModes.give_up(game, P2)
	FixtureCombatModes.raise(game, P2, P1)
	# The dead send no accepted intent.
	assert_array(FixtureModes.rejections(game, P2)).is_equal(
		[&"not_accepted", &"not_accepted", &"not_accepted", &"not_accepted"]
	)


func test_the_downed_players_claims_move_it_neither_while_a_raise_runs_nor_after() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	var lies := downed.position
	FixtureMoves.claim(game, P2, lies)
	FixtureModes.run_ticks(game, 1)
	FixtureCombatModes.raise(game, P3, P2)
	var corrected := FixtureMoves.corrections(game, P2).size()
	# A claim where it lies and one a step away: neither moves it and neither is corrected (KE4).
	FixtureMoves.claim(game, P2, lies)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.claim(game, P2, lies + Vector3(0.04, 0, 0))
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(corrected)
	assert_vector(downed.position).is_equal(lies)
	# After the raise stops, no more either: it holds still (KE4).
	FixtureCombatModes.stop_raise(game, P3)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.claim(game, P2, lies + Vector3(0.04, 0, 0))
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(corrected)
	assert_vector(downed.position).is_equal(lies)


func test_a_raise_restarted_again_and_again_cannot_move_the_downed_player() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	var lies := downed.position
	FixtureMoves.claim(game, P2, lies)
	FixtureModes.run_ticks(game, 1)
	var left := downed.life_deadline - (game.ticked_through() + 1)
	var corrected := FixtureMoves.corrections(game, P2).size()
	for cycle in 5:
		FixtureCombatModes.raise(game, P3, P2)
		for i in RAISE_TICKS - 1:
			# The downed client claims a step on every tick: each moves nothing.
			FixtureMoves.claim(game, P2, downed.position + Vector3(0.05, 0, 0))
			FixtureModes.run_ticks(game, 1)
		# Stopped just short, and started again in the same host tick.
		FixtureCombatModes.stop_raise(game, P3)
		FixtureCombatModes.raise(game, P3, P2)
		FixtureMoves.claim(game, P2, downed.position + Vector3(0.05, 0, 0))
		FixtureModes.run_ticks(game, 1)
		FixtureCombatModes.stop_raise(game, P3)
	assert_vector(downed.position).is_equal(lies)
	assert_int(FixtureMoves.corrections(game, P2).size()).is_equal(corrected)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	# The pause held: what was left of the knockdown is still left.
	assert_int(downed.life_deadline).is_equal(game.ticked_through() + 1 + left)
	assert_array(FixtureCombatModes.received(game, P1, &"Revived")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_small_claims_do_not_add_up_to_a_move() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	var lies := downed.position
	FixtureMoves.claim(game, P2, lies)
	FixtureModes.run_ticks(game, 1)
	FixtureCombatModes.raise(game, P3, P2)
	# Claims 0.8 mm past each last one, through the raise: the downed player stays where it lies.
	var step := Vector3(0.0008, 0, 0)
	for i in 20:
		FixtureMoves.claim(game, P2, lies + step * (i + 1))
		FixtureModes.run_ticks(game, 1)
	assert_vector(downed.position).is_equal(lies)


func test_a_raise_running_when_the_round_ends_stops_before_the_phase_changes() -> void:
	var game := _downed()
	var downed := game.state.player(P2)
	FixtureCombatModes.raise(game, P3, P2)
	FixtureModes.run_ticks(game, 10)
	game.state.add_to_counter(0, &"crew_win", 1)
	FixtureModes.run_ticks(game, 1)
	assert_str(String(game.phase_id())).is_equal("end")
	_assert_stopped_once(game)
	for peer: int in [P1, P2, P3]:
		var names := game.view_of(peer).event_names()
		var stopped := names.rfind(&"RaiseStopped")
		assert_int(stopped).is_greater_equal(0)
		assert_int(stopped).is_less(names.rfind(&"PhaseChanged"))
	# The knockdown it paused runs on: no channel targets it any more.
	assert_int(downed.life_deadline).is_greater(game.ticked_through())
	assert_object(Channels.on_target(game.state, P2)).is_null()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_stop_gives_no_deadline_to_a_downed_player_whose_knockdown_it_did_not_pause() -> void:
	# Through a match every knockdown has a deadline; RaiseDowned's own guard keeps a stop from
	# inventing one for a downed player whose knockdown never ran (life_deadline -1, set by hand).
	var game := _downed()
	var downed := game.state.player(P2)
	downed.life_deadline = -1
	var ctx := _context(game)
	var channel := _raise_channel()
	channel.effect.started(ctx, channel)
	assert_int(downed.knockdown_left).is_equal(-1)
	channel.effect.stopped(ctx, channel)
	assert_int(downed.life_deadline).is_equal(-1)
	assert_int(downed.knockdown_left).is_equal(-1)
	assert_int(downed.life).is_equal(PlayerState.Life.DOWNED)
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_stop_restarts_the_knockdown_only_of_a_player_still_downed() -> void:
	# Every life change stops the raise first (LifeRules), so its target is still downed when it
	# stops; RaiseDowned's own guard keeps a player who is not (left, set by hand) from getting a
	# deadline, which LifeTicks would report as a rule error.
	var game := _downed()
	var downed := game.state.player(P2)
	var ctx := _context(game)
	var channel := _raise_channel()
	channel.effect.started(ctx, channel)
	assert_int(downed.knockdown_left).is_greater(0)
	downed.life = PlayerState.Life.LEFT
	channel.effect.stopped(ctx, channel)
	assert_int(downed.life_deadline).is_equal(-1)
	assert_int(downed.knockdown_left).is_equal(-1)
	FixtureModes.run_ticks(game, KNOCKDOWN_TICKS + 1)
	assert_int(downed.life).is_equal(PlayerState.Life.LEFT)
	assert_array(Array(game.diagnostics)).is_empty()


## P1 (armed at the origin) knocks P2 down at LIES with two hits the cooldown apart; P3 stands at
## RAISER, 1.5 m from P2. Returns the match before the second hit's tick runs.
func _downed(world: WorldQuery = null, peers: Array[int] = [P1, P2, P3]) -> Match:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.raising(), peers, world)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, LIES)
	FixtureItemModes.stand(game, P3, RAISER)
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	return game


func _assert_stopped_once(game: Match) -> void:
	var stopped := FixtureCombatModes.received(game, P1, &"RaiseStopped")
	assert_array(stopped).has_size(1)
	assert_dict(stopped[0].to_dict()).is_equal({"raiser": P3, "target": P2})
	assert_object(Channels.of_actor(game.state, P3)).is_null()
	assert_int(game.state.player(P2).knockdown_left).is_equal(-1)


## A context of `game`'s next host tick, as a part called from the loop gets it.
func _context(game: Match) -> MatchContext:
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = game.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = game.ticked_through() + 1
	return ctx


## P3's raise of P2 with the fixture's RaiseDowned, not started: the effect is called directly.
func _raise_channel() -> Channel:
	var rule := FixtureCombatModes.raise_rule()
	var channel := Channel.new()
	channel.effect = rule.effects[0] as RaiseDowned
	channel.rule = rule
	channel.actor = P3
	channel.target = P2
	return channel
