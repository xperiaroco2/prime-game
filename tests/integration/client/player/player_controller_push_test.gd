extends GdUnitTestSuite
## Pushing between living players over real physics steps (Jolt, headless): the engineer's
## decision of 2026-09-30 (#46), ARCHITECTURE §7.1 "Pushing apart". Two controllers in one world
## stand for two clients that see each other without delay; each moves only its own body. Forward
## is -Z. Each test builds its own small world.

const SPEED_TOLERANCE := 0.1
## Metres two players' centres may be apart across their line of motion for a contact to count as
## head-on.
const NEARLY_STRAIGHT := 0.1
## Physics steps a remote capsule lags its player in the two-client tests: 0.1 s at 60 Hz, the
## interpolation delay of ARCHITECTURE §7. `_run_two_clients` checks the tick rate it assumes.
const DELAY := 6
const DELAY_TICKS_PER_SECOND := 60
const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")

var _tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")
var _rules := FixtureModes.player_rules()
var _world: PlayerTestWorld


func before_test() -> void:
	_world = PlayerTestWorld.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_walking_into_a_standing_player_pushes_both_at_the_push_speed() -> void:
	await _assert_pushes_at_the_push_speed(false)


func test_sprinting_into_a_standing_player_pushes_both_at_the_push_speed() -> void:
	await _assert_pushes_at_the_push_speed(true)


func test_a_pushed_player_holding_sprint_without_moving_keeps_its_stamina() -> void:
	# Only the player's own movement costs stamina (the engineer's decision of 2026-09-30): a
	# player that holds Shift and gives no movement input pays nothing while a push moves it.
	var standing := _world.add_player(Vector3(0.0, 0.0, -2.0))
	var pusher := _world.add_player(Vector3.ZERO)
	standing.sprint_held = true
	await _world.frames(5)
	var from := standing.global_position
	pusher.move_input = Vector2(0.0, 1.0)
	await _world.frames(90)
	assert_float(_world.horizontal_distance(from, standing.global_position)).is_greater(0.5)
	assert_bool(standing.is_sprinting()).is_true()
	assert_float(_world.stand_in(standing).get_stamina()).is_equal(float(_rules.stamina))


func test_a_pushed_player_sprinting_sideways_spends_stamina() -> void:
	await _assert_pushed_sprinter_pays(Vector2(1.0, 0.0))


func test_a_pushed_player_sprinting_away_spends_stamina() -> void:
	await _assert_pushed_sprinter_pays(Vector2(0.0, 1.0))


func test_a_player_standing_in_a_doorway_is_pushed_out_and_the_pusher_passes() -> void:
	# A wall across the way at z = -3 with a doorway 1.1 m wide: room for one capsule only.
	var half_door := 0.55
	_world.add_box(Vector3(-3.0 - half_door, 1.5, -3.0), Vector3(6.0, 3.0, 0.2))
	_world.add_box(Vector3(3.0 + half_door, 1.5, -3.0), Vector3(6.0, 3.0, 0.2))
	var standing := _world.add_player(Vector3(0.0, 0.0, -3.0))
	var pusher := _world.add_player(Vector3.ZERO)
	pusher.move_input = Vector2(0.0, 1.0)
	await _world.frames(240)
	var beyond := -3.0 - 0.1 - _rules.capsule_radius_m
	assert_float(standing.global_position.z).is_less(beyond)
	assert_float(pusher.global_position.z).is_less(beyond)
	assert_float(pusher.global_position.y).is_less(0.01)


func test_head_on_nobody_advances_and_the_drift_parts_them() -> void:
	var one := _world.add_player(Vector3.ZERO)
	var other := _world.add_player(Vector3(0.0, 0.0, -3.0))
	other.look(PI, 0.0)
	one.move_input = Vector2(0.0, 1.0)
	other.move_input = Vector2(0.0, 1.0)
	var deepest := -INF
	var met := NAN
	var straight := 0
	var passed := false
	for i: int in 180:
		await _world.frames(1)
		# How far `one` still is from having walked past `other`, and how far aside it is.
		var along := one.global_position.z - other.global_position.z
		var across := absf(other.global_position.x - one.global_position.x)
		if across < _rules.capsule_radius_m * 2.0 and along > 0.0:
			deepest = maxf(deepest, _rules.capsule_radius_m * 2.0 - Vector2(along, across).length())
			# Along the line of contact the pushes cancel: while the contact is still nearly
			# straight, the two stay where they met.
			var middle := (one.global_position.z + other.global_position.z) * 0.5
			if is_nan(met) and deepest > 0.0:
				met = middle
			if not is_nan(met) and across < NEARLY_STRAIGHT:
				assert_float(middle).is_equal_approx(met, 0.01)
				straight += 1
		passed = passed or along < 0.0
	assert_float(met).is_equal_approx(-1.5, 0.05)
	assert_int(straight).is_greater(3)
	# Never deeper in each other than a pusher may go, and yet they did not freeze: the drift
	# slid them apart and past each other.
	assert_float(deepest).is_less(_tuning.push_max_overlap + 0.01)
	assert_bool(passed).is_true()
	# Each drifted to its own right, so they passed on opposite sides: `one` faces -Z (right is
	# +X), `other` faces +Z (right is -X).
	assert_float(one.global_position.x).is_greater(0.0)
	assert_float(other.global_position.x).is_less(0.0)


func test_at_an_angle_the_two_slide_apart_and_walk_on() -> void:
	var one := _world.add_player(Vector3.ZERO)
	var other := _world.add_player(Vector3(0.3, 0.0, -3.0))
	other.look(PI, 0.0)
	one.move_input = Vector2(0.0, 1.0)
	other.move_input = Vector2(0.0, 1.0)
	var deepest := -INF
	for i: int in 60:
		await _world.frames(1)
		var apart := _world.horizontal_distance(one.global_position, other.global_position)
		deepest = maxf(deepest, _rules.capsule_radius_m * 2.0 - apart)
	# Each slid off to its side of the other and walked on past it.
	assert_float(one.global_position.x).is_less(-0.1)
	assert_float(other.global_position.x).is_greater(0.4)
	assert_float(one.global_position.z).is_less(-3.0)
	assert_float(other.global_position.z).is_greater(0.0)
	assert_float(deepest).is_less(_tuning.push_max_overlap + 0.01)


func test_a_downed_player_is_not_pushed_and_pushes_nobody() -> void:
	var downed := _world.add_downed(Vector3(0.0, 0.0, -2.0))
	var living := _world.add_player(Vector3.ZERO)
	await _world.frames(5)
	living.move_input = Vector2(0.0, 1.0)
	var speed: float = await _world.measure_speed(living, 10, 30)
	assert_float(speed).is_equal_approx(_rules.walk_speed_mps, SPEED_TOLERANCE)
	assert_float(living.global_position.z).is_less(-2.5)
	assert_vector(downed.global_position).is_equal_approx(
		Vector3(0.0, 0.0, -2.0), Vector3.ONE * 0.001
	)
	# The other way round: a downed player crawls through a standing player, who stays put.
	var standing := living.global_position
	living.move_input = Vector2.ZERO
	downed.move_input = Vector2(0.0, -1.0)
	await _world.frames(40)
	assert_float(downed.global_position.z).is_greater(standing.z + 1.0)
	assert_vector(living.global_position).is_equal_approx(standing, Vector3.ONE * 0.001)


## One player walks or sprints into another standing 2 m ahead: once in contact both move on at
## the pusher's speed times the push speed factor.
func _assert_pushes_at_the_push_speed(sprint: bool) -> void:
	var standing := _world.add_player(Vector3(0.0, 0.0, -2.0))
	var pusher := _world.add_player(Vector3.ZERO)
	pusher.move_input = Vector2(0.0, 1.0)
	pusher.sprint_held = sprint
	# Into contact (1.2 m to go), a step to settle, then a short look before the drift turns the
	# straight push into a slide off the other's round side.
	var touching := _rules.capsule_radius_m * 2.0
	var met := false
	for i: int in 120:
		if _world.horizontal_distance(standing.global_position, pusher.global_position) <= touching:
			met = true
			break
		await _world.frames(1)
	assert_bool(met).is_true()
	await _world.frames(1)
	var standing_from := standing.global_position
	var pusher_from := pusher.global_position
	var count := 6
	await _world.frames(count)
	var per_second := float(Engine.physics_ticks_per_second) / count
	var standing_speed := _world.horizontal_distance(standing_from, standing.global_position)
	var pusher_speed := _world.horizontal_distance(pusher_from, pusher.global_position)
	var own := _rules.sprint_speed_mps if sprint else _rules.walk_speed_mps
	var push := own * _tuning.push_speed_factor
	assert_float(standing_speed * per_second).is_equal_approx(push, SPEED_TOLERANCE)
	assert_float(pusher_speed * per_second).is_equal_approx(push, SPEED_TOLERANCE)
	var apart := _world.horizontal_distance(standing.global_position, pusher.global_position)
	assert_float(apart).is_between(touching - _tuning.push_max_overlap, touching)


func test_leaving_an_overlap_is_no_faster_than_sprinting() -> void:
	# A player standing almost inside a remote capsule leaves it, at most at sprint speed: the
	# host's speed bound for a pushed player counts on that cap (ARCHITECTURE §7.1).
	var standing := _world.add_player(Vector3.ZERO)
	await _world.frames(10)
	_world.add_remote(Vector3(0.0, 0.0, -0.1))
	var from := standing.global_position
	await _world.frames(1)
	var step := _world.horizontal_distance(from, standing.global_position)
	var speed := step * Engine.physics_ticks_per_second
	assert_float(speed).is_greater(_rules.walk_speed_mps)
	assert_float(speed).is_less(_rules.sprint_speed_mps + SPEED_TOLERANCE)


func test_over_a_delay_the_pushed_client_moves_its_player_from_the_pushers_motion() -> void:
	# Two clients, each a world of its own: its player and the other player's capsule, placed
	# where that player was 0.1 s ago, as interpolation will. Each moves only its own player.
	var pair := _two_clients(Vector3.ZERO, Vector3(0.0, 0.0, -2.0))
	var pusher := pair[0] as PlayerController
	var standing := pair[1] as PlayerController
	pusher.move_input = Vector2(0.0, 1.0)
	var views: Array[float] = await _run_two_clients(pair, 120)
	# The pushed client moved its player out of the way it saw the pusher come, and the pusher
	# got past, never deeper in the other's late capsule than a pusher may go.
	assert_float(standing.global_position.z).is_less(-2.2)
	assert_float(pusher.global_position.z).is_less(-3.0)
	assert_float(views[0]).is_less(_tuning.push_max_overlap + 0.01)
	assert_float(views[1]).is_less(0.1)


func test_over_a_delay_head_on_nobody_passes_through() -> void:
	var pair := _two_clients(Vector3.ZERO, Vector3(0.0, 0.0, -3.0))
	var one := pair[0] as PlayerController
	var other := pair[1] as PlayerController
	other.look(PI, 0.0)
	one.move_input = Vector2(0.0, 1.0)
	other.move_input = Vector2(0.0, 1.0)
	var views: Array[float] = await _run_two_clients(pair, 120)
	# The other's late capsule keeps coming for 0.1 s after that player stopped: a client sees it
	# at most one step of walking deeper before its own player steps back out.
	var one_step := _rules.walk_speed_mps / Engine.physics_ticks_per_second
	assert_float(views[0]).is_less(_tuning.push_max_overlap + one_step + 0.01)
	assert_float(views[1]).is_less(_tuning.push_max_overlap + one_step + 0.01)
	# They slid apart and walked on past each other.
	assert_float(one.global_position.z).is_less(-3.0)
	assert_float(other.global_position.z).is_greater(0.0)


## Two clients' worlds, each with a floor, its own player at `first` or `second`, and a remote
## capsule for the other player. Returns [first player, second player, remote of the second in
## the first's world, remote of the first in the second's world].
func _two_clients(first: Vector3, second: Vector3) -> Array[Node3D]:
	var one := _client_world()
	var two := _client_world()
	var first_player := one.add_player(first)
	var second_player := two.add_player(second)
	return [first_player, second_player, one.add_remote(second), two.add_remote(first)]


func _client_world() -> PlayerTestWorld:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_world.add_child(viewport)
	var world := PlayerTestWorld.new()
	viewport.add_child(world)
	return world


## Runs `pair` from `_two_clients` for `count` physics steps, each remote capsule DELAY steps
## behind its player. Returns the deepest overlap each client saw: [first's view, second's view].
func _run_two_clients(pair: Array[Node3D], count: int) -> Array[float]:
	assert_int(Engine.physics_ticks_per_second).is_equal(DELAY_TICKS_PER_SECOND)
	var first_trail: Array[Vector3] = []
	var second_trail: Array[Vector3] = []
	var deepest: Array[float] = [-INF, -INF]
	var touching := _rules.capsule_radius_m * 2.0
	for i: int in count:
		await _world.frames(1)
		first_trail.append(pair[0].global_position)
		second_trail.append(pair[1].global_position)
		pair[2].global_position = second_trail[maxi(0, second_trail.size() - 1 - DELAY)]
		pair[3].global_position = first_trail[maxi(0, first_trail.size() - 1 - DELAY)]
		var first_view := _world.horizontal_distance(
			pair[0].global_position, pair[2].global_position
		)
		var second_view := _world.horizontal_distance(
			pair[1].global_position, pair[3].global_position
		)
		deepest[0] = maxf(deepest[0], touching - first_view)
		deepest[1] = maxf(deepest[1], touching - second_view)
	return deepest


## The other half of the stamina rule: a pushed player that holds Shift and steers by `steer`
## gives movement input, so its sprint costs stamina as usual.
func _assert_pushed_sprinter_pays(steer: Vector2) -> void:
	var standing := _world.add_player(Vector3(0.0, 0.0, -2.0))
	var pusher := _world.add_player(Vector3.ZERO)
	standing.sprint_held = true
	# The pusher sprints as well, so it keeps up with a player sprinting away from it.
	pusher.sprint_held = true
	pusher.move_input = Vector2(0.0, 1.0)
	var touching := _rules.capsule_radius_m * 2.0
	var met := false
	for i: int in 120:
		if _world.horizontal_distance(standing.global_position, pusher.global_position) <= touching:
			met = true
			break
		await _world.frames(1)
	assert_bool(met).is_true()
	assert_float(_world.stand_in(standing).get_stamina()).is_equal(float(_rules.stamina))
	# Only the steps that start in contact count: out of it, it is an ordinary sprint.
	standing.move_input = steer
	var pushed_steps := 0
	while pushed_steps < 30:
		if _world.horizontal_distance(standing.global_position, pusher.global_position) > touching:
			break
		await _world.frames(1)
		pushed_steps += 1
	assert_int(pushed_steps).is_greater(0)
	assert_bool(standing.is_sprinting()).is_true()
	assert_float(_world.stand_in(standing).get_stamina()).is_less(float(_rules.stamina))
