extends GdUnitTestSuite
## Cooldown (ARCHITECTURE §9.2, §9.4) through the knife's Use (FixtureCombatModes: key `hit`,
## 0.5 s, that is 10 host ticks): `too_soon` until the interval passed since this player last paid
## the key, per player and not per item, recorded only when the whole rule applied.

const P1 := 1
const P2 := 2
const NORTH := Vector3(0, 0, 1)


func test_a_second_use_within_the_interval_is_too_soon_and_pays_nothing() -> void:
	var game := _armed([P1, P2])
	FixtureCombatModes.use(game, P1, NORTH)
	var paid_at := game.ticked_through() + 1
	assert_int(game.state.cooldown_paid_at(P1, &"hit")).is_equal(paid_at)
	FixtureModes.run_ticks(game, FixtureCombatModes.COOLDOWN_TICKS - 1)
	var stamina := game.state.player(P1).stamina
	FixtureCombatModes.use(game, P1, NORTH, 7)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"too_soon"])
	var rejected := FixtureCombatModes.received(game, P1, &"Rejected")[0] as RejectedEvent
	assert_int(rejected.seq).is_equal(7)
	assert_int(game.state.player(P1).stamina).is_equal(stamina)
	assert_int(game.state.cooldown_paid_at(P1, &"hit")).is_equal(paid_at)
	assert_array(FixtureCombatModes.received(game, P2, &"Swung")).has_size(1)
	# The refusal went to the attacker alone.
	assert_array(FixtureCombatModes.received(game, P2, &"Rejected")).is_empty()
	FixtureModes.run_ticks(game, 1)
	FixtureCombatModes.use(game, P1, NORTH)
	# Accepted once the interval has passed: no second refusal, and a second swing.
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"too_soon"])
	assert_array(FixtureCombatModes.received(game, P2, &"Swung")).has_size(2)


func test_two_uses_in_one_tick_are_too_soon() -> void:
	var game := _armed([P1, P2])
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"too_soon"])


func test_a_second_knife_does_not_skip_the_interval() -> void:
	var game := _armed([P1, P2])
	FixtureCombatModes.use(game, P1, NORTH)
	var second := FixtureItemModes.lay(game, &"knife", Vector3(0.5, 0, 0))
	FixtureItemModes.pick_up(game, P1, second)
	assert_int(game.state.player(P1).held_item).is_equal(second.id)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"too_soon"])


func test_the_interval_belongs_to_each_player() -> void:
	var game := _armed([P1, P2])
	FixtureCombatModes.arm(game, P2, Vector3(3, 0, 3))
	FixtureCombatModes.use(game, P1, NORTH)
	FixtureCombatModes.use(game, P2, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	assert_array(FixtureCombatModes.received(game, P1, &"Swung")).has_size(2)


func test_a_use_refused_by_a_later_cost_records_no_cooldown() -> void:
	var game := _armed([P1, P2])
	var attacker := game.state.player(P1)
	attacker.stamina = 10000
	attacker.stamina_settled_tick = game.ticked_through() + 1
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"tired"])
	assert_int(game.state.cooldown_paid_at(P1, &"hit")).is_equal(-1)
	attacker.stamina = 100000
	FixtureModes.run_ticks(game, 1)
	FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"tired"])
	assert_array(FixtureCombatModes.received(game, P2, &"Swung")).has_size(1)


func test_an_interval_of_zero_never_refuses() -> void:
	var mode := FixtureCombatModes.basic()
	mode.find_item_kind(&"knife").actions = [FixtureCombatModes.knife_rule(30.0, 1.5, 1, 0.0, 0)]
	var game := _armed([P1, P2], mode)
	for i in 3:
		FixtureCombatModes.use(game, P1, NORTH)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	assert_array(FixtureCombatModes.received(game, P2, &"Swung")).has_size(3)


func test_reset_match_clears_the_table() -> void:
	var game := _armed([P1, P2])
	FixtureCombatModes.use(game, P1, NORTH)
	game.state.reset_match()
	assert_int(game.state.cooldown_paid_at(P1, &"hit")).is_equal(-1)


## A round of `peers` (of `mode`, the knife mode when null) with P1 at the origin holding a knife.
func _armed(peers: Array[int], mode: GameMode = null) -> Match:
	var used := mode if mode != null else FixtureCombatModes.basic()
	var game := FixtureCombatModes.in_round(used, peers)
	FixtureCombatModes.arm(game, P1, Vector3.ZERO)
	return game
