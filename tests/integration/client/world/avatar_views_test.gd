extends GdUnitTestSuite
## AvatarViews (ARCHITECTURE §4.7): at physics priority -80 each other player of the model's newest
## snapshot gets a RemotePlayerBody at SnapshotBuffer's pose, the yaw on the body and the pitch on
## the head; a vertical facing keeps the turn and gives no NaN; a player the model drops goes; a
## PlayersPlaced snaps; a LoadMatch forgets the poses; the estimated host tick never runs backwards.

const PEER := 2
const TICK_USEC := 50000
const FRAME_USEC := 16667

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


## Waits until AvatarViews has run once more (physics_frame comes before the nodes' step).
func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _snapshot(tick: int, at: Vector3, facing: Vector3) -> void:
	var avatar := {
		"position": at,
		"velocity": Vector3.ZERO,
		"facing": facing,
		"ghost": false,
		"held_item": -1,
	}
	_now += TICK_USEC
	var fields := {"tick": tick, "avatars": {PEER: avatar}}
	_model.fold_snapshot(fields)
	_views.buffer.add(tick, fields["avatars"] as Dictionary, _now)
