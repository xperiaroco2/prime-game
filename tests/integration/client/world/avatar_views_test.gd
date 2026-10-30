extends GdUnitTestSuite
## AvatarViews (ARCHITECTURE §4.7): at physics priority -80 each other player of the model's newest
## snapshot gets a RemotePlayerBody at SnapshotBuffer's pose, the yaw on the body and the pitch on
## the head; a vertical facing keeps the turn and gives no NaN; a player the model drops goes; a
## PlayersPlaced snaps; a LoadMatch and a phase on another level (End -> Lobby, #241) forget the
## poses; the estimated host tick never runs backwards; a player the model knows as downed is on
## the downed layer, where no push searches (§7.1), and is drawn as a RagdollView (KE7, §4.7.9),
## the own player too, as its ragdoll only; a revive takes the ragdoll out of the physics space in
## that frame, a death parks it for BodyViews; a body the model drops leaves the physics space in
## that frame, before the local player's push search (#242), and clear() takes every body out of
## the tree the same way.

const PEER := 2
const OWN := 3
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
	# Knocked down (KE7): the body hides its capsule and head and turns its collision off; a
	# ragdoll on the downed layer, with the world mask only, is its body, held to its point.
	assert_bool(body.is_downed()).is_true()
	assert_bool(body.head().visible).is_false()
	var mesh := body.get_node("Mesh") as MeshInstance3D
	var shape := body.get_node("CollisionShape3D") as CollisionShape3D
	assert_bool(mesh.visible).is_false()
	assert_bool(shape.disabled).is_true()
	var ragdoll := _views.ragdoll_of(PEER)
	assert_object(ragdoll).is_not_null()
	assert_int(_views.ragdoll_count()).is_equal(1)
	assert_int(ragdoll.peer).is_equal(PEER)
	assert_int(ragdoll.collision_layer).is_equal(PhysicsLayers.DOWNED)
	assert_int(ragdoll.collision_mask).is_equal(PhysicsLayers.WORLD)
	assert_bool(ragdoll.is_in_group(SightHider.GROUP)).is_true()
	assert_vector(ragdoll.held_point()).is_equal(body.global_position)
	assert_vector(_views.point_of(PEER, Vector3.ONE)).is_equal(body.global_position)
	# A new match forgets the knockdown: the body is on the living layer again, standing, and the
	# ragdoll is out of the physics space in that frame.
	_model.lives.erase(PEER)
	await _drawn()
	assert_bool(body.is_living()).is_true()
	assert_bool(body.is_downed()).is_false()
	assert_bool(body.head().visible).is_true()
	assert_bool(mesh.visible).is_true()
	assert_bool(shape.disabled).is_false()
	assert_float((mesh.global_transform * mesh.get_aabb()).end.y).is_greater(1.7)
	assert_object(_views.ragdoll_of(PEER)).is_null()
	assert_bool(is_instance_valid(ragdoll) and ragdoll.is_inside_tree()).is_false()
	assert_vector(_views.point_of(PEER, Vector3.ONE)).is_equal(Vector3.ONE)
	await _drawn()
	assert_int(_ray_hits_at(1.5)).is_equal(1)


## KE5, KE7: the own player's avatar, which its snapshot carries while it is knocked down, is drawn
## as its ragdoll only, never as a stranger's body; living, it has none.
func test_the_own_knocked_down_avatar_is_drawn_as_its_ragdoll_only() -> void:
	_model.own_peer = OWN
	_model.fold(&"PlayerJoined", {"peer": OWN, "name": "Iryna", "spot": Vector3.ZERO, "colour": 2})
	_model.fold(&"KnockedDown", {"peer": OWN, "position": Vector3(1, 0, 1)})
	_arrive_own(1, Vector3(1, 0, 1))
	await _drawn()
	assert_object(_views.body_of(OWN)).is_null()
	var ragdoll := _views.ragdoll_of(OWN)
	assert_object(ragdoll).is_not_null()
	assert_object(ragdoll.colour()).is_equal(BodyColours.of(2))
	assert_vector(_views.point_of(OWN, Vector3.ZERO)).is_equal(Vector3(1, 0, 1))
	_model.fold(&"Revived", {"peer": OWN, "raiser": PEER})
	await _drawn()
	assert_object(_views.ragdoll_of(OWN)).is_null()
	assert_bool(is_instance_valid(ragdoll) and ragdoll.is_inside_tree()).is_false()
	assert_object(_views.body_of(OWN)).is_null()


## §7.1.21 (#1393): a limp player lies as its ragdoll though it is living, with the host body's
## velocity, its living body hidden; once a snapshot shows it standing the ragdoll goes. The own
## limp avatar is drawn as its ragdoll only.
func test_a_limp_player_is_drawn_as_its_ragdoll_until_it_stands() -> void:
	_model.own_peer = OWN
	var limp := {
		"position": Vector3.ZERO,
		"velocity": Vector3(1, 0, 0),
		"facing": Vector3.FORWARD,
		"limp": true,
	}
	_now += TICK_USEC
	var fields := {"tick": 1, "avatars": {PEER: limp, OWN: limp.duplicate()}}
	_model.fold_snapshot(fields)
	_views.buffer.add(1, fields["avatars"] as Dictionary, _now)
	await _drawn()
	assert_int(_model.life_of(PEER)).is_equal(ClientModel.Life.ALIVE)
	var ragdoll := _views.ragdoll_of(PEER)
	assert_object(ragdoll).is_not_null()
	assert_vector(ragdoll.held_velocity()).is_equal(Vector3(1, 0, 0))
	assert_bool(_views.body_of(PEER).is_downed()).is_true()
	assert_object(_views.ragdoll_of(OWN)).is_not_null()
	assert_object(_views.body_of(OWN)).is_null()
	_snapshot(2, Vector3.ZERO, Vector3.FORWARD)
	await _drawn()
	assert_object(_views.ragdoll_of(PEER)).is_null()
	assert_object(_views.ragdoll_of(OWN)).is_null()
	assert_bool(_views.body_of(PEER).is_downed()).is_false()


## KE14, the client ADR's host trust: a ragdoll takes its velocity only from a snapshot that shows
## its player knocked down, the host body's. When the reliable KnockedDown overtakes that snapshot,
## the newest one still carries the living player's claimed velocity: the ragdoll starts with none.
## A velocity past SnapshotBuffer.SNAP_SPEED_MPS is cut to it, a huge one stays finite.
func test_a_ragdoll_takes_no_claimed_velocity_only_a_downed_snapshots() -> void:
	var claimed := Vector3(20.0, 0.0, 0.0)
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD, false, false, claimed)
	await _drawn()
	_model.fold(&"KnockedDown", {"peer": PEER, "position": Vector3.ZERO})
	await _drawn()
	var ragdoll := _views.ragdoll_of(PEER)
	assert_vector(ragdoll.held_velocity()).is_equal(Vector3.ZERO)
	assert_bool(ragdoll.linear_velocity.is_finite()).is_true()
	assert_float(ragdoll.linear_velocity.length()).is_less(SnapshotBuffer.SNAP_SPEED_MPS)
	assert_bool(ragdoll.global_position.is_finite()).is_true()
	_snapshot(2, Vector3.ZERO, Vector3.FORWARD, false, false, Vector3(2.0, 1.0, 0.0), true)
	await _drawn()
	assert_vector(ragdoll.held_velocity()).is_equal(Vector3(2.0, 1.0, 0.0))
	_snapshot(3, Vector3.ZERO, Vector3.FORWARD, false, false, Vector3(0.0, 0.0, 90.0), true)
	await _drawn()
	assert_vector(ragdoll.held_velocity()).is_equal_approx(
		Vector3(0.0, 0.0, SnapshotBuffer.SNAP_SPEED_MPS), Vector3.ONE * 0.001
	)
	_snapshot(4, Vector3.ZERO, Vector3.FORWARD, false, false, Vector3(0.0, 0.0, 3.0e38), true)
	await _drawn()
	assert_bool(ragdoll.held_velocity().is_finite()).is_true()
	assert_float(ragdoll.held_velocity().length()).is_less_equal(SnapshotBuffer.SNAP_SPEED_MPS)
	assert_bool(ragdoll.global_position.is_finite()).is_true()


## KD7 (a): at a death the ragdoll is parked for BodyViews in that physics frame; one nobody takes
## goes at the next.
func test_a_death_parks_the_ragdoll_for_the_body_views_and_drops_it_untaken() -> void:
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD)
	_model.fold(&"KnockedDown", {"peer": PEER, "position": Vector3.ZERO})
	await _drawn()
	var ragdoll := _views.ragdoll_of(PEER)
	_model.fold(&"Died", {"peer": PEER, "position": Vector3(0.5, 0, 0)})
	# One step of AvatarViews: BodyViews (-70) would take it in this one.
	await get_tree().physics_frame
	assert_object(_views.ragdoll_of(PEER)).is_null()
	assert_object(_views.release_ragdoll(PEER)).is_same(ragdoll)
	assert_bool(ragdoll.is_inside_tree()).is_false()
	assert_object(_views.release_ragdoll(PEER)).is_null()
	ragdoll.free()
	# Another death nobody takes: the parked ragdoll goes at the next step.
	_model.fold(&"Respawned", {"peer": PEER, "position": Vector3.ZERO})
	await _drawn()
	_model.fold(&"KnockedDown", {"peer": PEER, "position": Vector3.ZERO})
	await _drawn()
	var second := _views.ragdoll_of(PEER)
	_model.fold(&"Died", {"peer": PEER, "position": Vector3.ZERO})
	await get_tree().physics_frame
	assert_bool(second.is_inside_tree()).is_true()
	await get_tree().physics_frame
	assert_bool(is_instance_valid(second) and second.is_inside_tree()).is_false()


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


## #551: a body wears its player's colour from the roster, standing and lying, and a profile change
## repaints the same material, never a new mesh per frame.
func test_a_body_wears_its_players_colour_and_follows_a_profile_change() -> void:
	_model.fold(&"PlayerJoined", {"peer": PEER, "name": "Olena", "spot": Vector3.ZERO, "colour": 4})
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD)
	await _drawn()
	var mesh := _views.body_of(PEER).get_node(^"Mesh") as MeshInstance3D
	var capsule := mesh.mesh as CapsuleMesh
	var material := capsule.material as StandardMaterial3D
	assert_object(material.albedo_color).is_equal(BodyColours.of(4))
	_model.fold(&"ProfileChanged", {"peer": PEER, "name": "Olena", "colour": 7})
	await _drawn()
	assert_object(mesh.mesh).is_same(capsule)
	assert_object(material.albedo_color).is_equal(BodyColours.of(7))
	_model.fold(&"KnockedDown", {"peer": PEER, "position": Vector3.ZERO})
	await _drawn()
	assert_bool(_views.body_of(PEER).is_downed()).is_true()
	assert_object(mesh.mesh).is_same(capsule)
	assert_object(material.albedo_color).is_equal(BodyColours.of(7))
	# The ragdoll wears it too, and follows a change.
	var ragdoll := _views.ragdoll_of(PEER)
	assert_object(ragdoll.colour()).is_equal(BodyColours.of(7))
	_model.fold(&"ProfileChanged", {"peer": PEER, "name": "Olena", "colour": 2})
	await _drawn()
	assert_object(ragdoll.colour()).is_equal(BodyColours.of(2))


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


func test_the_push_search_finds_the_crouched_capsule_in_the_frame_it_crouches() -> void:
	# The crouch ADR, KE7: the capsule switches before the body is placed, so the local player's
	# push search (priority 0, after AvatarViews' -80) never meets a standing capsule 0.6 m taller
	# than a crouched player, nor misses a standing one, in any frame.
	var spot := Vector3(2, 0, 0)
	for tick: int in range(1, 4):
		_snapshot(tick, spot, Vector3.FORWARD)
	await _drawn()
	var seen: Array[Vector3i] = []
	var search := func() -> void:
		var body := _views.body_of(PEER)
		seen.append(Vector3i(int(body.is_crouched()), _living_at(spot, 1.5), _living_at(spot, 0.6)))
	var step := Step.new(0, search, false)
	auto_free(step)
	add_child(step)
	await _drawn()
	for tick: int in range(4, 8):
		_snapshot(tick, spot, Vector3.FORWARD, false, true)
		await _drawn()
	for tick: int in range(8, 12):
		_snapshot(tick, spot, Vector3.FORWARD)
		await _drawn()
	# Standing, then crouched, then standing again: the capsule's top follows in every frame.
	assert_bool(seen.has(Vector3i(0, 1, 1))).is_true()
	assert_bool(seen.has(Vector3i(1, 0, 1))).is_true()
	assert_bool(seen.has(Vector3i(1, 1, 1))).is_false()
	assert_bool(seen.has(Vector3i(0, 0, 1))).is_false()
	assert_int(seen.filter(func(row: Vector3i) -> bool: return row.z == 0).size()).is_equal(0)
	assert_bool(seen.back() == Vector3i(0, 1, 1)).is_true()


func test_a_crouched_body_lowers_its_head_mouth_points_and_look() -> void:
	var rules := _views.rules
	var drop := rules.eye_height_m - rules.crouch_eye_height_m
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD)
	await _drawn()
	var body := _views.body_of(PEER)
	var mesh := body.get_node("Mesh") as MeshInstance3D
	assert_float(body.head().position.y).is_equal_approx(rules.eye_height_m, 1e-5)
	assert_float(_mesh_top(mesh)).is_equal_approx(rules.capsule_height_m, 1e-3)
	for tick: int in range(2, 6):
		_snapshot(tick, Vector3.ZERO, Vector3.FORWARD, false, true)
	await _until_crouched(body)
	# The capsule and its look switch at once; the head eases down at the step's catch-up rate.
	assert_float(_mesh_top(mesh)).is_equal_approx(rules.crouch_height_m, 1e-3)
	assert_float(body.sight_point().y).is_equal_approx(rules.crouch_height_m * 0.5, 1e-5)
	assert_float(body.head().position.y).is_greater(rules.crouch_eye_height_m + 1e-3)
	assert_float(body.head().position.y).is_less(rules.eye_height_m)
	await _frames(30)
	assert_float(body.head().position.y).is_equal_approx(rules.crouch_eye_height_m, 1e-5)
	# The mouth, where the voice plays (M5-5), and the item points come down with the head.
	assert_float(body.mouth_point().position.y).is_equal_approx(
		rules.crouch_eye_height_m - RemotePlayerBody.MOUTH_BELOW_EYE_M, 1e-5
	)
	assert_float(body.hand_point().position.y).is_equal_approx(
		RemotePlayerBody.HAND_POINT.y - drop, 1e-5
	)
	assert_float(body.belt_point().position.y).is_equal_approx(
		RemotePlayerBody.BELT_POINT.y - drop, 1e-5
	)
	assert_float(body.carry_point().position.y).is_equal_approx(
		RemotePlayerBody.CARRY_POINT.y - drop, 1e-5
	)
	# Standing again: everything back up.
	for tick: int in range(6, 10):
		_snapshot(tick, Vector3.ZERO, Vector3.FORWARD)
	await _frames(30)
	assert_bool(body.is_crouched()).is_false()
	assert_float(_mesh_top(mesh)).is_equal_approx(rules.capsule_height_m, 1e-3)
	assert_float(body.head().position.y).is_equal_approx(rules.eye_height_m, 1e-5)
	assert_float(body.mouth_point().position.y).is_equal_approx(
		rules.eye_height_m - RemotePlayerBody.MOUTH_BELOW_EYE_M, 1e-5
	)
	assert_vector(body.hand_point().position).is_equal_approx(
		RemotePlayerBody.HAND_POINT, Vector3.ONE * 1e-5
	)


func test_a_body_first_drawn_crouched_has_its_head_down_at_once() -> void:
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD, false, true)
	await _drawn()
	var body := _views.body_of(PEER)
	assert_bool(body.is_crouched()).is_true()
	assert_float(body.head().position.y).is_equal_approx(_views.rules.crouch_eye_height_m, 1e-5)


func test_a_downed_body_keeps_its_points_up_while_the_crouch_flag_trails_the_knockdown() -> void:
	# The life comes from the newest snapshot, the crouch flag from the drawn tick's: for the
	# interpolation delay after a knockdown, a body that lies can still be told "crouched".
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD)
	await _drawn()
	var body := _views.body_of(PEER)
	var mouth_y := body.mouth_point().position.y
	body.set_downed(true)
	body.set_crouched(true, INF)
	assert_float(body.mouth_point().position.y).is_equal_approx(mouth_y, 1e-5)
	assert_float(body.hand_point().position.y).is_equal_approx(RemotePlayerBody.HAND_POINT.y, 1e-5)


func test_a_mode_without_a_step_height_lowers_the_head_at_once_with_no_nan() -> void:
	# 0 * INF is NaN: a first draw of a mode with step_height_m 0 would blank every point.
	_views.rules.step_height_m = 0.0
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD, false, true)
	await _drawn()
	var body := _views.body_of(PEER)
	assert_float(body.head().position.y).is_equal_approx(_views.rules.crouch_eye_height_m, 1e-5)
	assert_bool(is_nan(body.mouth_point().position.y)).is_false()
	for tick: int in range(2, 6):
		_snapshot(tick, Vector3.ZERO, Vector3.FORWARD)
	await _frames(10)
	assert_float(body.head().position.y).is_equal_approx(_views.rules.eye_height_m, 1e-5)


func test_an_unchanged_crouch_flag_rewrites_no_looks() -> void:
	# AvatarViews calls set_crouched every frame for every body: the shape's transform goes to the
	# physics server only when the flag turns.
	_snapshot(1, Vector3.ZERO, Vector3.FORWARD)
	await _drawn()
	var body := _views.body_of(PEER)
	var shape := body.get_node("CollisionShape3D") as CollisionShape3D
	var marker := Transform3D(Basis.IDENTITY, Vector3(0.0, 7.0, 0.0))
	shape.transform = marker
	await _frames(3)
	assert_bool(shape.transform == marker).is_true()


## Waits until AvatarViews has run once more (physics_frame comes before the nodes' step).
func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


## Waits `count` physics frames (the head eases 0.6 m in about 12 at 60 Hz).
func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().physics_frame


## Waits for the physics frame that draws `body` crouched (at most a second of frames).
func _until_crouched(body: RemotePlayerBody) -> void:
	for frame: int in 60:
		if body.is_crouched():
			return
		await get_tree().physics_frame


## The top of `mesh` above the feet.
func _mesh_top(mesh: MeshInstance3D) -> float:
	return (mesh.global_transform * mesh.get_aabb()).end.y


func _snapshot(
	tick: int,
	at: Vector3,
	facing: Vector3,
	invulnerable := false,
	crouched := false,
	velocity := Vector3.ZERO,
	downed := false,
) -> void:
	var avatar := {
		"position": at,
		"velocity": velocity,
		"facing": facing,
		"downed": downed,
		"crouched": crouched,
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


## The own snapshot of `tick` with the own avatar at `at` (KE5: knocked down) arrives now.
func _arrive_own(tick: int, at: Vector3) -> void:
	_now += TICK_USEC
	var avatar := {"position": at, "velocity": Vector3.ZERO, "facing": Vector3.FORWARD}
	var fields := {"tick": tick, "avatars": {OWN: avatar}}
	_model.fold_snapshot(fields)
	_views.buffer.add(tick, fields["avatars"] as Dictionary, _now)


## How many bodies a horizontal ray across the origin at `height` metres hits, on any layer.
func _ray_hits_at(height: float) -> int:
	var space := _views.get_world_3d().direct_space_state
	var from := Vector3(-3.0, height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(3.0, height, 0.0), 0xFFFFFFFF)
	return 0 if space.intersect_ray(query).is_empty() else 1


## 1 when a shape query on the living layer, as the push search's, finds a body at `at`, `height`
## above it; else 0.
func _living_at(at: Vector3, height := 0.9) -> int:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * height)
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
