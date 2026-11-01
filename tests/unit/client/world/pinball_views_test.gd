extends GdUnitTestSuite
## The pinball's views together (#1400, ARCHITECTURE §4.7.63): placed on the level's markers (none:
## nothing drawn), the flippers following PinballState's held state, the ball fed from each newly
## folded snapshot (never under a skipped one's tick) and drawn at the remote bodies' render tick,
## a new game starting the track afresh, and a LoadMatch or a level swap snapping the close-up.

const LOBBY := "res://levels/lobby/lobby.tscn"
const OWN := 2

var _viewport: SubViewport
var _views: PinballViews
var _model: ClientModel
var _render := -1.0


func before_test() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_model = ClientModel.new(FixturePinball.mode())
	_model.own_peer = OWN
	_views = PinballViews.new()
	_views.model = _model
	_views.drawn_at = func() -> float: return _render
	_views.set_physics_process(false)
	_views.set_process(false)
	_viewport.add_child(_views)


func after_test() -> void:
	_viewport.free()


func test_the_views_sit_on_the_level_s_markers_and_hide_without_a_level() -> void:
	var level := _lobby()
	var mount := level.get_node(^"Pinball/TableMount") as Node3D
	assert_bool(mount.is_in_group(PinballViews.TABLE_GROUP)).is_true()
	assert_bool(_views.table.visible).is_true()
	assert_bool(_views.table.global_transform.is_equal_approx(mount.global_transform)).is_true()
	assert_bool(_views.display.visible).is_true()
	assert_object(_views.close_up.marker).is_not_null()
	_views.level = null
	assert_bool(_views.table.visible).is_false()
	assert_bool(_views.display.visible).is_false()
	assert_object(_views.close_up.marker).is_null()


func test_a_level_without_markers_draws_nothing() -> void:
	var bare := Node3D.new()
	_viewport.add_child(bare)
	_views.level = bare
	assert_bool(_views.table.visible).is_false()
	assert_bool(_views.display.visible).is_false()


func test_the_flippers_follow_the_host_s_state() -> void:
	_lobby()
	_model.pinball.right = true
	_views._physics_process(1.0)
	assert_float(_views.table.flipper_angle(1)).is_equal_approx(
		deg_to_rad(PinballTableView.SWING_DEG), 1e-5
	)
	assert_float(_views.table.flipper_angle(0)).is_zero()


func test_the_ball_is_drawn_at_the_render_tick_from_the_folded_snapshots() -> void:
	_lobby()
	_snapshot(10, Vector3(0.0, 0.03, 0.4))
	_snapshot(11, Vector3(0.2, 0.03, 0.0))
	_render = 10.5
	_views._physics_process(0.016)
	assert_bool(_views.table.ball.visible).is_true()
	assert_vector(_views.table.ball.position).is_equal_approx(
		Vector3(0.1, 0.03, 0.2), Vector3.ONE * 1e-5
	)
	_render = -1.0
	_views._physics_process(0.016)
	assert_bool(_views.table.ball.visible).is_false()


func test_a_skipped_snapshot_adds_no_sample_under_its_tick() -> void:
	_snapshot(10, Vector3(0.1, 0.03, 0.0))
	# ClientSession emits a skipped snapshot too; the model kept tick 10's ball.
	_views.on_snapshot(12, {})
	assert_int(_views.track.newest()).is_equal(10)


func test_a_new_game_starts_the_track_afresh() -> void:
	_model.pinball.game = 1
	_snapshot(10, Vector3(0.1, 0.03, 0.0))
	_model.pinball.game = 2
	_model.pinball.fold_snapshot({"tick": 11})
	_views.on_snapshot(11, {})
	assert_object(_views.track.at(10.0)).is_null()


func test_a_load_match_and_a_level_swap_snap_the_close_up_back() -> void:
	_lobby()
	var player := (load("res://client/player/player.tscn") as PackedScene).instantiate()
	_viewport.add_child(player)
	player.set_physics_process(false)
	_views.close_up.player = player as PlayerController
	_views.close_up.model = _model
	_model.pinball.player = OWN
	_views.close_up.step(0.1)
	assert_bool(_views.close_up.active()).is_true()
	_views.on_event(&"LoadMatch", {})
	assert_bool(_views.close_up.active()).is_false()
	_views.close_up.step(0.1)
	assert_bool(_views.close_up.active()).is_true()
	_views.level = null
	assert_bool(_views.close_up.active()).is_false()
	assert_bool((player as PlayerController).held).is_false()


func _lobby() -> Node:
	var level := (load(LOBBY) as PackedScene).instantiate()
	_viewport.add_child(level)
	_views.level = level
	return level


## A snapshot of `tick` with the ball at `place`, folded as ClientModel would, then emitted.
func _snapshot(tick: int, place: Vector3) -> void:
	_model.pinball.fold_snapshot({"tick": tick, "ball": place})
	_views.on_snapshot(tick, {})
