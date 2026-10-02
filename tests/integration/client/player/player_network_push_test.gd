extends GdUnitTestSuite
## Pushing over the network (ARCHITECTURE §7.1 "Pushing apart", §4.7): the two-client push tests
## of `player_controller_push_test.gd` through the real pipeline instead of a fixed trail: a host
## Game and a joined Game over a LoopbackHub, each drawing the other at SnapshotBuffer's
## interpolation delay. Each moves only its own player, and the host corrects nobody for it.
##
## Every physics frame a probe between Avatars (-80) and the players (0) asserts that the physics
## server already holds the pose Avatars set in that frame, and that a shape query of the kind the
## push search makes (the living layer, in the world's direct space state) finds the capsule there:
## at its centre, and, when it moved, at a point just inside its new front that the last frame's
## capsule did not hold. The transform check failed on most frames a body moved (30 to 173 stale
## frames per test) while RemotePlayerBody was an AnimatableBody3D with `sync_to_physics` off and
## placed without force_update_transform(). With an AnimatableBody3D (`sync_to_physics` off) that
## does call force_update_transform(), both checks fail (checked once, 2026-10-01: 30 to 173 stale
## frames and 12 to 173 missed queries per test); the StaticBody3D passes both.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## Between Avatars (-80) and the local player (0).
const PROBE_PRIORITY := -50
## How far apart, in metres, the server's and the node's positions of a body may be.
const SAME := 0.0001
## The front point's depth inside the new capsule, and the least horizontal move in a frame that
## puts it outside the last frame's capsule with room to spare, in metres.
const FRONT_INSIDE := 0.005
const FRONT_MOVE := 0.015
## The query sphere's radius: a point, in metres.
const POINT := 0.001

var _tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")
var _rules := FixtureModes.player_rules()
var _pair: NetPair


## Compares every remote body of one game with the physics server in each physics frame.
class SameFrameProbe:
	extends Node
	var avatars: AvatarViews
	var rules: PlayerRules
	var checked := 0
	var stale := 0
	## Shape queries that did not find the capsule where it was placed this frame.
	var missed := 0
	## Frames with a front query (the body moved far enough).
	var fronts := 0
	var _last: Dictionary[RID, Vector3] = {}

	func _init(of: AvatarViews, player_rules: PlayerRules) -> void:
		avatars = of
		rules = player_rules
		process_physics_priority = PROBE_PRIORITY

	func _physics_process(_delta: float) -> void:
		for body: Node in avatars.get_children():
			var remote := body as RemotePlayerBody
			if remote == null or remote.is_queued_for_deletion():
				continue
			var state: Variant = PhysicsServer3D.body_get_state(
				remote.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM
			)
			var server: Transform3D = state
			checked += 1
			if server.origin.distance_to(remote.global_position) > SAME:
				stale += 1
			var centre := remote.global_position + Vector3.UP * rules.capsule_height_m * 0.5
			if not _hits(remote, centre):
				missed += 1
			var rid := remote.get_rid()
			if _last.has(rid):
				var moved := centre - _last[rid]
				moved.y = 0.0
				if moved.length() > FRONT_MOVE:
					fronts += 1
					var inside := rules.capsule_radius_m - FRONT_INSIDE
					if not _hits(remote, centre + moved.normalized() * inside):
						missed += 1
			_last[rid] = centre

	## Whether a point query on the living layer, as the push search's, finds `remote` at `at`.
	func _hits(remote: RemotePlayerBody, at: Vector3) -> bool:
		var sphere := SphereShape3D.new()
		sphere.radius = POINT
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.transform = Transform3D(Basis.IDENTITY, at)
		query.collision_mask = PhysicsLayers.LIVING
		var space := avatars.get_world_3d().direct_space_state
		for hit: Dictionary in space.intersect_shape(query, 8):
			if hit["rid"] == remote.get_rid():
				return true
		return false


func before_test() -> void:
	_pair = NetPair.new()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_the_pushed_client_moves_its_player_from_the_pushers_interpolated_motion() -> void:
	assert_bool(await _pair.start()).is_true()
	var probes := _probes()
	var pusher := _pair.host.player()
	var standing := _pair.client.player()
	assert_float(standing.global_position.z - pusher.global_position.z).is_equal_approx(-2.0, 0.01)
	pusher.move_input = Vector2(0.0, 1.0)
	var views: Array[float] = await _run(150)
	# The pushed client moved its player out of the way it saw the pusher come, and the pusher got
	# past, never deeper in the other's late capsule than a pusher may go.
	assert_float(standing.global_position.z).is_less(-2.2)
	assert_float(pusher.global_position.z).is_less(-3.0)
	assert_float(views[0]).is_less(_tuning.push_max_overlap + 0.01)
	assert_float(views[1]).is_less(0.1)
	_assert_uncorrected_and_same_frame(probes)
	await _pair.stop()


func test_head_on_nobody_passes_through() -> void:
	assert_bool(await _pair.start()).is_true()
	var probes := _probes()
	var one := _pair.host.player()
	var other := _pair.client.player()
	other.look(PI, 0.0)
	one.move_input = Vector2(0.0, 1.0)
	other.move_input = Vector2(0.0, 1.0)
	var views: Array[float] = await _run(180)
	# The other's late capsule keeps coming for the delay after that player stopped: a client sees
	# it at most one step of walking deeper before its own player steps back out.
	var one_step := _rules.walk_speed_mps / Engine.physics_ticks_per_second
	assert_float(views[0]).is_less(_tuning.push_max_overlap + one_step + 0.01)
	assert_float(views[1]).is_less(_tuning.push_max_overlap + one_step + 0.01)
	# They slid apart and walked on past each other.
	assert_float(one.global_position.z).is_less(-3.0)
	assert_float(other.global_position.z).is_greater(0.0)
	_assert_uncorrected_and_same_frame(probes)
	await _pair.stop()


## A probe in each game.
func _probes() -> Array[SameFrameProbe]:
	var found: Array[SameFrameProbe] = []
	for game: Game in [_pair.host, _pair.client]:
		var probe := SameFrameProbe.new(game.avatars(), _rules)
		game.add_child(probe)
		found.append(probe)
	return found


## Runs `count` physics frames; returns the deepest overlap each client saw between its own player
## and its drawing of the other: [the host's view, the joiner's view].
func _run(count: int) -> Array[float]:
	var deepest: Array[float] = [-INF, -INF]
	var touching := _rules.capsule_radius_m * 2.0
	var games: Array[Game] = [_pair.host, _pair.client]
	for i: int in count:
		await _pair.frames(1)
		for side: int in 2:
			var game := games[side]
			var other := _pair.peer_of(games[1 - side])
			var drawn := game.avatars().body_of(other)
			if drawn == null:
				continue
			var own := game.player().global_position
			var apart := Vector2(own.x - drawn.global_position.x, own.z - drawn.global_position.z)
			deepest[side] = maxf(deepest[side], touching - apart.length())
	return deepest


func _assert_uncorrected_and_same_frame(probes: Array[SameFrameProbe]) -> void:
	assert_int(_pair.host.client().corrections).is_equal(0)
	assert_int(_pair.client.client().corrections).is_equal(0)
	for probe: SameFrameProbe in probes:
		assert_int(probe.checked).is_greater(100)
		assert_int(probe.stale).is_equal(0)
		assert_int(probe.fronts).is_greater(10)
		assert_int(probe.missed).is_equal(0)
