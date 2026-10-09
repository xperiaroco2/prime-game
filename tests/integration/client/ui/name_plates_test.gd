extends GdUnitTestSuite
## NamePlates (#257, ARCHITECTURE §4.7.29) over real physics steps (Jolt, headless) in a
## SubViewport of its own world: AvatarViews draws five other players from snapshots, the camera
## stands at the own eye looking along -Z. A plate shows only for a player in line of sight within
## 10 m and in front of the camera, centred on the projection of the point 0.35 m over its head;
## none behind a wall, beyond 10 m, behind the camera, for a body SightHider hid or one watched
## from its eyes, or while the layer is hidden. The teammate mark shows only on a dissident's
## client and only for a teammate; an engineer's client never draws it, and a plate holds the name
## and nothing else.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
const OWN := 1
## In front, 5 m away.
const NEAR := 2
## In front, about 6 m away: the own dissident's teammate in the dissident's tests.
const MATE := 3
## 3 m behind the camera.
const BEHIND := 4
## 7 m away, past the end of the wall at x = 3.
const WALLED := 5
## 12 m away in the open, in front.
const FAR := 6
const SPOTS: Dictionary[int, Vector3] = {
	NEAR: Vector3(-1.0, 0.0, -5.0),
	MATE: Vector3(1.5, 0.0, -6.0),
	BEHIND: Vector3(0.0, 0.0, 3.0),
	WALLED: Vector3(6.0, 0.0, -4.0),
	FAR: Vector3(0.0, 0.0, -12.0),
}
const NAMES: Dictionary[int, String] = {
	OWN: "Me", NEAR: "Taras", MATE: "Olena", BEHIND: "Behind", WALLED: "Walled", FAR: "Far"
}
const TICK_USEC := 50000

var _viewport: SubViewport
var _world: PlayerTestWorld
var _model: ClientModel
var _avatars: AvatarViews
var _camera: Camera3D
var _plates: NamePlates
var _now := 1000000


func before_test() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(1920, 1080)
	add_child(_viewport)
	_world = PlayerTestWorld.new()
	_viewport.add_child(_world)
	# A wall at x = 3 from z = -8 to 0, 4 m high: the ray to WALLED's eye crosses it at z = -2.
	_world.add_box(Vector3(3.0, 2.0, -4.0), Vector3(0.2, 4.0, 8.0))
	_model = _lobby_model()
	_avatars = AvatarViews.new()
	_avatars.model = _model
	_avatars.buffer = SnapshotBuffer.new()
	_avatars.rules = _world.rules
	_avatars.clock = func() -> int: return _now
	_world.add_child(_avatars)
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.position = Vector3(0.0, _world.rules.eye_height_m, 0.0)
	_camera.make_current()
	_plates = NamePlates.new()
	_plates.avatars = _avatars
	_viewport.add_child(_plates)


func after_test() -> void:
	_viewport.free()


func test_a_player_in_sight_within_range_gets_its_name_centred_over_its_head() -> void:
	await _settle()
	for peer: int in [NEAR, MATE]:
		assert_bool(_plates.shows(peer)).override_failure_message(NAMES[peer]).is_true()
		var plate := _plates.plate_of(peer)
		assert_str(plate.name_label.text).is_equal(NAMES[peer])
		var head := _avatars.body_of(peer).head().global_position
		assert_vector(NamePlates.plate_point(_avatars.body_of(peer))).is_equal_approx(
			head + Vector3.UP * 0.35, Vector3.ONE * 1e-4
		)
		var over := _camera.unproject_position(head + Vector3.UP * 0.35)
		assert_vector(plate.position + plate.size * 0.5).is_equal_approx(over, Vector2.ONE * 0.5)
	assert_int(_plates.shown_count()).is_equal(2)
	assert_float(NamePlates.RANGE_M).is_equal(10.0)


func test_no_plate_behind_a_wall_beyond_range_or_behind_the_camera() -> void:
	await _settle()
	# In range and in front: only the wall keeps WALLED's plate away.
	var walled := _avatars.body_of(WALLED)
	assert_bool(NamePlates.in_view(_camera, walled)).is_true()
	for peer: int in [WALLED, FAR, BEHIND]:
		assert_bool(_plates.shows(peer)).override_failure_message(NAMES[peer]).is_false()
	# The wall gone, the same player's plate shows.
	for child: Node in _world.get_children():
		if child is StaticBody3D and (child as StaticBody3D).position.x == 3.0:
			child.free()
	await _settle()
	assert_bool(_plates.shows(WALLED)).is_true()
	assert_bool(_plates.shows(FAR)).is_false()
	assert_bool(_plates.shows(BEHIND)).is_false()


func test_a_body_out_of_the_eyes_sight_or_watched_from_its_eyes_gets_no_plate() -> void:
	await _settle()
	assert_bool(_plates.shows(NEAR)).is_true()
	# SightHider's verdict while the downed camera is in use: the body is not drawn.
	_avatars.body_of(NEAR).visible = false
	_avatars.body_of(MATE).set_watched(true)
	await _settle()
	assert_bool(_plates.shows(NEAR)).is_false()
	assert_bool(_plates.shows(MATE)).is_false()
	_avatars.body_of(NEAR).visible = true
	_avatars.body_of(MATE).set_watched(false)
	await _settle()
	assert_bool(_plates.shows(NEAR)).is_true()
	assert_bool(_plates.shows(MATE)).is_true()


func test_the_downed_cameras_plate_also_needs_the_bodys_eye_to_see_the_player() -> void:
	# The camera at the origin (the arm, 2 m back) sees NEAR over the end of the wall; the body's eye
	# behind the wall at x = 3 does not (the M4 ADR's §3 item 3).
	var hider: SightHider = auto_free(SightHider.new())
	_plates.hider = hider
	await _settle()
	assert_bool(_plates.shows(NEAR)).is_true()
	hider.watch_from(Vector3(5.0, _world.rules.eye_height_m, -3.0))
	await _settle()
	assert_bool(_plates.shows(NEAR)).is_false()
	assert_bool(_plates.shows(MATE)).is_false()
	hider.watch_from(Vector3(0.0, _world.rules.eye_height_m, 1.0))
	await _settle()
	assert_bool(_plates.shows(NEAR)).is_true()
	hider.stop()
	hider.watch_from(Vector3(5.0, _world.rules.eye_height_m, -3.0))
	hider.stop()
	await _settle()
	assert_bool(_plates.shows(NEAR)).is_true()


func test_the_mark_shows_on_a_dissidents_client_for_a_teammate_only() -> void:
	_model.fold(&"RoleAssigned", {"role": &"dissident"})
	_model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([OWN, MATE])})
	await _settle()
	assert_bool(_plates.plate_of(MATE).is_marked()).is_true()
	assert_bool(_plates.plate_of(NEAR).is_marked()).is_false()


func test_an_engineers_client_never_draws_the_mark() -> void:
	_model.fold(&"RoleAssigned", {"role": &"engineer"})
	await _settle()
	assert_int(_plates.shown_count()).is_equal(2)
	for peer: int in [NEAR, MATE]:
		assert_bool(_plates.plate_of(peer).is_marked()).is_false()
		assert_bool(_plates.plate_of(peer).mark.visible).is_false()


func test_a_plate_holds_the_name_and_nothing_else() -> void:
	_model.fold(&"RoleAssigned", {"role": &"dissident"})
	_model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([OWN, MATE])})
	_model.fold(&"KnockedDown", {"peer": NEAR, "by": OWN})
	await _settle()
	for peer: int in [NEAR, MATE]:
		var texts := PackedStringArray()
		for label: Node in _plates.plate_of(peer).find_children("*", "Label", true, false):
			texts.append((label as Label).text)
		assert_array(Array(texts)).is_equal([NAMES[peer]])
		var name_label := _plates.plate_of(peer).name_label
		assert_int(name_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)


func test_a_downed_players_plate_sits_over_its_lying_body() -> void:
	_model.fold(&"KnockedDown", {"peer": NEAR, "by": OWN})
	await _settle()
	var body := _avatars.body_of(NEAR)
	assert_bool(body.is_downed()).is_true()
	assert_bool(_plates.shows(NEAR)).is_true()
	var top := body.sight_point() + Vector3.UP * (_world.rules.capsule_radius_m + 0.35)
	assert_vector(NamePlates.plate_point(body)).is_equal_approx(top, Vector3.ONE * 1e-4)


func test_a_hidden_layer_or_a_player_who_left_shows_no_plate() -> void:
	await _settle()
	assert_int(_plates.shown_count()).is_equal(2)
	_model.fold(&"PlayerLeft", {"peer": NEAR})
	await _settle()
	assert_object(_plates.plate_of(NEAR)).is_null()
	assert_bool(_plates.shows(MATE)).is_true()
	_plates.visible = false
	await _settle()
	assert_int(_plates.shown_count()).is_equal(0)


## Lobby of the own player and the five others, each placed by snapshots at its spot.
func _lobby_model() -> ClientModel:
	var model := ClientModel.new(FixtureBaseMode.mode())
	var welcome := WelcomeEvent.new(OWN, Vector3.ZERO, 1)
	welcome.roster.assign([{"peer": OWN, "name": NAMES[OWN], "ready": false}])
	welcome.settings = FixtureBaseMode.mode().default_settings()
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	for peer: int in SPOTS:
		model.fold(&"PlayerJoined", {"peer": peer, "name": NAMES[peer], "spot": SPOTS[peer]})
	return model


## Snapshots of every other player still in the roster at its spot, then the physics steps that
## place the bodies and cast the rays, and a drawn frame.
func _settle() -> void:
	for i: int in 3:
		var tick := _model.snapshot_tick + 1
		var avatars := {}
		for peer: int in SPOTS:
			if not _model.roster.has(peer):
				continue
			avatars[peer] = {
				"position": SPOTS[peer], "velocity": Vector3.ZERO, "facing": Vector3.FORWARD
			}
		_now += TICK_USEC
		_model.fold_snapshot({"tick": tick, "avatars": avatars})
		_avatars.buffer.add(tick, avatars, _now)
	for i: int in 3:
		await get_tree().physics_frame
	await get_tree().process_frame
	_plates.refresh()
