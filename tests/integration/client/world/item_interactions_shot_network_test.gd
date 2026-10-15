extends GdUnitTestSuite
## The shot from the viewfinder as a player takes it (#1114; photo P7, #786, ARCHITECTURE §4.7.56;
## the photo ADR's §2): the left mouse button, through Input.parse_input_event as a real click
## reaches the action states, read by ItemInteractions' own _process, against a HostSession over a
## LoopbackHub on FixtureWirePhoto (the photo wire test's mode and layout, no Game). The shooter's
## client carries the dealt film to the camera and loads it by intents; then its real
## PlayerController stands at the camera on a floor of its own and its PhotoViewfinder opens there.
## With the mouse captured the click sends Interact(camera, item -1) and the host's ShotTaken comes
## back with the counter one frame down; the click that captures the mouse takes no shot.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const World := preload("res://tests/integration/client/player/player_test_world.gd")

## The host's own client stands on the photo spot, the shooter at the camera.
const SPOTS: Array[Vector3] = [FixtureWirePhoto.SUBJECT_SPOT, FixtureWirePhoto.SHOOT_SPOT]
## How long the host gets to answer an intent (the photo wire test's).
const AFTER_USE_S := 0.4

var _h: Harness
var _world: Node3D
var _keys: ItemInteractions
var _finder: PhotoViewfinder
var _shooter: ClientSession
var _camera := -1
var _captured := true


func before_test() -> void:
	_captured = true
	_h = Harness.new(FixtureWirePhoto.mode(), true, null, FixtureWirePhoto.layouts(SPOTS))
	assert_bool(_h.started).is_true()
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(0.5)
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 800)).is_true()
	_h.pump_seconds(0.5)
	_shooter = _h.clients[1]
	# The ids the host dealt, as the test reads them; the client below reads only its own model.
	var game := _h.session.game
	_camera = FixturePhotoModes.state_of(game).camera
	var dealt := FixturePhotoModes.dealt_film(game)
	_shooter.send_intent(Intents.PICK_UP, {"item": dealt.id})
	_h.pump_seconds(AFTER_USE_S)
	_shooter.send_intent(Intents.INTERACT, {"station": _camera, "item": -1})
	_h.pump_seconds(AFTER_USE_S)
	assert_array(_shooter.view.events_named(&"FilmLoaded")).has_size(1)
	_world = World.new()
	add_child(_world)
	var player := _world.call(&"add_player", FixtureWirePhoto.SHOOT_SPOT) as PlayerController
	_keys = ItemInteractions.new()
	_keys.setup(_shooter, _h.mode)
	_keys.player = player
	_keys.mouse_captured = func() -> bool: return _captured
	_finder = PhotoViewfinder.new()
	_finder.model = _shooter.model
	_finder.mode = _h.mode
	_finder.player = player
	_keys.viewfinder = _finder
	_world.add_child(_keys)
	_world.add_child(_finder)


func after_test() -> void:
	_click(false)
	if _world != null:
		_world.free()
		_world = null
	if _h != null:
		_h.close()
		_h = null


func test_the_left_button_in_the_view_takes_the_shot_on_the_host() -> void:
	var frames := PhotoUse.frames_left(_shooter.model, _h.mode, _camera)
	assert_int(frames).is_greater(0)
	await _open_view()
	await _shoot()
	var shots := _shooter.view.events_named(&"ShotTaken")
	assert_array(shots).has_size(1)
	if not shots.is_empty():
		assert_int(shots[0].fields["station"] as int).is_equal(_camera)
	assert_array(_shooter.view.events_named(&"Rejected")).is_empty()
	assert_int(PhotoUse.frames_left(_shooter.model, _h.mode, _camera)).is_equal(frames - 1)


func test_a_click_with_the_mouse_free_takes_no_shot() -> void:
	_captured = false
	await _open_view()
	await _shoot()
	assert_array(_shooter.view.events_named(&"ShotTaken")).is_empty()
	# Captured from then on, the next click shoots.
	_captured = true
	await _process_frames(2)
	await _shoot()
	assert_array(_shooter.view.events_named(&"ShotTaken")).has_size(1)


## The real order: the controller captures the mouse on the click itself, before the item keys'
## _process of that frame, so that click reads as captured now but was free a frame ago.
func test_the_click_that_captures_the_mouse_takes_no_shot() -> void:
	_captured = false
	await _open_view()
	_click(true)
	_captured = true
	await _process_frames(2)
	_click(false)
	await _process_frames(1)
	_h.pump_seconds(AFTER_USE_S)
	assert_array(_shooter.view.events_named(&"ShotTaken")).is_empty()
	assert_array(_shooter.view.events_named(&"Rejected")).is_empty()
	# The next click, the mouse already captured, shoots.
	await _shoot()
	assert_array(_shooter.view.events_named(&"ShotTaken")).has_size(1)


## Lets the keys read the pointer once, then opens the view at the loaded camera.
func _open_view() -> void:
	await _process_frames(2)
	assert_bool(_finder.enter(_camera)).is_true()
	assert_bool(_keys.viewing()).is_true()


## The left button down for two frames, then up; the host answers.
func _shoot() -> void:
	_click(true)
	await _process_frames(2)
	_click(false)
	await _process_frames(1)
	_h.pump_seconds(AFTER_USE_S)


## The left mouse button pressed or released, as a real click reaches the action states.
func _click(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _process_frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame
