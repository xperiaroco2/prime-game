extends GdUnitTestSuite
## ItemWorld's photo booth (#1397, ARCHITECTURE §4.7.62) with a real local player, a ClientSession
## harness decoding the host's BoothStep events off the loopback wire and the booth fixture mode as
## the client's own mode copy: STARTED lights the lamp, each FLASH plays the shutter at it and the
## own player in the frame gets the white; PRINTED binds each strip to the session's three records,
## plays the print at the slot, slides the own strip into the hand and a prop out of the slot; the
## session's end forgets it all.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")

const BOOTH := 5
const BOOTH_AT := Vector3(0, 0, -3)
const STRIP_OWN := 40
const STRIP_OTHER := 41
const OTHER := 7

var _world: Node3D
var _player: PlayerController
var _harness: Harness
var _items: ItemWorld
var _own := 0


func before_test() -> void:
	AudioBuses.ensure()
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_own = _harness.session.model.own_peer
	_items = ItemWorld.new()
	_world.add_child(_items)
	var avatars := AvatarViews.new()
	_world.add_child(avatars)
	_items.setup(_harness.session, FixtureBooth.mode(), avatars)
	_items.set_player(_player)
	_items.interactions.reads_device_input = false
	_items.sounds.listener = func() -> Variant: return _player.global_position + Vector3.UP
	_send(StationPlacedEvent.new(BOOTH, &"booth", Color.WHITE, BOOTH_AT))


func after_test() -> void:
	_world.free()
	_harness.close()


func test_a_session_off_the_wire_flashes_prints_and_binds_three_frames() -> void:
	await _physics(2)
	var heard := _items.sounds.played()
	var started := BoothStepEvent.new(BOOTH, 1, BoothStepEvent.STARTED)
	started.presser = _own
	started.frames = 3
	started.countdown = 60
	started.gap = 40
	_send(started)
	assert_object(_items.booth_views.lamp_of(BOOTH)).is_not_null()
	var lamp := BOOTH_AT + Vector3.UP * BoothViews.LAMP_LIFT_M
	for frame: int in 3:
		var flash := BoothStepEvent.new(BOOTH, 1, BoothStepEvent.FLASH)
		flash.frame = frame
		flash.record = [_row(_own), _row(OTHER)]
		_send(flash)
		assert_that(_last_sound().global_position).is_equal(lamp)
	assert_float(_items.booth_views.overlay_alpha()).is_greater(0.0)
	assert_int(_items.sounds.played()).is_equal(heard + 3)
	_send(ItemSpawnedEvent.new(STRIP_OWN, StripLooks.STRIP, BOOTH_AT))
	_send(ItemPickedUpEvent.new(_own, STRIP_OWN))
	_send(ItemSpawnedEvent.new(STRIP_OTHER, StripLooks.STRIP, BOOTH_AT))
	_send(ItemPickedUpEvent.new(OTHER, STRIP_OTHER))
	var played := _items.sounds.played()
	var printed := BoothStepEvent.new(BOOTH, 1, BoothStepEvent.PRINTED)
	printed.items = PackedInt32Array([STRIP_OWN, STRIP_OTHER])
	_send(printed)
	assert_int(_items.sounds.played()).is_equal(played + 1)
	assert_that(_last_sound().global_position).is_equal(
		BOOTH_AT + Vector3.UP * BoothViews.SLOT_LIFT_M
	)
	var session := _items.booth.session_of(STRIP_OWN)
	assert_object(session).is_not_null()
	assert_object(_items.booth.session_of(STRIP_OTHER)).is_same(session)
	assert_int(session.frame_count()).is_equal(3)
	for frame: int in 3:
		var peers: Array[int] = []
		for row: Dictionary in session.record_of(frame):
			peers.append(row["peer"] as int)
		assert_array(peers).contains_exactly([_own, OTHER])
	assert_int(_items.booth_views.prints().size()).is_equal(1)
	await _physics(2)
	var hand := _player.hand_view()
	assert_str(String(hand.shown_kind())).is_equal(String(StripLooks.STRIP))
	assert_bool(hand.is_sliding()).is_true()


func test_the_session_s_end_forgets_the_booth() -> void:
	var started := BoothStepEvent.new(BOOTH, 1, BoothStepEvent.STARTED)
	started.frames = 1
	started.countdown = 60
	_send(started)
	_items.reset()
	assert_object(_items.booth.running_at(BOOTH)).is_null()
	assert_object(_items.booth_views.lamp_of(BOOTH)).is_null()


func _row(peer: int) -> Dictionary:
	return {
		"peer": peer,
		"colour": 0,
		"position": BOOTH_AT,
		"facing": Vector3.FORWARD,
		"crouched": false,
		"sneaking": false,
		"posed": false,
		"limp": false,
	}


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
