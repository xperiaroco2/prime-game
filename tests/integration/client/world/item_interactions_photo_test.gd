extends GdUnitTestSuite
## E at the photo camera and its viewfinder against a fixture world (ARCHITECTURE §4.7.56, #786,
## photo P7; the photo ADR §2, §3.1): the real PlayerController on a floor, looking through its own
## camera at the camera station of FixturePhotoModes, the photo spot further along -Z. E at an empty
## camera with a fresh film carried sends Interact(camera, item -1), the load. At a camera holding a
## film a tap opens the viewfinder (nothing sent) and a hold of HOLD_SECONDS sends PickUp of the
## film, cooking's gesture. In the view the shot sends Interact(camera, item -1) while the film has
## frames left; the lens is current at the frame's pose, the player held, its hand hidden, the
## frames left shown. It opens only from inside the camera's cylinder with the floor point in sight
## (none from afar, none through a wall) and closes on E, a hit, a knockdown, the film taken out or
## gone, the player out of the cylinder, the line of sight cut, and the keys no longer listening.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const CAMERA := 30
const SPOT := 31
const FILM := 40
## The camera's floor point 0.7 m ahead of the feet: inside its 1 m cylinder less the margin.
const CAMERA_AT := Vector3(0, 0, -0.7)
const SPOT_AT := Vector3(0, 0, -8)

var _world: Node3D
var _player: PlayerController
var _keys: ItemInteractions
var _finder: PhotoViewfinder
var _harness: Harness
var _model: ClientModel
var _mode: GameMode


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_model = _harness.session.model
	_mode = FixturePhotoModes.basic()
	_keys = ItemInteractions.new()
	_keys.reads_device_input = false
	_keys.setup(_harness.session, _mode)
	_keys.player = _player
	_finder = PhotoViewfinder.new()
	_finder.model = _model
	_finder.mode = _mode
	_finder.player = _player
	_keys.viewfinder = _finder
	_world.add_child(_keys)
	_world.add_child(_finder)
	_fold(StationPlacedEvent.new(CAMERA, &"camera", Color.WHITE, CAMERA_AT))
	_fold(StationPlacedEvent.new(SPOT, &"photo_spot", Color.WHITE, SPOT_AT))
	_fold(TaskStateEvent.new(0, &"photo", 0, 2))
	_fold(ItemSpawnedEvent.new(FILM, &"film", Vector3(0, 0, 5)))
	_fold(ItemPickedUpEvent.new(_model.own_peer, FILM))


func after_test() -> void:
	_world.free()
	_harness.close()


func test_e_at_an_empty_camera_with_a_fresh_film_sends_the_load() -> void:
	await _look_at_camera()
	assert_int(_keys.station_target()).is_equal(CAMERA)
	assert_int(_keys.press_interact()).is_greater(0)
	assert_bool(_keys.viewing()).is_false()
	_harness.pump()
	var sent := _harness.sent_named(Intents.INTERACT)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["station"] as int).is_equal(CAMERA)
	assert_int(sent[0].fields["item"] as int).is_equal(-1)


func test_an_empty_camera_offers_nothing_with_an_exposed_film() -> void:
	_load()
	_fold(ShotTakenEvent.new(CAMERA, FILM, 0))
	_fold(ItemPickedUpEvent.new(_model.own_peer, FILM))
	await _look_at_camera()
	assert_int(_keys.station_target()).is_equal(-1)
	assert_int(_keys.interact()).is_equal(-1)


func test_a_tap_at_a_loaded_camera_opens_the_view_and_sends_nothing() -> void:
	_load()
	await _look_at_camera()
	assert_int(_keys.station_target()).is_equal(CAMERA)
	assert_int(_keys.press_interact()).is_equal(-1)
	assert_int(_keys.held_camera()).is_equal(CAMERA)
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS * 0.5)).is_equal(-1)
	assert_int(_keys.release_interact()).is_equal(-1)
	assert_bool(_keys.viewing()).is_true()
	assert_int(_finder.station()).is_equal(CAMERA)
	_harness.pump()
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(0)
	assert_int(_harness.sent_named(Intents.PICK_UP).size()).is_equal(0)


func test_the_view_looks_through_the_lens_at_the_frame_s_pose_with_the_player_held() -> void:
	await _open_view()
	var frame := PhotoUse.frame_of(_model, _mode, CAMERA)
	assert_bool(_finder.camera.current).is_true()
	assert_object(_finder.live_camera()).is_same(_finder.camera)
	assert_vector(_finder.camera.global_position).is_equal_approx(frame.lens, Vector3.ONE * 1e-4)
	var ahead := -_finder.camera.global_basis.z
	assert_vector(ahead).is_equal_approx(-frame.basis.z, Vector3.ONE * 1e-4)
	assert_int(_finder.camera.keep_aspect).is_equal(Camera3D.KEEP_HEIGHT)
	var screen := _finder.get_viewport().get_visible_rect().size
	var fov := PhotoViewfinder.fov_for(FixturePhotoModes.FOV_DEG, FixturePhotoModes.ASPECT, screen)
	assert_float(_finder.camera.fov).is_equal_approx(fov, 1e-4)
	assert_bool(_player.held).is_true()
	assert_bool(_player.hand_view().visible).is_false()
	assert_bool(_finder.mask.visible).is_true()


func test_the_mask_bars_meet_the_photo_s_edges_and_the_counter_shows_the_frames_left() -> void:
	await _open_view()
	await _process_frames(2)
	var screen := _finder.get_viewport().get_visible_rect().size
	var photo := PhotoViewfinder.photo_rect(FixturePhotoModes.ASPECT, screen)
	var left := _finder.mask.get_node(^"Left") as ColorRect
	var right := _finder.mask.get_node(^"Right") as ColorRect
	var top := _finder.mask.get_node(^"Top") as ColorRect
	var bottom := _finder.mask.get_node(^"Bottom") as ColorRect
	var near := Vector2.ONE * 1e-3
	assert_vector(left.position + Vector2(left.size.x, 0)).is_equal_approx(
		Vector2(photo.position.x, 0), near
	)
	assert_vector(right.position).is_equal_approx(Vector2(photo.end.x, 0), near)
	assert_float(top.position.y + top.size.y).is_equal_approx(photo.position.y, 1e-3)
	assert_float(bottom.position.y).is_equal_approx(photo.end.y, 1e-3)
	assert_str(_finder.counter.text).is_equal(str(FixturePhotoModes.FRAMES))
	_fold(ShotTakenEvent.new(CAMERA, FILM, 0))
	await _process_frames(2)
	assert_str(_finder.counter.text).is_equal(str(FixturePhotoModes.FRAMES - 1))


func test_a_hold_at_a_loaded_camera_takes_the_film_out_once_and_opens_no_view() -> void:
	_load()
	await _look_at_camera()
	_keys.press_interact()
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS * 0.6)).is_equal(-1)
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS * 0.6)).is_greater(0)
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS)).is_equal(-1)
	assert_int(_keys.release_interact()).is_equal(-1)
	assert_bool(_keys.viewing()).is_false()
	_harness.pump()
	var sent := _harness.sent_named(Intents.PICK_UP)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["item"] as int).is_equal(FILM)
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(0)


func test_the_shot_sends_interact_at_the_camera_until_no_frame_is_left() -> void:
	await _open_view()
	assert_int(_keys.shoot()).is_greater(0)
	_harness.pump()
	var sent := _harness.sent_named(Intents.INTERACT)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["station"] as int).is_equal(CAMERA)
	assert_int(sent[0].fields["item"] as int).is_equal(-1)
	for shot in FixturePhotoModes.FRAMES:
		_fold(ShotTakenEvent.new(CAMERA, FILM, shot))
	assert_int(PhotoUse.frames_left(_model, _mode, CAMERA)).is_equal(0)
	assert_int(_keys.shoot()).is_equal(-1)
	_harness.pump()
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(1)


func test_no_shot_without_the_view() -> void:
	_load()
	await _look_at_camera()
	assert_int(_keys.shoot()).is_equal(-1)
	# E's interact() on a loaded camera sends nothing either: it shoots only from the view.
	assert_int(_keys.interact()).is_equal(-1)
	_harness.pump()
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(0)


func test_e_in_the_view_closes_it_and_gives_the_eye_back() -> void:
	await _open_view()
	assert_int(_keys.press_interact()).is_equal(-1)
	assert_bool(_keys.viewing()).is_false()
	assert_int(_keys.held_camera()).is_equal(-1)
	assert_bool(_player.get_camera().current).is_true()
	assert_bool(_player.held).is_false()
	assert_bool(_player.hand_view().visible).is_true()
	assert_bool(_finder.mask.visible).is_false()
	assert_object(_finder.live_camera()).is_null()
	_harness.pump()
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(0)
	assert_int(_harness.sent_named(Intents.PICK_UP).size()).is_equal(0)


func test_the_film_taken_out_by_another_closes_the_view() -> void:
	await _open_view()
	_fold(ItemPickedUpEvent.new(_model.own_peer + 1, FILM))
	await _frames(2)
	assert_bool(_keys.viewing()).is_false()


func test_the_film_vanishing_closes_the_view() -> void:
	await _open_view()
	_fold(ItemVanishedEvent.new(FILM))
	await _frames(2)
	assert_bool(_keys.viewing()).is_false()


func test_a_hit_closes_the_view() -> void:
	await _open_view()
	var hit := DamagedEvent.new(_model.own_peer, 1, 2)
	_fold(hit)
	_finder.on_event(hit.event_name(), hit.to_dict())
	assert_bool(_keys.viewing()).is_false()


func test_a_knockdown_closes_the_view() -> void:
	await _open_view()
	var down := KnockedDownEvent.new(_model.own_peer, Vector3.ZERO)
	_fold(down)
	_finder.on_event(down.event_name(), down.to_dict())
	assert_bool(_keys.viewing()).is_false()


func test_a_death_closes_the_view_by_the_next_physics_step() -> void:
	await _open_view()
	_model.lives[_model.own_peer] = ClientModel.Life.DEAD
	await _frames(2)
	assert_bool(_keys.viewing()).is_false()


func test_leaving_the_cylinder_closes_the_view() -> void:
	await _open_view()
	_player.global_position = Vector3(0, 0, 2)
	await _frames(2)
	assert_bool(_keys.viewing()).is_false()


func test_a_box_cutting_the_line_to_the_floor_point_closes_the_view() -> void:
	await _open_view()
	var eye := _player.get_camera().global_position
	var floor_point := Items.lifted(CAMERA_AT)
	_world.call(&"add_box", eye.lerp(floor_point, 0.8), Vector3(0.3, 0.05, 0.05))
	await _frames(2)
	assert_bool(_keys.viewing()).is_false()


func test_the_keys_no_longer_listening_close_the_view() -> void:
	await _open_view()
	_keys.listening = false
	await _frames(2)
	assert_bool(_keys.viewing()).is_false()
	assert_bool(_player.held).is_false()


func test_no_view_from_outside_the_cylinder() -> void:
	_load()
	_player.global_position = Vector3(0, 0, 1.5)
	await _look_at_camera()
	assert_int(_keys.station_target()).is_equal(-1)
	_keys.press_interact()
	assert_int(_keys.release_interact()).is_equal(-1)
	assert_bool(_keys.viewing()).is_false()
	assert_bool(_finder.enter(CAMERA)).is_false()
	assert_bool(_finder.active()).is_false()


func test_no_view_through_a_wall() -> void:
	_load()
	# A pane between the eye and the camera's lifted floor point, clear of the own capsule.
	var eye := Vector3(0, FixtureModes.player_rules().eye_height_m, 0)
	_world.call(&"add_box", eye.lerp(Items.lifted(CAMERA_AT), 0.8), Vector3(1.0, 0.2, 0.02))
	await _look_at_camera()
	assert_int(_keys.station_target()).is_equal(-1)
	_keys.press_interact()
	assert_int(_keys.release_interact()).is_equal(-1)
	assert_bool(_keys.viewing()).is_false()
	# Opened past the target anyway, it closes in the next physics step.
	assert_bool(_finder.enter(CAMERA)).is_true()
	await _frames(2)
	assert_bool(_finder.active()).is_false()
	_harness.pump()
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(0)


## The own film loaded into the camera (the host's FilmLoaded; no ItemPlaced follows).
func _load() -> void:
	_fold(FilmLoadedEvent.new(CAMERA, FILM))


## The film loaded, the crosshair on the camera, a tap of E: the view is up.
func _open_view() -> void:
	_load()
	await _look_at_camera()
	_keys.press_interact()
	_keys.release_interact()
	assert_bool(_keys.viewing()).is_true()


func _fold(event: MatchEvent) -> void:
	_model.fold(event.event_name(), event.to_dict())


## Turns the player's camera at the camera station's aim point, then lets two physics frames cast.
func _look_at_camera() -> void:
	await get_tree().physics_frame
	var eye := _player.get_camera().global_position
	var to := TargetChoice.aim_point(_model.stations[CAMERA]) - eye
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	_player.look(0.0, pitch - _player.get_camera().get_parent_node_3d().rotation.x)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _process_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
