extends GdUnitTestSuite
## RE8's walk test (#811, ARCHITECTURE §4.7.56; the car repair ADR's RE8, RD1, §8 R7): R5's real
## car scene (`levels/stations/car.tscn`) in both Games' levels on NetPair's crouch_room, its Lift
## (layer 4, `movers`, which the own living player's mask holds) driven on the client by a
## test-local CarRepairViews from a ClientModel of FixtureCarRepairClient (for_scenes(): R5's
## 1.4 m clearance), as ItemWorld's views drive it in a match. The host's Game holds the scene
## too, but its rules never see the Lift (the server's LevelWorld and HostWorldQuery query the
## world layer only), so whatever the client's capsule does against it, the host judges claims.
##
## Lowered: a jump at the car's end does not get on it or into it, and no Correction follows.
## Raised: a standing walk at it stops at its body; a crouched walk goes under it and out of the
## far end, letting go of the crouch under it keeps the crouch (KD4 (a)); no Correction. Dropped
## on a crouched player at its end (feet outside the footprint, the capsule under the hull's
## edge): the push is printed on an `RE8 edge:` line (the ADR asks it recorded), no sink and at
## most MAX_CORRECTIONS.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
const CAR_SCENE := preload("res://levels/stations/car.tscn")
## The car's origin from the client player's spawn: along -z, on crouch_room's open floor.
const CAR_FROM_SPAWN := Vector3(0, 0, -5)
## How far from the car's end the walks start and end.
const APPROACH_M := 1.5
## Frames of a walk or a jump run at the car.
const RUN_FRAMES := 120
## After a walk: the last claims and any Correction arrive.
const SETTLE_FRAMES := 30
## How far into the hull's footprint (grown by the capsule) a blocked capsule may sit.
const CONTACT_M := 0.05
## Below the floor that counts as sinking.
const FLOOR_M := 0.05
## Feet outside the car's end by this much, the capsule under the hull's edge, for the drop.
const EDGE_M := 0.2
## How short of its target NetPair.walk_to() stops.
const WALK_STOP_M := 0.2
## The most Corrections the drop at the edge may cost (KD15's bound for the client's walk-out).
const MAX_CORRECTIONS := 1

var _pair: NetPair
var _views: CarRepairViews
var _model: ClientModel
var _type: CarRepair
var _clock := 0.0
var _now := 0
var _car: Node3D


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_crouch_room()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_only_a_crouched_player_gets_under_the_raised_car() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var player := _pair.client.player()
	var session := _pair.client.client()
	var rules := _pair.mode.player_rules
	await _build(player.global_position + CAR_FROM_SPAWN)
	assert_float(rules.crouch_height_m).is_less(_type.clearance_m)
	assert_float(_type.clearance_m).is_less(rules.capsule_height_m)
	var half_length := _hull().size.z * 0.5
	var near_end := _car.global_position + Vector3(0, 0, half_length + APPROACH_M)
	var far_end := _car.global_position - Vector3(0, 0, half_length + APPROACH_M)
	var blocked_z := half_length + rules.capsule_radius_m - CONTACT_M
	var corrections := session.corrections

	# Lowered: jumping at the car's end.
	assert_bool(await _pair.walk_to(player, near_end)).is_true()
	var highest := 0.0
	var nearest := INF
	for i: int in RUN_FRAMES:
		_face(player, _car.global_position)
		player.move_input = Vector2(0.0, 1.0)
		player.jump_requested = true
		await _frames(1)
		highest = maxf(highest, player.global_position.y - _car.global_position.y)
		nearest = minf(nearest, player.global_position.z - _car.global_position.z)
	player.release_keys()
	await _frames(SETTLE_FRAMES)
	assert_float(nearest).is_greater(blocked_z)
	assert_float(highest).is_less(_hull_top())
	assert_int(session.corrections - corrections).is_equal(0)

	# Raised: standing, the capsule meets the body.
	FixtureCarRepairClient.lift(_model, true, _now)
	await _frames(Ticks.RATE * 3)
	assert_float(_underside()).is_equal_approx(_type.clearance_m, 0.01)
	assert_bool(await _pair.walk_to(player, near_end)).is_true()
	nearest = await _run_at(player, _car.global_position)
	assert_float(nearest).is_greater(blocked_z)
	assert_bool(player.is_crouched()).is_false()

	# Crouched: under it, the crouch kept there when let go, and out of the far end.
	player.crouch_held = true
	assert_bool(await _pair.walk_to(player, _car.global_position)).is_true()
	player.crouch_held = false
	await _frames(SETTLE_FRAMES)
	assert_bool(player.is_crouched()).is_true()
	player.crouch_held = true
	assert_bool(await _pair.walk_to(player, far_end)).is_true()
	player.release_keys()
	await _frames(SETTLE_FRAMES)
	assert_bool(player.is_crouched()).is_false()
	assert_int(session.corrections - corrections).is_equal(0)

	# Dropped on a crouched player at the far end: NetPair's walk stops WALK_STOP_M short of its
	# target, so the target lies that much nearer the car than the feet should.
	player.crouch_held = true
	var edge := _car.global_position - Vector3(0, 0, half_length + EDGE_M - WALK_STOP_M)
	assert_bool(await _pair.walk_to(player, edge)).is_true()
	await _frames(SETTLE_FRAMES)
	var start := player.global_position
	var outside := _car.global_position.z - start.z - half_length
	assert_float(outside).is_between(0.0, rules.capsule_radius_m - CONTACT_M)
	var before_corrections := session.corrections
	FixtureCarRepairClient.lift(_model, false, _now)
	var push := 0.0
	var sink := 0.0
	for i: int in Ticks.RATE * 2:
		await _frames(1)
		var moved := player.global_position - start
		push = maxf(push, Vector2(moved.x, moved.z).length())
		sink = maxf(sink, -moved.y)
	await _frames(SETTLE_FRAMES)
	var dropped_corrections := session.corrections - before_corrections
	print(
		(
			"RE8 edge: feet %.2f m outside the end; push %.3f m, sink %.3f m, Corrections %d, at %s"
			% [
				outside,
				push,
				sink,
				dropped_corrections,
				player.global_position - _car.global_position
			]
		)
	)
	assert_float(_underside()).is_less(0.5)
	assert_float(sink).is_less(FLOOR_M)
	assert_int(dropped_corrections).is_less_equal(MAX_CORRECTIONS)
	player.release_keys()
	await _pair.stop()


## The car scene at `at` in both levels; the client's driven by a test-local CarRepairViews.
func _build(at: Vector3) -> void:
	# Placed before it enters the tree, as a level holds it: a parent moved later leaves the Lift
	# (sync_to_physics) where it entered.
	var host_car := CAR_SCENE.instantiate() as Node3D
	host_car.position = at
	_pair.host.level().add_child(host_car)
	_car = CAR_SCENE.instantiate() as Node3D
	_car.position = at
	_pair.client.level().add_child(_car)
	var mode := FixtureCarRepairClient.for_scenes(FixtureCarRepairModes.basic())
	_type = FixtureCarRepairModes.type_of(mode)
	var spot := (_car.get_node("UseSpot") as Node3D).global_position
	var away := at + Vector3(0, 0, 30)
	var bins: Array[Vector3] = [away, away + Vector3.RIGHT, away + Vector3.LEFT]
	_model = FixtureCarRepairClient.dealt(mode, &"spark_plug", spot, away, bins, away)
	_views = auto_free(CarRepairViews.new())
	_views.mode = mode
	_views.host_tick = func() -> int: return _now
	add_child(_views)
	_views.model = _model
	_views.level = _pair.client.level()
	await _frames(2)
	assert_object(_views.scene_of(FixtureCarRepairClient.CAR)).is_same(_car)


## Walks `player` at `target` for RUN_FRAMES; its nearest z to the car's origin.
func _run_at(player: PlayerController, target: Vector3) -> float:
	var nearest := INF
	for i: int in RUN_FRAMES:
		_face(player, target)
		player.move_input = Vector2(0.0, 1.0)
		await _frames(1)
		nearest = minf(nearest, player.global_position.z - _car.global_position.z)
	player.release_keys()
	await _frames(SETTLE_FRAMES)
	return nearest


func _face(player: PlayerController, target: Vector3) -> void:
	var to := target - player.global_position
	player.look(angle_difference(player.rotation.y, atan2(-to.x, -to.z)), 0.0)


## Physics frames, the host tick the views read advancing with them.
func _frames(count: int) -> void:
	for i: int in count:
		await _pair.frames(1)
		_clock += 1.0 / Engine.physics_ticks_per_second
		_now = Ticks.from_seconds(_clock)


func _hull() -> BoxShape3D:
	return (_car.get_node("Lift/Hull") as CollisionShape3D).shape as BoxShape3D


## The Lift's lowest collision point above the car's floor.
func _underside() -> float:
	var hull := _car.get_node("Lift/Hull") as CollisionShape3D
	return hull.global_position.y - _hull().size.y * 0.5 - _car.global_position.y


func _hull_top() -> float:
	return _underside() + _hull().size.y
