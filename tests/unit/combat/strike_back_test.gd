extends GdUnitTestSuite
## The hit from behind and the fallback hit (#1437, ARCHITECTURE §7.1.10, §9.4 Strike): a target
## whose rear half holds the attacker (the angle between its facing and the direction to the
## attacker over 90°, the engineer's answer on #1437) takes `back_damage`; a hand without its own
## Use rule (empty, or an item kind with none) hits by the mode's rule, the two-handed pair while a
## two-handed item is in the hand. FixtureCombatModes.fisting(): the knife's zone, cooldown and
## stamina; 5 front, 10 back, two-handed 20 and 40. Health 100.

const P1 := 1
const P2 := 2
const P3 := 3
const NORTH := Vector3(0, 0, 1)
const SOUTH := Vector3(0, 0, -1)
const EAST := Vector3(1, 0, 0)
const HEALTH := 100000
## P2's spot: 1 m north of P1 at the origin, in the zone of a hit facing north.
const AHEAD := Vector3(0, 0, 1)


func test_a_hit_from_behind_takes_the_back_damage() -> void:
	# P2 faces away from P1 (north): P1 stands in its rear half.
	assert_int(_taken(FixtureCombatModes.fisting(), NORTH)).is_equal(FixtureCombatModes.FIST_BACK)


func test_a_hit_from_the_front_takes_the_front_damage() -> void:
	assert_int(_taken(FixtureCombatModes.fisting(), SOUTH)).is_equal(FixtureCombatModes.FIST)


func test_a_target_that_never_claimed_a_facing_faces_forward() -> void:
	# Vector3.FORWARD is south (-z): P1 south of P2 is in front, P1 north of it behind.
	assert_int(_taken(FixtureCombatModes.fisting(), Vector3.ZERO)).is_equal(FixtureCombatModes.FIST)
	var game := FixtureCombatModes.in_round(FixtureCombatModes.fisting(), [P1, P2])
	FixtureItemModes.stand(game, P1, Vector3(0, 0, 2))
	FixtureItemModes.stand(game, P2, AHEAD)
	FixtureCombatModes.use(game, P1, SOUTH)
	assert_int(_lost(game)).is_equal(FixtureCombatModes.FIST_BACK)


func test_exactly_ninety_degrees_is_the_front_and_one_more_is_the_back() -> void:
	# P2 faces east, P1 straight south of it: 90°, the front.
	assert_int(_taken(FixtureCombatModes.fisting(), EAST)).is_equal(FixtureCombatModes.FIST)
	# Turned 1° to the north, away from P1: 91°.
	var turned := EAST.rotated(Vector3.UP, deg_to_rad(-1.0))
	assert_float(turned.z).is_greater(0.0)
	assert_int(_taken(FixtureCombatModes.fisting(), turned)).is_equal(FixtureCombatModes.FIST_BACK)
	# 89°, towards P1: the front.
	var towards := EAST.rotated(Vector3.UP, deg_to_rad(1.0))
	assert_int(_taken(FixtureCombatModes.fisting(), towards)).is_equal(FixtureCombatModes.FIST)


func test_back_damage_zero_means_the_front_damage() -> void:
	var mode := FixtureCombatModes.basic()
	mode.actions.append(FixtureCombatModes.fist_rule(7, 0, 0, 0))
	assert_int(_taken(mode, NORTH)).is_equal(7)
	# The knife's own rule sets no back damage: from behind it deals its front damage.
	assert_int(_taken(FixtureCombatModes.fisting(), NORTH, &"knife")).is_equal(
		FixtureCombatModes.DAMAGE
	)


func test_no_horizontal_facing_or_the_same_spot_is_the_front() -> void:
	# A MoveClaim always stores a horizontal part (MovementRule.stored_facing); only the state can
	# hold a facing straight up, which is_behind takes as the front.
	var game := FixtureCombatModes.in_round(FixtureCombatModes.fisting(), [P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, AHEAD)
	game.state.player(P2).facing = Vector3.UP
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(_lost(game)).is_equal(FixtureCombatModes.FIST)
	var attacker := PlayerState.new(P1, "p1")
	var target := PlayerState.new(P2, "p2")
	target.position = Vector3(3, 0, 4)
	attacker.position = Vector3(3, 0, 4)
	target.facing = NORTH
	assert_bool(Strike.is_behind(attacker, target)).is_false()
	attacker.position = Vector3(3, 5, 3)
	assert_bool(Strike.is_behind(attacker, target)).is_true()
	attacker.position = Vector3(3, 0, 5)
	assert_bool(Strike.is_behind(attacker, target)).is_false()


func test_a_two_handed_hand_takes_the_two_handed_pair() -> void:
	# The package: two-handed, no actions of its own.
	var mode := FixtureCombatModes.fisting()
	assert_int(_taken(mode, SOUTH, &"package")).is_equal(FixtureCombatModes.TWO_HANDED)
	assert_int(_taken(mode, NORTH, &"package")).is_equal(FixtureCombatModes.TWO_HANDED_BACK)


func test_the_empty_hand_and_a_one_handed_item_without_a_use_rule_take_the_base() -> void:
	var mode := FixtureCombatModes.fisting()
	mode.item_kinds.append(FixtureItemModes.item_kind(&"cup", []))
	for kind: StringName in [&"", &"cup"]:
		assert_int(_taken(mode, SOUTH, kind)).is_equal(FixtureCombatModes.FIST)
		assert_int(_taken(mode, NORTH, kind)).is_equal(FixtureCombatModes.FIST_BACK)


func test_two_handed_back_zero_means_the_two_handed_front() -> void:
	var mode := FixtureCombatModes.basic()
	mode.actions.append(FixtureCombatModes.fist_rule(5, 10, 20, 0))
	assert_int(_taken(mode, NORTH, &"package")).is_equal(20)


func test_no_two_handed_pair_leaves_a_two_handed_hand_the_base_pair() -> void:
	# The pair is picked first, then its back value: a two-handed hand with no two-handed pair hits
	# from behind by back_damage, not by damage.
	var mode := FixtureCombatModes.basic()
	mode.actions.append(FixtureCombatModes.fist_rule(50, 75, 0, 0))
	assert_int(_taken(mode, NORTH, &"package")).is_equal(75)
	assert_int(_taken(mode, SOUTH, &"package")).is_equal(50)


func test_a_kind_with_its_own_use_rule_overrides_the_mode_fallback() -> void:
	assert_int(_taken(FixtureCombatModes.fisting(), SOUTH, &"knife")).is_equal(
		FixtureCombatModes.DAMAGE
	)
	# The tool's own Use notes "tool used" and strikes nobody.
	var game := FixtureCombatModes.in_round(FixtureCombatModes.fisting(), [P1, P2])
	_hold(game, &"tool")
	FixtureItemModes.stand(game, P2, AHEAD)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(_lost(game)).is_equal(0)
	assert_array(FixtureModes.notes(game)).contains(["tool used"])


func test_a_knife_on_the_belt_does_not_count_the_empty_hand_hits_by_the_fallback() -> void:
	var game := FixtureCombatModes.in_round(
		FixtureItemModes.swapping(FixtureCombatModes.fisting()), [P1, P2]
	)
	_hold(game, &"knife")
	FixtureItemModes.swap(game, P1)
	assert_int(game.state.player(P1).held_item).is_equal(-1)
	assert_int(game.state.player(P1).belt_item).is_not_equal(-1)
	FixtureItemModes.stand(game, P2, AHEAD)
	_face(game, P2, SOUTH)
	FixtureCombatModes.use(game, P1, NORTH, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_int(_lost(game)).is_equal(FixtureCombatModes.FIST)
	# From behind: the fallback's 10, not the knife's 75.
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	game.state.player(P2).health = HEALTH
	_face(game, P2, NORTH)
	FixtureCombatModes.use(game, P1, NORTH, 2)
	assert_int(_lost(game)).is_equal(FixtureCombatModes.FIST_BACK)


func test_an_empty_hand_use_swings_where_the_mode_has_a_use_rule_else_nothing_to_do() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.fisting(), [P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, Vector3(5, 0, 5))
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureCombatModes.received(game, P2, &"Swung")).has_size(1)
	var bare := FixtureCombatModes.in_round(FixtureCombatModes.basic(), [P1, P2])
	FixtureCombatModes.use(bare, P1, NORTH)
	assert_array(FixtureModes.rejections(bare, P1)).is_equal([&"nothing_to_do"])
	assert_array(FixtureCombatModes.received(bare, P2, &"Swung")).is_empty()


func test_a_tired_fist_is_refused_and_the_hit_cooldown_is_shared_with_the_knife() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.fisting(), [P1, P2])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, AHEAD)
	var attacker := game.state.player(P1)
	attacker.stamina = FixtureCombatModes.STAMINA_COST * 1000 - 1000
	attacker.stamina_settled_tick = game.ticked_through() + 1
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"tired"])
	assert_int(_lost(game)).is_equal(0)
	attacker.stamina = HEALTH
	attacker.stamina_settled_tick = game.ticked_through() + 1
	FixtureCombatModes.use(game, P1, NORTH, 1)
	assert_int(_lost(game)).is_equal(FixtureCombatModes.FIST)
	# A knife taken into the hand right after: its hit waits for the same `hit` interval.
	var knife := FixtureItemModes.lay(game, &"knife", Vector3.ZERO)
	FixtureItemModes.pick_up(game, P1, knife, 2)
	assert_int(knife.holder).is_equal(P1)
	FixtureCombatModes.use(game, P1, NORTH, 3)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"tired", &"too_soon"])
	assert_int(_lost(game)).is_equal(FixtureCombatModes.FIST)


func test_the_limp_the_downed_and_the_invulnerable_are_not_hit_by_a_fist() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.fisting(), [P1, P2, P3])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, AHEAD)
	FixtureItemModes.stand(game, P3, Vector3(0.3, 0, 1))
	game.state.player(P2).life = PlayerState.Life.DOWNED
	game.state.player(P3).invulnerable_until = game.ticked_through() + 2
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	assert_int(game.state.player(P3).health).is_equal(HEALTH)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS)
	game.state.player(P3).limp = LimpState.new(game.ticked_through() + 1000)
	FixtureCombatModes.use(game, P1, NORTH, 1)
	assert_int(game.state.player(P3).health).is_equal(HEALTH)
	assert_array(FixtureCombatModes.received(game, P3, &"Damaged")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_fist_that_empties_health_knocks_down_and_the_victim_keeps_its_item() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.fisting(), [P1, P2, P3])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	var tool := FixtureItemModes.lay(game, &"tool", AHEAD)
	FixtureItemModes.stand(game, P2, AHEAD)
	FixtureItemModes.pick_up(game, P2, tool)
	assert_int(tool.holder).is_equal(P2)
	FixtureItemModes.stand(game, P3, Vector3(6, 0, 6))
	game.state.player(P2).health = FixtureCombatModes.FIST * 1000
	FixtureCombatModes.use(game, P1, NORTH)
	assert_int(game.state.player(P2).life).is_equal(PlayerState.Life.DOWNED)
	assert_int(game.state.player(P2).held_item).is_equal(tool.id)
	assert_int(tool.holder).is_equal(P2)
	for peer: int in [P1, P2, P3]:
		assert_array(FixtureCombatModes.received(game, peer, &"KnockedDown")).has_size(1)


func test_a_fists_events_reach_whom_the_knifes_do() -> void:
	var game := FixtureCombatModes.in_round(FixtureCombatModes.fisting(), [P1, P2, P3])
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, AHEAD)
	FixtureItemModes.stand(game, P3, Vector3(6, 0, 6))
	_face(game, P2, NORTH)
	FixtureModes.run_ticks(game, 1)
	var seen: Dictionary[int, int] = {}
	for peer: int in [P1, P2, P3]:
		seen[peer] = game.view_of(peer).events.size()
	FixtureCombatModes.use(game, P1, NORTH)
	# SelfStatus goes out at the end of the tick (SelfStatusFeed.flush).
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureItemModes.names_after(game, P1, seen[P1])).is_equal(
		[&"Swung", &"SelfStatus"]
	)
	assert_array(FixtureItemModes.names_after(game, P2, seen[P2])).is_equal(
		[&"Swung", &"Damaged", &"SelfStatus"]
	)
	assert_array(FixtureItemModes.names_after(game, P3, seen[P3])).is_equal([&"Swung"])
	var damaged := FixtureCombatModes.received(game, P2, &"Damaged")[0]
	var back := FixtureCombatModes.FIST_BACK * 1000
	assert_dict(damaged.to_dict()).is_equal({"amount": back, "health": HEALTH - back})


func test_the_mode_check_bounds_the_back_and_two_handed_damage() -> void:
	var check := ModeCheck.run(FixtureCombatModes.fisting())
	assert_array(Array(check.errors)).is_empty()
	assert_array(Array(check.warnings)).is_empty()
	var mode := FixtureCombatModes.basic()
	mode.actions.append(FixtureCombatModes.fist_rule(5, 1001, 1001, 1001))
	var errors := ";".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Strike back_damage is 1001, outside 0 to 1000")
	assert_str(errors).contains("Strike two_handed_damage is 1001, outside 0 to 1000")
	assert_str(errors).contains("Strike two_handed_back_damage is 1001, outside 0 to 1000")
	mode = FixtureCombatModes.basic()
	mode.actions.append(FixtureCombatModes.fist_rule(5, -1, -1, -1))
	errors = ";".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("Strike back_damage is -1, outside 0 to 1000")
	assert_str(errors).contains("Strike two_handed_damage is -1, outside 0 to 1000")
	assert_str(errors).contains("Strike two_handed_back_damage is -1, outside 0 to 1000")
	# A two-handed back value beside no two-handed front value would be ignored: say so.
	mode = FixtureCombatModes.basic()
	mode.actions.append(FixtureCombatModes.fist_rule(5, 10, 0, 40))
	errors = ";".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("two_handed_back_damage is set but two_handed_damage is 0")
	mode = FixtureCombatModes.basic()
	mode.actions.append(FixtureCombatModes.fist_rule(5, 10, 20, 0))
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


## The whole points P2, 1 m north of P1, loses to one Use of P1 facing north, with P2 facing
## `facing` by a MoveClaim (none when zero: the default Vector3.FORWARD) and P1 holding an item of
## `kind` (none when empty).
func _taken(mode: GameMode, facing: Vector3, kind: StringName = &"") -> int:
	var game := FixtureCombatModes.in_round(mode, [P1, P2])
	if not kind.is_empty():
		_hold(game, kind)
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	FixtureItemModes.stand(game, P2, AHEAD)
	if not facing.is_zero_approx():
		_face(game, P2, facing)
	assert_int(game.state.player(P2).health).is_equal(HEALTH)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	return _lost(game)


## P1 at the origin picks up an item of `kind` laid at its feet.
func _hold(game: Match, kind: StringName) -> void:
	FixtureItemModes.stand(game, P1, Vector3.ZERO)
	var item := FixtureItemModes.lay(game, kind, Vector3.ZERO)
	FixtureItemModes.pick_up(game, P1, item)
	assert_int(item.holder).is_equal(P1)


## `peer` claims to face `facing` where the host has it (a MoveClaim applied on the next tick).
func _face(game: Match, peer: int, facing: Vector3) -> void:
	FixtureMoves.claim(game, peer, game.state.player(peer).position, {"facing": facing})
	var stored := game.state.player(peer).facing
	assert_vector(stored).is_equal_approx(facing.normalized(), Vector3.ONE * 1e-5)


## The whole points P2 has lost.
func _lost(game: Match) -> int:
	return roundi((HEALTH - game.state.player(P2).health) / 1000.0)
