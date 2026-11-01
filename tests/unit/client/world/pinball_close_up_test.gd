extends GdUnitTestSuite
## The seated player's close-up (#1400, ARCHITECTURE §4.7.63): seated, the lens eases from the eye
## to the marker, becomes current, holds the keys and hides the hand; the seat's end lets the keys
## go at once and eases back to the eye; a knockdown, a LoadMatch or a level swap snap back; another
## player's seat touches nothing here; the controller's head is never moved; and in the hall the
## table lies whole inside the close-up's view and fills most of its height.

const PLAYER := preload("res://client/player/player.tscn")
const LOBBY := "res://levels/lobby/lobby.tscn"
const OWN := 2

var _viewport: SubViewport
var _player: PlayerController
var _marker: Marker3D
var _close_up: PinballCloseUp
var _model: ClientModel


func before_test() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_player = PLAYER.instantiate() as PlayerController
	_viewport.add_child(_player)
	_player.set_physics_process(false)
	_player.get_camera().make_current()
	_marker = Marker3D.new()
	_marker.position = Vector3(3, 2.5, -1)
	_marker.rotation = Vector3(deg_to_rad(-60), PI, 0)
	_viewport.add_child(_marker)
	_model = ClientModel.new(FixturePinball.mode())
	_model.own_peer = OWN
	_close_up = PinballCloseUp.new()
	_close_up.model = _model
	_close_up.player = _player
	_close_up.marker = _marker
	_close_up.set_process(false)
	_viewport.add_child(_close_up)


func after_test() -> void:
	_viewport.free()


func test_the_lens_culls_as_every_live_camera() -> void:
	assert_int(_close_up.camera.cull_mask).is_equal(PhotoLayers.LIVE_VIEW)


func test_a_seat_eases_the_lens_to_the_marker_and_holds_the_keys() -> void:
	var eye := _player.get_camera().global_transform
	_model.pinball.player = OWN
	_close_up.step(PinballCloseUp.EASE_S / 2.0)
	assert_bool(_close_up.active()).is_true()
	assert_bool(_close_up.camera.current).is_true()
	assert_bool(_player.held).is_true()
	assert_bool(_player.hand_view().visible).is_false()
	assert_object(_close_up.live_camera()).is_same(_close_up.camera)
	# Half the time is half the way (smoothstep's middle): between the eye and the marker.
	var mid := _close_up.camera.global_position
	var want := eye.origin.lerp(_marker.global_position, 0.5)
	assert_vector(mid).is_equal_approx(want, Vector3.ONE * 1e-3)
	_close_up.step(PinballCloseUp.EASE_S)
	(
		assert_bool(_close_up.camera.global_transform.is_equal_approx(_marker.global_transform))
		. is_true()
	)


func test_the_seat_s_end_lets_the_keys_go_and_eases_back_to_the_eye() -> void:
	_model.pinball.player = OWN
	_close_up.step(PinballCloseUp.EASE_S)
	_model.pinball.player = -1
	_close_up.step(PinballCloseUp.EASE_S / 2.0)
	assert_bool(_player.held).is_false()
	assert_bool(_close_up.camera.current).is_true()
	_close_up.step(PinballCloseUp.EASE_S)
	assert_bool(_close_up.active()).is_false()
	assert_object(_close_up.live_camera()).is_null()
	assert_bool(_player.get_camera().current).is_true()
	assert_bool(_player.hand_view().visible).is_true()


func test_another_player_s_seat_leaves_the_own_view_alone() -> void:
	_model.pinball.player = OWN + 1
	_close_up.step(PinballCloseUp.EASE_S)
	assert_bool(_close_up.active()).is_false()
	assert_bool(_player.get_camera().current).is_true()
	assert_bool(_player.held).is_false()


func test_a_knockdown_snaps_back_without_taking_the_view_from_another_camera() -> void:
	_model.pinball.player = OWN
	_close_up.step(PinballCloseUp.EASE_S)
	# LifeView's downed camera takes the view at the knockdown.
	var downed := Camera3D.new()
	_viewport.add_child(downed)
	downed.make_current()
	_model.lives[OWN] = ClientModel.Life.DOWNED
	_close_up.step(0.01)
	assert_bool(_close_up.active()).is_false()
	assert_bool(_player.held).is_false()
	assert_bool(downed.current).is_true()


func test_a_snap_restores_the_eye_at_once() -> void:
	_model.pinball.player = OWN
	_close_up.step(PinballCloseUp.EASE_S / 3.0)
	_close_up.snap()
	assert_bool(_close_up.active()).is_false()
	assert_bool(_player.get_camera().current).is_true()
	assert_bool(_player.held).is_false()
	assert_bool(_player.hand_view().visible).is_true()


func test_a_marker_gone_snaps_back() -> void:
	_model.pinball.player = OWN
	_close_up.step(PinballCloseUp.EASE_S)
	_marker.free()
	_close_up.step(0.01)
	assert_bool(_close_up.active()).is_false()
	assert_bool(_player.get_camera().current).is_true()


func test_a_hold_another_view_set_is_not_let_go() -> void:
	_player.held = true
	_model.pinball.player = OWN
	_close_up.step(PinballCloseUp.EASE_S)
	_close_up.snap()
	assert_bool(_player.held).is_true()


func test_a_whole_seat_never_moves_the_controller_s_head() -> void:
	var head := _player.get_camera().global_transform
	_model.pinball.player = OWN
	_close_up.step(PinballCloseUp.EASE_S)
	_close_up.step(1.0)
	_model.pinball.player = -1
	_close_up.step(PinballCloseUp.EASE_S * 2.0)
	assert_bool(_player.get_camera().global_transform.is_equal_approx(head)).is_true()


func test_item_world_gives_life_view_the_close_up_lens_while_seated() -> void:
	# ItemWorld.live_camera is LifeView's view_camera (Game._start_client): with no viewfinder up
	# the seated player's lens is the camera the living see through (LifeView makes it current and
	# raises no one through it), and the eye again once the seat's view is down.
	var world := ItemWorld.new()
	var close_up := world.pinball.close_up
	close_up.model = _model
	close_up.player = _player
	close_up.marker = _marker
	close_up.set_process(false)
	_viewport.add_child(world)
	assert_object(world.viewfinder.live_camera()).is_null()
	assert_object(world.live_camera()).is_null()
	_model.pinball.player = OWN
	close_up.step(PinballCloseUp.EASE_S / 2.0)
	assert_object(world.live_camera()).is_same(close_up.camera)
	_model.pinball.player = -1
	close_up.step(PinballCloseUp.EASE_S * 2.0)
	assert_object(world.live_camera()).is_null()


func test_in_the_hall_the_table_fills_the_close_up_s_view() -> void:
	var level := (load(LOBBY) as PackedScene).instantiate()
	_viewport.add_child(level)
	var views := PinballViews.new()
	_viewport.add_child(views)
	views.level = level
	assert_bool(views.table.visible).is_true()
	assert_object(views.close_up.marker).is_not_null()
	var lens := views.close_up.camera
	lens.global_transform = views.close_up.marker.global_transform
	lens.make_current()
	var screen := Vector2(_viewport.size)
	var box := Rect2()
	var first := true
	for mesh: MeshInstance3D in views.table.find_children("*", "MeshInstance3D", true, false):
		if mesh == views.table.ball:
			continue
		var aabb := mesh.global_transform * mesh.get_aabb()
		for i in 8:
			var corner := aabb.get_endpoint(i)
			(
				assert_bool(lens.is_position_in_frustum(corner))
				. override_failure_message("%s's corner %s is out of view" % [mesh.name, corner])
				. is_true()
			)
			var at := lens.unproject_position(corner)
			box = Rect2(at, Vector2.ZERO) if first else box.expand(at)
			first = false
	# The display's best line shows at the top of the seated view.
	assert_bool(views.display.visible).is_true()
	assert_bool(lens.is_position_in_frustum(views.display.best.global_position)).is_true()
	# Most of the screen's height: the table, not the room.
	assert_float(box.size.y / screen.y).is_greater(0.6)
	assert_bool(Rect2(Vector2.ZERO, screen).encloses(box)).is_true()
