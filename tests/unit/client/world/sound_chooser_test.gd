extends GdUnitTestSuite
## The sound chooser (client/world/sound_chooser.gd; ARCHITECTURE §4.7, a hearing range; the M4
## ADR's §3 item 10, E33 (a)): Swung, ItemPickedUp, ItemPlaced and ItemThrown (#645) play at their
## places only within the hearing range of the listener's camera, and nothing at all for an event
## from farther away; every other event is silent. And WorldSounds sets each player's max_distance
## to the same range.

const RANGE := SoundChooser.HEARING_RANGE_M

var _model: ClientModel
var _positions: Dictionary[int, Vector3] = {}


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_positions = {2: Vector3(3, 0, 4)}
	_model.fold(&"ItemSpawned", {"item": 5, "kind": &"knife", "position": Vector3(0, 0, 10)})


func test_a_swing_plays_at_the_swinger_within_the_range() -> void:
	var sound := _choose(&"Swung", {"peer": 2, "facing": Vector3.FORWARD}, Vector3.ZERO)
	assert_object(sound).is_not_null()
	assert_str(String(sound.id)).is_equal(String(SoundChooser.SWING))
	assert_that(sound.position).is_equal(Vector3(3, 0, 4))
	# The occlusion ray aims at about the swinger's chest, not its feet (M5-7).
	assert_that(sound.aim).is_equal(Vector3(3, SoundChooser.SWING_AIM_M, 4))
	# A swinger the client draws nowhere makes no sound.
	assert_object(_choose(&"Swung", {"peer": 9, "facing": Vector3.FORWARD}, Vector3.ZERO)).is_null()


func test_a_pickup_plays_where_the_item_lay() -> void:
	_model.fold(&"ItemPickedUp", {"peer": 2, "item": 5})
	var sound := _choose(&"ItemPickedUp", {"peer": 2, "item": 5}, Vector3(0, 0, 4))
	assert_str(String(sound.id)).is_equal(String(SoundChooser.PICK_UP))
	assert_that(sound.position).is_equal(Vector3(0, 0, 10))
	assert_that(sound.aim).is_equal(Vector3(0, SoundChooser.ITEM_AIM_M, 10))
	assert_object(_choose(&"ItemPickedUp", {"peer": 2, "item": 77}, Vector3.ZERO)).is_null()


func test_a_put_down_plays_at_its_position() -> void:
	var at := Vector3(1, 0, 1)
	var fields := {"item": 5, "position": at, "cause": &"put_down"}
	var sound := _choose(&"ItemPlaced", fields, Vector3.ZERO)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.PUT_DOWN))
	assert_that(sound.position).is_equal(at)
	assert_that(sound.aim).is_equal(at + Vector3.UP * SoundChooser.ITEM_AIM_M)


func test_nothing_plays_beyond_the_hearing_range() -> void:
	# The plant E33 guards against: a package put down in a far storeroom.
	var far := Vector3(0, 0, RANGE + 0.5)
	var near := Vector3(0, 0, RANGE - 0.5)
	var put := {"item": 5, "position": far, "cause": &"put_down"}
	assert_object(_choose(&"ItemPlaced", put, Vector3.ZERO)).is_null()
	put["position"] = near
	assert_object(_choose(&"ItemPlaced", put, Vector3.ZERO)).is_not_null()
	# The listener counts, wherever its camera is (the living, the downed, the dead's spectating).
	put["position"] = far
	assert_object(_choose(&"ItemPlaced", put, Vector3(0, 0, 2))).is_not_null()
	_positions[2] = Vector3(RANGE, 0, 1)
	assert_object(_choose(&"Swung", {"peer": 2, "facing": Vector3.FORWARD}, Vector3.ZERO)).is_null()
	assert_bool(SoundChooser.audible(Vector3(RANGE, 0, 0), Vector3.ZERO)).is_true()
	assert_bool(SoundChooser.audible(Vector3(RANGE + 0.01, 0, 0), Vector3.ZERO)).is_false()


func test_a_launch_plays_at_its_origin_and_none_beyond_the_hearing_range() -> void:
	# The plant E33 guards against for throws (#645): ItemThrown reaches everyone with its origin,
	# so an uncut launch would tell every client where a package was just thrown to hide it.
	var launch := {
		"item": 5,
		"peer": 2,
		"origin": Vector3(0, 1.6, 3),
		"velocity": Vector3(0, 4, -8),
		"gravity": Vector3(0, -9.8, 0),
		"tick": 30,
	}
	var sound := _choose(&"ItemThrown", launch, Vector3.ZERO)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.THROW))
	assert_that(sound.position).is_equal(Vector3(0, 1.6, 3))
	assert_that(sound.aim).is_equal(Vector3(0, 1.6, 3))
	launch["origin"] = Vector3(0, 0, RANGE + 0.5)
	assert_object(_choose(&"ItemThrown", launch, Vector3.ZERO)).is_null()
	launch["origin"] = Vector3(0, 0, RANGE)
	assert_object(_choose(&"ItemThrown", launch, Vector3.ZERO)).is_not_null()


func test_other_events_are_silent() -> void:
	for event_name: StringName in [&"Damaged", &"PackageDelivered", &"KnockedDown", &"Swapped"]:
		assert_object(_choose(event_name, {"peer": 2}, Vector3.ZERO)).is_null()


func test_world_sounds_plays_with_the_range_as_max_distance() -> void:
	var sounds: WorldSounds = auto_free(WorldSounds.new())
	add_child(sounds)
	sounds.model = _model
	sounds.listener = func() -> Variant: return Vector3.ZERO
	sounds.on_event(&"ItemPlaced", {"item": 5, "position": Vector3(0, 0, 2), "cause": &"put_down"})
	sounds.on_event(&"ItemPlaced", {"item": 5, "position": Vector3(0, 0, 40), "cause": &"put_down"})
	assert_int(sounds.played()).is_equal(1)
	var players := sounds.find_children("*", "AudioStreamPlayer3D", false, false)
	assert_int(players.size()).is_equal(1)
	var played := players[0] as AudioStreamPlayer3D
	assert_float(played.max_distance).is_equal(RANGE)
	assert_that(played.position).is_equal(Vector3(0, 0, 2))
	assert_object(played.stream).is_not_null()
	# No listener (no camera): nothing plays.
	sounds.listener = func() -> Variant: return null
	sounds.on_event(&"ItemPlaced", {"item": 5, "position": Vector3.ZERO, "cause": &"put_down"})
	assert_int(sounds.played()).is_equal(1)


func test_the_placeholder_blips_are_short_sound() -> void:
	for id: StringName in [
		SoundChooser.SWING, SoundChooser.PICK_UP, SoundChooser.PUT_DOWN, SoundChooser.THROW
	]:
		var blip := WorldSounds.blip(id)
		assert_float(blip.get_length()).is_between(0.05, 0.5)
		assert_int(blip.data.size()).is_greater(1000)


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	return SoundChooser.choose(event_name, fields, _model, _position_of, listener)


func _position_of(peer: int) -> Variant:
	return _positions.get(peer)
