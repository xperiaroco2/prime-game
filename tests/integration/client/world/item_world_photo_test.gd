extends GdUnitTestSuite
## ItemWorld's photo flash and sounds (#785, photo P6) with a real local player, a ClientSession
## harness decoding the host's events off the loopback wire and the fixture base mode as the
## client's own mode copy: a ShotTaken lights the flash at the camera's lens (the mode's eye height
## above its marker) and plays the shutter there; PhotoPrinted and PhotoHung play theirs; behind a
## wall the shutter plays muffled (M5-7), beyond the hearing range not at all (the flash still
## lights: a light is seen only where the eye reaches); the session's end ends the flashes.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")

const CAMERA := 3
const BOARD := 7
const PHOTO := 20
const CAMERA_AT := Vector3(0, 0, -4)
const BOARD_AT := Vector3(-2, 0, -4)
const TRAY_AT := Vector3(2, 0.9, -4)
const FAR_CAMERA := 4
const FAR_AT := Vector3(0, 0, -30)

var _world: Node3D
var _player: PlayerController
var _harness: Harness
var _mode: GameMode
var _items: ItemWorld


func before_test() -> void:
	AudioBuses.ensure()
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_mode = FixtureBaseMode.mode()
	_items = ItemWorld.new()
	_world.add_child(_items)
	var avatars := AvatarViews.new()
	_world.add_child(avatars)
	_items.setup(_harness.session, _mode, avatars)
	_items.set_player(_player)
	_items.interactions.reads_device_input = false
	_items.sounds.listener = func() -> Variant: return _player.global_position + Vector3.UP
	_send(StationPlacedEvent.new(CAMERA, &"camera", Color.WHITE, CAMERA_AT))
	_send(StationPlacedEvent.new(BOARD, &"board", Color.WHITE, BOARD_AT))
	_send(StationPlacedEvent.new(FAR_CAMERA, &"camera", Color.WHITE, FAR_AT))
	_send(ItemSpawnedEvent.new(PHOTO, &"photo", TRAY_AT))


func after_test() -> void:
	_world.free()
	_harness.close()


func test_a_shot_off_the_wire_flashes_and_clicks_at_the_lens() -> void:
	await _physics(2)
	var heard := _items.sounds.played()
	_send(ShotTakenEvent.new(CAMERA, 5, 11))
	var lens := CAMERA_AT + Vector3.UP * _mode.player_rules.eye_height_m
	var light := _items.flashes.light_of(11)
	assert_object(light).is_not_null()
	assert_that(light.global_position).is_equal(lens)
	assert_bool(light.shadow_enabled).is_true()
	assert_int(_items.sounds.played()).is_equal(heard + 1)
	var shutter := _last_sound()
	assert_that(shutter.global_position).is_equal(lens)
	assert_float(shutter.max_distance).is_equal(SoundChooser.HEARING_RANGE_M)
	assert_str(String(shutter.bus)).is_equal(String(AudioBuses.EFFECTS))
	# The print and the hang.
	_send(PhotoPrintedEvent.new(PHOTO, 11))
	assert_that(_last_sound().global_position).is_equal(TRAY_AT)
	_send(PhotoHungEvent.new(PHOTO, BOARD, true))
	assert_that(_last_sound().global_position).is_equal(BOARD_AT)
	assert_int(_items.sounds.played()).is_equal(heard + 3)
	# The test caller of P8's release: the flash ends once past its shortest pulse.
	_items.flashes.advance(PhotoFlashes.PULSE_S)
	_items.flashes.release(11)
	assert_int(_items.flashes.lit()).is_equal(0)


func test_the_shutter_behind_a_wall_plays_muffled() -> void:
	_world.call(&"add_box", Vector3(0, 1.5, -2), Vector3(4, 3, 0.2))
	await _physics(2)
	_send(ShotTakenEvent.new(CAMERA, 5, 11))
	var shutter := _last_sound()
	assert_str(String(shutter.bus)).is_equal(String(AudioBuses.EFFECTS_MUFFLED))
	assert_float(shutter.volume_db).is_equal(Muffle.QUIET_DB)
	assert_int(_items.sounds.muffled()).is_equal(1)
	# The flash still lights at the lens: its shadows keep it out of the room on this side.
	assert_bool(_items.flashes.light_of(11).shadow_enabled).is_true()


func test_a_shot_beyond_the_range_plays_nothing() -> void:
	await _physics(2)
	var heard := _items.sounds.played()
	var rays := _items.sounds.rays()
	_send(ShotTakenEvent.new(FAR_CAMERA, 5, 12))
	assert_int(_items.sounds.played()).is_equal(heard)
	assert_int(_items.sounds.rays()).is_equal(rays)
	assert_object(_items.flashes.light_of(12)).is_not_null()


func test_the_session_end_ends_the_flashes() -> void:
	_send(ShotTakenEvent.new(CAMERA, 5, 11))
	assert_int(_items.flashes.lit()).is_equal(1)
	_items.reset()
	assert_int(_items.flashes.lit()).is_equal(0)
	assert_object(_items.flashes.model).is_null()


## Sends `event` over the loopback wire; the session decodes it, folds it and hands it to ItemWorld.
func _send(event: MatchEvent) -> void:
	_harness.send(event)
	_harness.deliver()


## The player WorldSounds started last (it frees itself when it ends).
func _last_sound() -> AudioStreamPlayer3D:
	var sounds := _items.sounds
	return sounds.get_child(sounds.get_child_count() - 1) as AudioStreamPlayer3D


func _physics(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
