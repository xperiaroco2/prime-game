extends GdUnitTestSuite
## E on a Generator's station against a fixture world (ARCHITECTURE §4.7.53, #801): the real
## PlayerController on a floor, looking through its own camera at a station's use spot or its
## device (a box the level's ray hits, named by `station_of_body` as StationViews does). E sends
## Interact(station, item -1); the host decides everything. No target once the charge is done, none
## past a box or a downed player in front, and the target is the same for a switch on and off.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
## The station ids this suite places.
const SWITCH := 4
const GENERATOR := 3
## A switch's floor point 0.3 m ahead of the feet: inside its 1 m cylinder less the margin.
const SPOT := Vector3(0, 0, -0.3)

var _world: Node3D
var _player: PlayerController
var _keys: ItemInteractions
var _harness: Harness
var _model: ClientModel
## The collider StationViews would name SWITCH by; null for none.
var _device: Object = null


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_model = _harness.session.model
	_keys = ItemInteractions.new()
	_keys.reads_device_input = false
	_keys.setup(_harness.session, FixtureGeneratorModes.basic())
	_keys.player = _player
	_keys.station_of_body = func(body: Object) -> int: return SWITCH if body == _device else -1
	_world.add_child(_keys)
	_place(GENERATOR, &"generator", Vector3(0, 0, 20))
	_place(SWITCH, &"switch", SPOT)
	_fold(ZoneProgressEvent.new(GENERATOR, 0, FixtureGeneratorModes.NEEDED, false, 0))


func after_test() -> void:
	_world.free()
	_harness.close()


func test_e_at_a_switch_use_spot_sends_interact_with_no_item() -> void:
	await _look_at(TargetChoice.aim_point(_model.stations[SWITCH]))
	assert_int(_keys.station_target()).is_equal(SWITCH)
	assert_int(_keys.target()).is_equal(-1)
	assert_int(_keys.interact()).is_greater(0)
	_harness.pump()
	var sent := _harness.sent_named(Intents.INTERACT)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["station"] as int).is_equal(SWITCH)
	assert_int(sent[0].fields["item"] as int).is_equal(-1)
	assert_int(_harness.sent_named(Intents.PICK_UP).size()).is_equal(0)


func test_the_hint_names_the_station_and_not_its_state() -> void:
	await _look_at(TargetChoice.aim_point(_model.stations[SWITCH]))
	var local := HudText.Local.new()
	local.aim_station = _keys.station_target()
	var off := HudText.of(_model, _keys.mode, 0.0, local).aim
	assert_str(off).is_equal("switch")
	_fold(SwitchChangedEvent.new(SWITCH, true))
	await _frames(2)
	assert_int(_keys.station_target()).is_equal(SWITCH)
	assert_str(HudText.of(_model, _keys.mode, 0.0, local).aim).is_equal(off)


func test_a_charged_generator_offers_no_station() -> void:
	_fold(
		ZoneProgressEvent.new(
			GENERATOR, FixtureGeneratorModes.NEEDED, FixtureGeneratorModes.NEEDED, false, 5
		)
	)
	await _look_at(TargetChoice.aim_point(_model.stations[SWITCH]))
	assert_int(_keys.station_target()).is_equal(-1)
	assert_int(_keys.interact()).is_equal(-1)


func test_the_device_names_its_station_only_through_station_of_body() -> void:
	# A device box at eye height ahead, the use spot's sphere far below the ray.
	_world.call(&"add_box", Vector3(0, 1.6, -1.2), Vector3(0.4, 0.4, 0.2))
	await _look_at(Vector3(0, 1.6, -1.2))
	assert_int(_keys.station_target()).is_equal(-1)
	_device = _last_box()
	await _frames(2)
	assert_int(_keys.station_target()).is_equal(SWITCH)


func test_a_box_before_the_use_spot_offers_nothing() -> void:
	_place(SWITCH, &"switch", Vector3(0, 0, -0.6))
	# A shelf over the use spot, met before the ray enters its sphere.
	_world.call(&"add_box", Vector3(0, 0.78, -0.65), Vector3(1.0, 0.02, 0.5))
	await _look_at(TargetChoice.aim_point(_model.stations[SWITCH]))
	assert_int(_keys.station_target()).is_equal(-1)


func test_a_box_hiding_the_floor_point_offers_nothing() -> void:
	# The host's StationInSight: the line to the lifted floor point, below the aimed sphere.
	_place(SWITCH, &"switch", Vector3(0, 0, -0.6))
	await _look_at(TargetChoice.aim_point(_model.stations[SWITCH]))
	assert_int(_keys.station_target()).is_equal(SWITCH)
	_world.call(&"add_box", Vector3(0, 0.2, -0.5), Vector3(1.0, 0.2, 0.1))
	await _frames(2)
	assert_int(_keys.station_target()).is_equal(-1)


func test_a_downed_player_in_front_hides_the_station() -> void:
	_place(SWITCH, &"switch", Vector3(0, 0, -0.6))
	var downed := _world.call(&"add_remote", Vector3(0, 0, -0.5)) as RemotePlayerBody
	downed.set_living(false)
	await _look_at(TargetChoice.aim_point(_model.stations[SWITCH]))
	assert_int(_keys.station_target()).is_equal(-1)
	downed.position = Vector3(3, 0, 0)
	await _frames(2)
	assert_int(_keys.station_target()).is_equal(SWITCH)


func _place(id: int, kind: StringName, at: Vector3) -> void:
	_fold(StationPlacedEvent.new(id, kind, Color.WHITE, at))


func _fold(event: MatchEvent) -> void:
	_model.fold(event.event_name(), event.to_dict())


## The collider add_box made last.
func _last_box() -> Object:
	return _world.get_child(_world.get_child_count() - 1)


## Turns the player's camera at `point`, then lets two physics frames cast.
func _look_at(point: Vector3) -> void:
	await get_tree().physics_frame
	var eye := _player.get_camera().global_position
	var to := point - eye
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	_player.look(0.0, pitch - _player.get_camera().get_parent_node_3d().rotation.x)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
