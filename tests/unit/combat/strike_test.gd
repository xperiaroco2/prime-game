extends GdUnitTestSuite
## Strike (ARCHITECTURE §7.1 "Hits", §9.4) through the knife's Use (FixtureCombatModes: 30°,
## 1.5 m, 50 damage; capsules of 0.4 m by 1.8 m): the targets the host picks (reach, angle,
## vertical overlap, line of sight from the eye, living only, never the attacker), the damage in
## peer-id order, and who learns what: Swung everyone, Damaged and the health only the victim.
## The cooldown: cooldown_test.gd. Death: tests/unit/life/life_rules_test.gd.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
const NORTH := Vector3(0, 0, 1)
const HEALTH := 100000
const HALF := 50000


func test_a_hit_damages_the_target_and_only_the_victim_learns_it() -> void:
	var game := _armed([P1, P2, P3])
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureItemModes.stand(game, P3, Vector3(4, 0, 4))
	FixtureModes.run_ticks(game, 1)
	var seen: Dictionary[int, int] = {}
	for peer: int in [P1, P2, P3]:
		seen[peer] = game.view_of(peer).events.size()
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.player(P2).health).is_equal(HALF)
	assert_array(FixtureItemModes.names_after(game, P2, seen[P2])).is_equal(
		[&"Swung", &"Damaged", &"SelfStatus"]
	)
	var damaged := FixtureCombatModes.received(game, P2, &"Damaged")[0]
	assert_dict(damaged.to_dict()).is_equal({"amount": HALF, "health": HALF})
	var status := FixtureMoves.statuses(game, P2)
	assert_int(status[status.size() - 1].health).is_equal(HALF)
	# The attacker gets its swing and its own stamina, no confirmation of the hit.
	assert_array(FixtureItemModes.names_after(game, P1, seen[P1])).is_equal(
		[&"Swung", &"SelfStatus"]
	)
	var own := FixtureMoves.statuses(game, P1)
	assert_int(own[own.size() - 1].health).is_equal(HEALTH)
	assert_int(own[own.size() - 1].stamina).is_equal(75000)
	assert_array(FixtureItemModes.names_after(game, P3, seen[P3])).is_equal([&"Swung"])


func test_swung_goes_to_everyone_even_when_it_touches_nobody() -> void:
	var game := _armed([P1, P2])
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 3))
	FixtureCombatModes.use(game, P1, NORTH)
	for peer: int in [P1, P2]:
		var swung := FixtureCombatModes.received(game, peer, &"Swung")
		assert_array(swung).has_size(1)
		assert_dict(swung[0].to_dict()).is_equal({"peer": P1, "facing": NORTH})
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	assert_array(FixtureCombatModes.received(game, P2, &"Damaged")).is_empty()


func test_the_reach_counts_to_the_nearest_point_of_the_capsule() -> void:
	# Reach 1.5 m plus the capsule's radius 0.4 m.
	assert_array(_hit_at(Vector3(0, 0, 1.89))).is_equal([P2])
	assert_array(_hit_at(Vector3(0, 0, 1.91))).is_empty()


func test_the_angle_counts_to_the_nearest_point_of_the_capsule() -> void:
	# 1 m ahead, the edge of the 30° zone (15° either side) passes 0.259 m to the side; a capsule
	# of 0.4 m touches it while its centre is within 0.682 m of the facing line.
	assert_array(_hit_at(Vector3(0.66, 0, 1))).is_equal([P2])
	assert_array(_hit_at(Vector3(-0.66, 0, 1))).is_equal([P2])
	assert_array(_hit_at(Vector3(0.7, 0, 1))).is_empty()
	assert_array(_hit_at(Vector3(-0.7, 0, 1))).is_empty()
	# Behind the attacker only an overlapping capsule touches the zone's apex.
	assert_array(_hit_at(Vector3(0, 0, -1))).is_empty()
	assert_array(_hit_at(Vector3(0, 0, -0.39))).is_equal([P2])


func test_a_wide_weapon_hits_all_around() -> void:
	var mode := FixtureCombatModes.basic()
	mode.find_item_kind(&"knife").actions = [FixtureCombatModes.knife_rule(360.0, 1.5, 50)]
	var game := _armed([P1, P2, P3], mode)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, -1.8))
	FixtureItemModes.stand(game, P3, Vector3(1.9, 0, 0.1))
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HALF)
	assert_int(game.state.player(P3).health).is_equal(HEALTH)


func test_a_target_must_overlap_the_attacker_vertically() -> void:
	var world := FixtureTerrainWorld.new().add_platform(-1, 0.5, 1, 2, 1.8)
	var game := _armed([P1, P2, P3], null, world)
	# Both on platforms higher than the attacker: 1.8 m up still overlaps, 1.9 m does not.
	FixtureItemModes.stand(game, P2, Vector3(0, 1.8, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HALF)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureItemModes.stand(game, P2, Vector3(0, 1.9, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HALF)


func test_a_wall_between_blocks_the_hit_and_a_low_one_does_not() -> void:
	var world := FlatWorldQuery.new().add_wall(AABB(Vector3(-2, 0, 0.5), Vector3(4, 3, 0.1)))
	var game := _armed([P1, P2], null, world)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	assert_array(FixtureCombatModes.received(game, P2, &"Swung")).has_size(1)
	var low := FlatWorldQuery.new().add_wall(AABB(Vector3(-2, 0, 0.5), Vector3(4, 0.5, 0.1)))
	game = _armed([P1, P2], null, low)
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HALF)


func test_every_living_player_in_the_zone_is_hit_in_peer_id_order_but_ghosts_are_not() -> void:
	var game := _armed([P1, P2, P3, P4])
	# P3 is nearer than P2, and P4 is a ghost in the zone.
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1.4))
	FixtureItemModes.stand(game, P3, Vector3(0.1, 0, 0.7))
	FixtureItemModes.stand(game, P4, Vector3(-0.1, 0, 0.9))
	game.state.player(P4).life = PlayerState.Life.GHOST
	FixtureCombatModes.use(game, P1, NORTH)
	var victims: Array[int] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event is DamagedEvent:
			victims.append((emitted.event as DamagedEvent).peer)
	assert_array(victims).is_equal([P2, P3])
	assert_int(game.state.player(P1).health).is_equal(HEALTH)
	assert_int(game.state.player(P4).health).is_equal(HEALTH)
	for peer: int in [P2, P3]:
		assert_array(FixtureCombatModes.received(game, peer, &"Damaged")).has_size(1)
	# No victim learns of the other's damage.
	assert_array(FixtureCombatModes.received(game, P1, &"Damaged")).is_empty()
	assert_array(FixtureCombatModes.received(game, P4, &"Damaged")).is_empty()


func test_the_facing_is_the_uses_and_without_a_finite_one_the_last_claims() -> void:
	var game := _armed([P1, P2])
	FixtureItemModes.stand(game, P2, Vector3(1, 0, 0))
	game.state.player(P1).facing = Vector3(1, 0, 0)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureModes.send(game, Intents.USE, P1)
	assert_int(game.state.player(P2).health).is_equal(HALF)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, Vector3(NAN, 0, 1))
	assert_int(game.state.player(P2).health).is_equal(0)
	var swung := FixtureCombatModes.received(game, P2, &"Swung")
	assert_vector((swung[1] as SwungEvent).facing).is_equal(Vector3(1, 0, 0))
	assert_vector((swung[2] as SwungEvent).facing).is_equal(Vector3(1, 0, 0))


func test_a_facing_straight_down_touches_only_an_overlapping_capsule() -> void:
	var game := _armed([P1, P2, P3])
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 0.3))
	FixtureItemModes.stand(game, P3, Vector3(0, 0, -1))
	FixtureCombatModes.use(game, P1, Vector3.DOWN)
	assert_int(game.state.player(P2).health).is_equal(HALF)
	assert_int(game.state.player(P3).health).is_equal(HEALTH)
	# The zone had no direction, and Swung says so rather than relaying the claim.
	var swung := FixtureCombatModes.received(game, P3, &"Swung")
	assert_vector((swung[0] as SwungEvent).facing).is_equal(Vector3.ZERO)


func test_swung_carries_the_zones_horizontal_unit_direction_not_the_raw_claim() -> void:
	var game := _armed([P1, P2])
	FixtureItemModes.stand(game, P2, Vector3(1, 0, 0))
	game.state.player(P1).facing = Vector3(1, 0, 0)
	# A zero facing counts as none: the last claim's facing strikes P2.
	FixtureCombatModes.use(game, P1, Vector3.ZERO)
	assert_int(game.state.player(P2).health).is_equal(HALF)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	# A huge finite facing, tilted down, still gives a horizontal unit vector.
	FixtureCombatModes.use(game, P1, Vector3(3e38, -3e38, 3e38))
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	FixtureCombatModes.use(game, P1, Vector3(0, 0.5, 2))
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	var swung := FixtureCombatModes.received(game, P2, &"Swung")
	assert_array(swung).has_size(3)
	var diagonal := Vector3(1, 0, 1).normalized()
	assert_vector((swung[0] as SwungEvent).facing).is_equal(Vector3(1, 0, 0))
	assert_vector((swung[1] as SwungEvent).facing).is_equal_approx(diagonal, Vector3.ONE * 1e-6)
	assert_vector((swung[2] as SwungEvent).facing).is_equal(NORTH)


func test_a_tired_attacker_is_refused_and_pays_nothing() -> void:
	var game := _armed([P1, P2])
	FixtureItemModes.stand(game, P2, Vector3(0, 0, 1))
	var attacker := game.state.player(P1)
	attacker.stamina = 20000
	attacker.stamina_settled_tick = game.ticked_through() + 1
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"tired"])
	assert_int(attacker.stamina).is_equal(20000)
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	assert_array(FixtureCombatModes.received(game, P2, &"Swung")).is_empty()


func test_the_mode_check_refuses_numbers_the_data_did_not_set() -> void:
	var check := ModeCheck.run(FixtureCombatModes.basic())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()
	var mode := FixtureCombatModes.basic()
	mode.find_item_kind(&"knife").actions = [
		FixtureModes.rule(Intents.USE, [Cooldown.new()], [Strike.new()])
	]
	var errors := ";".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Cooldown has no key")
	assert_str(errors).contains("Strike angle_deg is 0, outside 1 to 360")
	assert_str(errors).contains("Strike reach_m is 0, outside 0.1 to 10")
	assert_str(errors).contains("Strike damage is 0, outside 1 to 1000")
	mode.find_item_kind(&"knife").actions = [
		FixtureCombatModes.knife_rule(361.0, 10.5, 1001, 600.5)
	]
	errors = ";".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Cooldown seconds is 600.5, outside 0 to 600")
	assert_str(errors).contains("Strike angle_deg is 361, outside 1 to 360")
	assert_str(errors).contains("Strike reach_m is 10.5, outside 0.1 to 10")
	assert_str(errors).contains("Strike damage is 1001, outside 1 to 1000")


## A round of `peers` (of `mode`, the knife mode when null, in `world`) with P1 at the origin
## holding a knife.
func _armed(peers: Array[int], mode: GameMode = null, world: WorldQuery = null) -> Match:
	var used := mode if mode != null else FixtureCombatModes.basic()
	var game := FixtureCombatModes.in_round(used, peers, world)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	return game


## The peers P1's knife hits facing north with P2 at `at`.
func _hit_at(at: Vector3) -> Array[int]:
	var game := _armed([P1, P2])
	FixtureItemModes.stand(game, P2, at)
	FixtureCombatModes.use(game, P1, NORTH)
	var victims: Array[int] = []
	if game.state.player(P2).health < HEALTH:
		victims.append(P2)
	return victims
