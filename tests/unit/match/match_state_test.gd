extends GdUnitTestSuite
## MatchState: reset_match (ResetMatch, 2b) and part_state (ARCHITECTURE §3.1, §3.5, §9.1).

const P1 := 1
const P2 := 2
const P3 := 3


func test_reset_match_clears_the_match_and_drops_who_left() -> void:
	var state := _played_state()
	var index := state.rng.match_index
	var epoch := state.player(P1).epoch
	state.reset_match()
	assert_array(state.peers()).is_equal([P1, P3])
	assert_dict(state.items).is_empty()
	assert_dict(state.tasks).is_empty()
	assert_dict(state.stations).is_empty()
	assert_dict(state.bodies).is_empty()
	assert_int(state.cooldown_paid_at(P1, &"strike")).is_equal(-1)
	assert_int(state.counter(P1, &"uses")).is_equal(0)
	assert_int(state.clock_ticks_left).is_equal(-1)
	assert_bool(state.clock_ended).is_false()
	assert_str(state.winner).is_empty()
	assert_int(state.rng.match_index).is_equal(index + 1)
	var made := [0]
	var fresh := state.part_state(
		&"fixture",
		func() -> RefCounted:
			made[0] += 1
			return RefCounted.new()
	)
	assert_object(fresh).is_not_null()
	assert_int(made[0]).is_equal(1)
	for peer: int in [P1, P3]:
		var player := state.player(peer)
		assert_bool(player.ready).is_false()
		assert_str(player.role).is_empty()
		assert_int(player.life).is_equal(PlayerState.Life.ALIVE)
		assert_int(player.held_item).is_equal(-1)
		assert_int(player.health).is_equal(100000)
		assert_int(player.stamina).is_equal(100000)
		assert_bool(player.sprint_held).is_false()
		assert_bool(player.moving).is_false()
	assert_int(state.player(P1).epoch).is_equal(epoch)
	assert_int(state.add_item(ItemKind.new(), Vector3.ZERO).id).is_equal(1)
	assert_int(state.add_task(P1, FixtureTaskType.new()).id).is_equal(1)
	assert_int(state.add_station(StationKind.new(), Vector3.ZERO, Color.RED).id).is_equal(1)


func test_part_state_is_made_once_per_key() -> void:
	var state := MatchState.new(1)
	var made := [0]
	var create := func() -> RefCounted:
		made[0] += 1
		return RefCounted.new()
	var first := state.part_state(&"a", create)
	assert_object(state.part_state(&"a", create)).is_same(first)
	assert_object(state.part_state(&"b", create)).is_not_same(first)
	assert_int(made[0]).is_equal(2)


## A state after some play: P2 left, P3 a ghost holding an item, P1 a ready dissident with a
## cooldown and a counter; items, tasks, stations, a body, the clock and a winner set.
func _played_state() -> MatchState:
	var state := MatchState.new(5)
	state.player_rules = FixtureModes.player_rules()
	for peer: int in [P1, P2, P3]:
		state.add_player(peer, "p%d" % peer)
	var p1 := state.player(P1)
	p1.ready = true
	p1.role = &"dissident"
	p1.health = 1
	p1.stamina = 2
	p1.sprint_held = true
	p1.moving = true
	p1.epoch = 4
	state.player(P2).life = PlayerState.Life.LEFT
	var p3 := state.player(P3)
	p3.life = PlayerState.Life.GHOST
	p3.held_item = state.add_item(ItemKind.new(), Vector3.ONE).id
	state.add_task(P1, FixtureTaskType.new())
	state.add_station(StationKind.new(), Vector3.ONE, Color.BLUE)
	state.bodies[P3] = Vector3.ONE
	state.set_cooldown_paid(P1, &"strike", 40)
	state.set_counter(P1, &"uses", 2)
	state.part_state(&"fixture", func() -> RefCounted: return RefCounted.new())
	state.clock_ticks_left = 10
	state.clock_ended = true
	state.winner = &"crew"
	return state
