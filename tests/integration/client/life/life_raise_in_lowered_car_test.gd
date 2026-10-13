extends GdUnitTestSuite
## KD15 (a)'s push (the knockdown rework's §2 and §10, 728e, #849): a body launched into the
## lowered car and raised there. The car is client-only (the car repair ADR's RE8 (a)): an
## AnimatableBody3D on layer 4, `movers`, which each honest client's own player collides with
## beside the world, and which the host's world never holds. So the host's revive Correction
## places the raised player inside the car's footprint, and its own client's solver pushes it out
## on its screen, a push the host sees only through the claims that follow and checks as any
## claims (ARCHITECTURE §7.1.5). This suite records that push and the Corrections the host sends
## after the revive's placement (it prints them on a `KD15 (a):` line).
##
## What it measured (#849): the raiser's hint offers the body inside the car (the raise ray passes
## through `movers`); the crouched capsule placed inside the stand-in is pushed down, not out (about
## 0.56 m into the floor on its own screen, no Correction while it stands still), and walking out
## across the long side gets 3 Corrections. ADR §2 makes more than one a stop: KD15 went back to
## the engineer with (b) and (c) (PR of #849). So the suite asserts what holds either way (the
## placement, the crouch, the way out, the floor once out) and only records the Corrections and the
## push; his answer sets the bound it is to assert.
##
## Neither the car (R5) nor the `movers` layer (R7) is built yet, so the suite builds a stand-in:
## a box on layer 4 in both Games' worlds (each machine has its own copy, as R7 drives it), and it
## adds layer 4 to each living player's collision_mask every frame (set_life() resets the mask to
## the world alone; R7 is to add `movers` there). The box is the car's footprint (RD2's
## placeholders: half-width 1.0 m, half-length 2.3 m) from LOWERED_UNDERSIDE_M to CAR_TOP_M:
## a placeholder of the lowered car's body, not a decision. The match plays crouch_room (the
## crouch plays, so the raised player can crouch, KE6), an open floor where nothing else pushes.
## The knocked-down player is put at the footprint's centre by building the car around its body
## (no launch: the host's world has no car, so a launch there rests the body on the floor inside
## the footprint, which is where the knockdown leaves it here). It holds the crouch through the
## revive, so the Correction places a crouched player (KE6 gives it under a car whose layer is on
## the mask; R7 decides when the mask gets it).

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## Layer 4, `movers` in the car repair ADR's RE8 (a) (bit value 8); not in PhysicsLayers until R7.
const MOVERS := 1 << 3
## The lowered car's stand-in: the footprint (RD2's 2.0 m wide, 4.6 m long, long axis along z),
## its underside above the floor and below the raised clearance (1.4 m), its top above the
## crouched capsule. Not a decision: R5's car.tscn sets the real collider.
const CAR_SIZE := Vector2(2.0, 4.6)
const LOWERED_UNDERSIDE_M := 0.3
const CAR_TOP_M := 1.5
## Nobody respawns or bleeds out during the suite.
const RESPAWN_S := 60.0
const KNOCKDOWN_S := 60.0
## Where the raiser walks to: this far from the body across the car's long side, so it stops
## (within NetPair's 0.2 m) beside the car and within the raise hint's reach (1.7 m here).
const RAISER_M := 1.45
## The most physics frames the host's KnockedDown or Revived takes to arrive; the raise is 3 s.
const ANSWER_FRAMES := 30
const REVIVE_FRAMES := 300
## The raiser aims this high above the body's point (a ragdoll lies low), at most AIM_FRAMES.
const AIM_UP_M := 0.15
const AIM_FRAMES := 30
## How long the raised player is watched, still in the car and again once out: 3 s.
const WATCH_FRAMES := 180
## After the walk out, before the second watch: the last claims and Corrections arrive.
const SETTLE_FRAMES := 30
## The revive's placement lands within this of the body's point (the footprint's centre).
const PLACED_M := 0.05
## Out of the car, the feet stand on the floor: within this of its height.
const FLOOR_M := 0.05

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	_pair.with_life(RESPAWN_S)
	_pair.mode.player_rules.knockdown_s = KNOCKDOWN_S
	_pair.with_crouch_room(true)
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_a_player_raised_in_the_lowered_car_is_pushed_out_by_its_own_client() -> void:
	assert_bool(await _pair.start()).is_true()
	assert_bool(await _pair.to_round()).is_true()
	var session := _pair.client.client()
	var model := session.model
	var raised := _pair.peer_of(_pair.client)
	var player := _pair.client.player()
	var raiser := _pair.host.player()
	_pair.knock_down(_pair.client)
	var lying := func() -> bool: return model.life_of(raised) == ClientModel.Life.DOWNED
	assert_bool(await _until(lying, ANSWER_FRAMES)).is_true()
	await _pair.frames(20)
	var body := player.global_position
	_build_car(_pair.client, body)
	_build_car(_pair.host, body)
	# The raiser walks to the car's long side nearer to it and aims at the body until its hint
	# offers the raise, or AIM_FRAMES pass.
	var side := Vector3(signf(raiser.global_position.x - body.x), 0.0, 0.0)
	if side == Vector3.ZERO:
		side = Vector3.RIGHT
	assert_bool(await _walk_to(raiser, body + side * RAISER_M)).is_true()
	var offered := false
	for i: int in AIM_FRAMES:
		_pair.aim(raiser, body + Vector3.UP * AIM_UP_M)
		await _frames(1)
		offered = _pair.host.life().raise_target() == raised
		if offered:
			break
	player.crouch_held = true
	# E held; where the hint offers nothing (the issue's follow-up: the raise ray passes through
	# `movers`, yet the car may hide the body), the Raise a modified client could send, so the push
	# is recorded all the same (the host's sight passes through the car, RE8).
	_pair.host.life().press_raise()
	if not offered:
		_pair.host.client().send_intent(Intents.RAISE, {"target": raised})
	var placements := session.placements
	var revived := func() -> bool:
		return model.life_of(raised) == ClientModel.Life.ALIVE and session.placements > placements
	assert_bool(await _until(revived, REVIVE_FRAMES)).is_true()
	var corrections := session.corrections
	var placed := player.global_position - body
	var crouched := player.is_crouched()
	# Still: what its own client's solver does with a crouched capsule inside the car.
	var still := await _watch(player, body, WATCH_FRAMES)
	var still_corrected := session.corrections - corrections
	# Out: the player walks out across the long side away from the raiser, the shortest way.
	var out_to := body - side * (CAR_SIZE.x * 0.5 + _pair.mode.player_rules.capsule_radius_m + 0.3)
	var walked_out := await _walk_to(player, out_to)
	await _frames(SETTLE_FRAMES)
	var out := await _watch(player, body, WATCH_FRAMES)
	var corrected := session.corrections - corrections
	print(
		(
			(
				"KD15 (a): hint offered %s; placed %s, crouched %s; still %.1f s: push %.3f m, "
				+ "lift %.3f m, sink %.3f m, Corrections %d; walked out %s to %s; Corrections in all %d"
			)
			% [
				offered,
				placed,
				crouched,
				WATCH_FRAMES / 60.0,
				still.push,
				still.lift,
				still.sink,
				still_corrected,
				walked_out,
				player.global_position - body,
				corrected,
			]
		)
	)
	assert_float(Vector2(placed.x, placed.z).length()).is_less(PLACED_M)
	assert_bool(crouched).is_true()
	assert_bool(walked_out).is_true()
	assert_float(out.sink).is_less(FLOOR_M)
	assert_float(out.lift).is_less(FLOOR_M)
	await _pair.stop()


## The lowered car's stand-in in `game`'s world, its footprint centred on `at`.
func _build_car(game: Game, at: Vector3) -> void:
	var car := AnimatableBody3D.new()
	car.sync_to_physics = true
	car.collision_layer = MOVERS
	car.collision_mask = 0
	var box := BoxShape3D.new()
	var height := CAR_TOP_M - LOWERED_UNDERSIDE_M
	box.size = Vector3(CAR_SIZE.x, height, CAR_SIZE.y)
	var shape := CollisionShape3D.new()
	shape.shape = box
	car.add_child(shape)
	game.level().add_child(car)
	car.global_position = at + Vector3.UP * (LOWERED_UNDERSIDE_M + height * 0.5)


## Physics frames, each first giving every living player the `movers` layer as R7 will.
func _frames(count: int) -> void:
	for i: int in count:
		for game: Game in [_pair.host, _pair.client]:
			var player := game.player()
			if player != null and player.is_living():
				player.collision_mask |= MOVERS
		await _pair.frames(1)


## NetPair.walk_to() with the `movers` layer on the walker's mask.
func _walk_to(player: PlayerController, target: Vector3) -> bool:
	for i: int in NetPair.MAX_WALK_FRAMES:
		var to := target - player.global_position
		to.y = 0.0
		if to.length() < 0.2:
			player.move_input = Vector2.ZERO
			return true
		player.look(angle_difference(player.rotation.y, atan2(-to.x, -to.z)), 0.0)
		player.move_input = Vector2(0.0, 1.0)
		await _frames(1)
	player.move_input = Vector2.ZERO
	return false


## Waits until `done` holds, at most `frames` physics frames; whether it held.
func _until(done: Callable, frames: int) -> bool:
	for i: int in frames:
		if done.call():
			return true
		await _frames(1)
	return done.call()


## Watches `player` for `count` physics frames: its farthest horizontal distance from `body`,
## and how far its feet rose above and sank below the body's floor.
func _watch(player: PlayerController, body: Vector3, count: int) -> Watch:
	var watch := Watch.new()
	for i: int in count:
		await _frames(1)
		var moved := player.global_position - body
		watch.push = maxf(watch.push, Vector2(moved.x, moved.z).length())
		watch.lift = maxf(watch.lift, moved.y)
		watch.sink = maxf(watch.sink, -moved.y)
	return watch


## What _watch() saw.
class Watch:
	extends RefCounted
	var push := 0.0
	var lift := 0.0
	var sink := 0.0
