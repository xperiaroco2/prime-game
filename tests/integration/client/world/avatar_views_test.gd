extends GdUnitTestSuite
## AvatarViews (ARCHITECTURE §4.7): at physics priority -80 each other player of the model's newest
## snapshot gets a RemotePlayerBody at SnapshotBuffer's pose, the yaw on the body and the pitch on
## the head; a vertical facing keeps the turn and gives no NaN; a player the model drops goes; a
## PlayersPlaced snaps; a LoadMatch and a phase on another level (End -> Lobby, #241) forget the
## poses; the estimated host tick never runs backwards; a player the model knows as downed is on
## the downed layer, where no push searches (§7.1); a body the model drops leaves the physics
## space in that frame, before the local player's push search (#242), and clear() takes every
## body out of the tree the same way.

const PEER := 2
const TICK_USEC := 50000
const FRAME_USEC := 16667
const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")

var _views: AvatarViews
var _model: ClientModel
var _now := 1000000


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_views = AvatarViews.new()
	_views.model = _model
	_views.buffer = SnapshotBuffer.new()
	_views.rules = FixtureModes.player_rules()
	_views.clock = func() -> int: return _now
	add_child(_views)


func after_test() -> void:
	_views.free()


func test_it_draws_at_minus_80_the_yaw_on_the_body_and_the_pitch_on_the_head() -> void:
	assert_int(_views.process_physics_priority).is_equal(-80)
	# Looking along +X and 30 degrees up.
	var facing := Vector3(cos(PI / 6.0), sin(PI / 6.0), 0.0)
	for tick: int in range(1, 6):
		_snapshot(tick, Vector3(tick, 0, 0), facing)
	await _drawn()
	var body := _views.body_of(PEER)
	assert_object(body).is_not_null()
	assert_float(body.rotation.y).is_equal_approx(-PI / 2.0, 1e-4)
	assert_float(body.rotation.x).is_equal_approx(0.0, 1e-6)
	assert_float(body.head().rotation.x).is_equal_approx(PI / 6.0, 1e-4)
	# Drawn behind the newest snapshot by the delay, on the line between the snapshots.
	var at := _views.drawn_at()
	assert_float(at).is_less(5.0)
	assert_float(body.global_position.x).is_equal_approx(at, 1e-3)


func test_a_vertical_facing_keeps_the_turn_and_gives_no_nan() -> void:
	_snapshot(1, Vector3.ZERO, Vector3(1, 0, 0))
	_snapshot(2, Vector3.ZERO, Vector3(0, -1, 0))
	_snapshot(3, Vector3.ZERO, Vector3.ZERO)
	# The physics_frame signal comes before the nodes' step: the first wait draws nothing yet.
	await get_tree().physics_frame
	for i: int in 12:
		_now += FRAME_USEC
		await get_tree().physics_frame
		var body := _views.body_of(PEER)
		assert_bool(body.global_transform.is_finite()).is_true()
		assert_bool(body.head().global_transform.is_finite()).is_true()
	var turned := _views.body_of(PEER)
	assert_float(turned.rotation.y).is_equal_approx(-PI / 2.0, 1e-4)
	assert_float(turned.head().rotation.x).is_equal_approx(-SnapshotBuffer.MAX_PITCH, 1e-4)


func test_players_dropped_by_the_model_go_and_a_new_map_forgets_the_poses() -> void:
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD)
	await _drawn()
	assert_int(_views.count()).is_equal(1)
	_model.fold(&"PlayerLeft", {"peer": PEER})
	await _drawn()
	assert_int(_views.count()).is_equal(0)
	_views.on_event(&"LoadMatch", {})
	assert_int(_views.buffer.newest_tick()).is_equal(-1)


func test_a_placement_snaps_the_player_it_names() -> void:
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD)
	_snapshot(2, Vector3.ZERO, Vector3.FORWARD)
	_views.on_event(&"PlayersPlaced", {"spots": {PEER: Vector3(1, 0, 0)}})
	_snapshot(3, Vector3(1, 0, 0), Vector3.FORWARD)
	# Between ticks 2 and 3 it is where it was, not on its way: a placement slides nowhere.
	var pose := _views.buffer.pose_of(PEER, 2.5)
	assert_vector(pose.position).is_equal(Vector3.ZERO)


func test_a_downed_player_is_on_the_downed_layer_and_living_again_on_the_living_one() -> void:
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD)
	await _drawn()
	var body := _views.body_of(PEER)
	assert_int(body.collision_layer).is_equal(PhysicsLayers.LIVING)
	_model.fold(&"KnockedDown", {"peer": PEER, "position": Vector3.ZERO})
	await _drawn()
	assert_int(body.collision_layer).is_equal(PhysicsLayers.DOWNED)
	assert_bool(body.is_living()).is_false()
	# The downed pose (D8): the mesh lies on its side, its top at the capsule's width, no head.
	assert_bool(body.is_downed()).is_true()
	assert_bool(body.head().visible).is_false()
	var mesh := body.get_node("Mesh") as MeshInstance3D
	assert_float(mesh.get_aabb().size.y).is_greater(1.0)
	assert_float((mesh.global_transform * mesh.get_aabb()).end.y).is_less(0.81)
	# Its collision capsule lies with the mesh: a ray over the lying body, where the standing
	# capsule was, finds nothing to raise there.
	await _drawn()
	assert_int(_ray_hits_at(1.5)).is_equal(0)
	assert_int(_ray_hits_at(0.3)).is_equal(1)
	# A new match forgets the knockdown: the body is on the living layer again, standing.
	_model.lives.erase(PEER)
	await _drawn()
	assert_bool(body.is_living()).is_true()
	assert_bool(body.is_downed()).is_false()
	assert_bool(body.head().visible).is_true()
	assert_float((mesh.global_transform * mesh.get_aabb()).end.y).is_greater(1.7)
	assert_int(_ray_hits_at(1.5)).is_equal(1)


func test_the_invulnerable_flag_shows_the_shell_and_every_body_hides_out_of_sight() -> void:
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD, true)
	await _drawn()
	var body := _views.body_of(PEER)
	assert_bool(body.is_invulnerable()).is_true()
	assert_bool(body.is_in_group(SightHider.GROUP)).is_true()
	assert_int(body.peer).is_equal(PEER)
	_snapshot(2, Vector3.ZERO, Vector3.FORWARD)
	await _drawn()
	assert_bool(body.is_invulnerable()).is_false()


func test_the_host_tick_never_runs_backwards() -> void:
	var avatars := {}
	# One snapshot arrives with no delay, then every later one 3 ticks late: when the first leaves
	# the 2 s window, the raw estimate drops by 3 ticks.
	_views.buffer.add(100, avatars, _now)
	var given: Array[int] = [_views.host_tick()]
	var dropped := false
	var raw := floori(_views.buffer.estimated_tick(_now))
	for i: int in 60:
		_now += TICK_USEC
		_views.buffer.add(101 + i - 3, avatars, _now)
		given.append(_views.host_tick())
		var next := floori(_views.buffer.estimated_tick(_now))
		dropped = dropped or next < raw
		raw = next
	assert_bool(dropped).is_true()
	for i: int in range(1, given.size()):
		assert_int(given[i]).is_greater_equal(given[i - 1])
	# Cleared views (a session ended) give the estimate again.
	_views.clear()
	assert_int(_views.host_tick()).is_equal(raw)


func test_clear_takes_every_body_out_of_the_tree_before_it_is_freed() -> void:
	# A session's end (or a level swap) clears the views: like a drop, each body leaves the tree,
	# and so the physics space, at once instead of at the frame's end (#242).
	_snapshot(1, Vector3(2, 0, 0), Vector3.FORWARD)
	await _drawn()
	var body := _views.body_of(PEER)
	assert_object(body).is_not_null()
	_views.clear()
	assert_int(_views.count()).is_equal(0)
	assert_object(_views.body_of(PEER)).is_null()
	assert_bool(body.is_inside_tree()).is_false()
	assert_bool(body.is_queued_for_deletion()).is_true()
	# Out of the tree it is still freed, at the frame's end.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(body)).is_false()


func test_a_body_the_model_drops_leaves_the_physics_space_in_that_frame() -> void:
	# A queued node stays in the tree, and its body in the physics space, until the frame's end:
	# the local player's push search (priority 0) runs after AvatarViews (-80) in the same frame.
	var spot := Vector3(2, 0, 0)
	_snapshot(1, spot, Vector3.FORWARD)
	await _drawn()
	var found: Array[int] = []
	var search := Step.new(0, func() -> void: found.append(_living_at(spot)), false)
	auto_free(search)
	add_child(search)
	await _drawn()
	# The search sees a drawn body.
	assert_array(found).is_not_empty()
	assert_int(found.back()).is_equal(1)
	found.clear()
	# The session folds a new map (LoadMatch) or the lobby, which forget the avatars.
	var fold := Step.new(SessionNode.PHYSICS_PRIORITY, _model.clear_match, true)
	auto_free(fold)
	add_child(fold)
	await _drawn()
	assert_int(_views.count()).is_equal(0)
	assert_array(found).is_not_empty()
	assert_bool(found.has(1)).is_false()


func test_a_player_placed_in_the_frame_the_others_go_is_not_pushed_by_their_bodies() -> void:
	# End -> Lobby: one host step brings PhaseChanged, which forgets the avatars, and the
	# placement's Correction, which teleports the local player, here onto another player's last
	# round spot (the greybox lobby and round markers share coordinates).
	var world := PlayerTestWorld.new()
	auto_free(world)
	add_child(world)
	var player := world.add_player(Vector3(-3, 0, 0))
	var spot := Vector3(2, 0, 0)
	_snapshot(1, spot, Vector3.FORWARD)
	await world.frames(10)
	assert_vector(_views.body_of(PEER).global_position).is_equal_approx(spot, Vector3.ONE * 1e-3)
	var place := func() -> void:
		_model.clear_match()
		player.teleport(Transform3D(player.global_basis, spot))
	var placement := Step.new(SessionNode.PHYSICS_PRIORITY, place, true)
	auto_free(placement)
	add_child(placement)
	await world.frames(3)
	assert_float(world.horizontal_distance(player.global_position, spot)).is_less(1e-3)


func test_entering_the_lobby_from_the_map_forgets_the_round_poses() -> void:
	# End -> Lobby (#241): the next snapshot draws the player again, but the round's snapshots stay
	# behind the interpolation delay. Drawn from them, it stood at its round spot for that delay,
	# where the greybox lobby can put another player (its markers share the round's coordinates),
	# and pushed that player off its lobby Correction.
	var round_spot := Vector3(2, 0, 0)
	var lobby_spot := Vector3(-4, 0, 0)
	_model.phase = &"end"
	for tick: int in range(1, 6):
		_snapshot(tick, round_spot, Vector3.FORWARD)
	await _drawn()
	assert_vector(_views.body_of(PEER).global_position).is_equal_approx(
		round_spot, Vector3.ONE * 1e-3
	)
	# The row's placement comes before the phase it enters (Match._transition).
	_views.on_event(&"PlayersPlaced", {"spots": {PEER: lobby_spot}})
	_model.fold(&"PhaseChanged", {"phase": &"lobby", "end_tick": -1})
	_views.on_event(&"PhaseChanged", {"phase": &"lobby", "end_tick": -1})
	_snapshot(6, lobby_spot, Vector3.FORWARD)
	for frame: int in 4:
		_now += FRAME_USEC
		await get_tree().physics_frame
		assert_int(_living_at(round_spot)).is_equal(0)
	assert_vector(_views.body_of(PEER).global_position).is_equal_approx(
		lobby_spot, Vector3.ONE * 1e-3
	)
	# A phase on the same level forgets nothing: the lobby's countdown keeps the lobby's poses.
	_model.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": 100})
	_views.on_event(&"PhaseChanged", {"phase": &"countdown", "end_tick": 100})
	assert_int(_views.buffer.newest_tick()).is_equal(6)


func test_a_round_snapshot_that_arrives_after_end_to_lobby_is_not_drawn() -> void:
	# #251: the round's snapshot of tick 5 is delayed past the PhaseChanged of tick 6 (unreliable
	# against reliable lanes). It is newer than every snapshot held, so only the host tick
	# estimated at the change keeps it out of the model and the buffer.
	var round_spot := Vector3(2, 0, 0)
	var lobby_spot := Vector3(-4, 0, 0)
	_model.phase = &"end"
	for tick: int in range(1, 5):
		_snapshot(tick, round_spot, Vector3.FORWARD)
	await _drawn()
	assert_int(_views.count()).is_equal(1)
	# Snapshot 5 is late; the change of tick 6 arrives when the snapshot of tick 6 would.
	_now += 2 * TICK_USEC
	_views.on_event(&"PlayersPlaced", {"spots": {PEER: lobby_spot}})
	_model.fold(&"PhaseChanged", {"phase": &"lobby", "end_tick": -1})
	_views.on_event(&"PhaseChanged", {"phase": &"lobby", "end_tick": -1})
	_arrive(5, round_spot)
	assert_bool(_model.avatars.is_empty()).is_true()
	assert_int(_views.buffer.newest_tick()).is_equal(-1)
	for frame: int in 4:
		_now += FRAME_USEC
		await get_tree().physics_frame
		assert_int(_living_at(round_spot)).is_equal(0)
	_now += TICK_USEC
	_arrive(7, lobby_spot)
	for frame: int in 4:
		_now += FRAME_USEC
		await get_tree().physics_frame
		assert_int(_living_at(round_spot)).is_equal(0)
	assert_vector(_views.body_of(PEER).global_position).is_equal_approx(
		lobby_spot, Vector3.ONE * 1e-3
	)


func test_a_replaced_model_no_longer_reads_this_views_host_tick() -> void:
	var old := _model
	assert_bool(old.host_tick_now.is_valid()).is_true()
	var other := ClientModel.new(FixtureBaseMode.mode())
	_views.model = other
	assert_bool(old.host_tick_now.is_valid()).is_false()
	assert_bool(other.host_tick_now == _views.host_tick).is_true()
	_views.model = null
	assert_bool(other.host_tick_now.is_valid()).is_false()


## Waits until AvatarViews has run once more (physics_frame comes before the nodes' step).
func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _snapshot(tick: int, at: Vector3, facing: Vector3, invulnerable := false) -> void:
	var avatar := {
		"position": at,
		"velocity": Vector3.ZERO,
		"facing": facing,
		"downed": false,
		"invulnerable": invulnerable,
		"held_item": -1,
	}
	_now += TICK_USEC
	_arrive(tick, at, avatar)


## The snapshot of `tick` arrives now (the session's order: the model folds it, then the buffer).
func _arrive(tick: int, at: Vector3, avatar := {}) -> void:
	if avatar.is_empty():
		avatar = {"position": at, "velocity": Vector3.ZERO, "facing": Vector3.FORWARD}
	var fields := {"tick": tick, "avatars": {PEER: avatar}}
	_model.fold_snapshot(fields)
	_views.buffer.add(tick, fields["avatars"] as Dictionary, _now)


## How many bodies a horizontal ray across the origin at `height` metres hits, on any layer.
func _ray_hits_at(height: float) -> int:
	var space := _views.get_world_3d().direct_space_state
	var from := Vector3(-3.0, height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(3.0, height, 0.0), 0xFFFFFFFF)
	return 0 if space.intersect_ray(query).is_empty() else 1


## 1 when a shape query on the living layer, as the push search's, finds a body at `at`; else 0.
func _living_at(at: Vector3) -> int:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
	query.collision_mask = PhysicsLayers.LIVING
	var space := _views.get_world_3d().direct_space_state
	return 0 if space.intersect_shape(query).is_empty() else 1


## Calls `action` in each physics step at `priority`, or in the first one only (`once`).
class Step:
	extends Node

	var _action: Callable
	var _once: bool

	func _init(priority: int, action: Callable, once: bool) -> void:
		process_physics_priority = priority
		_action = action
		_once = once

	func _physics_process(_delta: float) -> void:
		_action.call()
		if _once:
			set_physics_process(false)
