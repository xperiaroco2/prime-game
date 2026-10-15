extends GdUnitTestSuite
## E on the car repair's stations against a fixture world (#811, the car repair ADR's §8 R7, RE5,
## §2.2, §2.3): the real PlayerController on a floor, its own camera aiming. E on the lift panel
## sends Interact, and E released sends StopRaise once, wherever the crosshair is then; the keys
## falling silent (Esc) send it too; a knockdown sends nothing (the host stopped the hold). A bin
## is a tap. The level's first ray meets the movers layer (the car's Lift names the car), and a
## shelf's body names a bin by the hit point (station_near_hit).

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const CAR := FixtureCarRepairClient.CAR
const PANEL := FixtureCarRepairClient.PANEL
const BIN := FixtureCarRepairClient.FIRST_BIN
const PICTURE := FixtureCarRepairClient.PICTURE
const PART := 30
## A station's floor point 0.3 m ahead of the feet: inside its use cylinder.
const SPOT := Vector3(0, 0, -0.3)
const FAR := Vector3(0, 0, 30)
## A device box at eye height ahead: the use spot's aim sphere is far below the ray.
const DEVICE_AT := Vector3(0, 1.6, -1.2)

var _world: Node3D
var _player: PlayerController
var _keys: ItemInteractions
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
	_mode = FixtureCarRepairModes.basic()
	_keys = ItemInteractions.new()
	_keys.setup(_harness.session, _mode)
	_keys.player = _player
	_world.add_child(_keys)
	_place(CAR, &"car", FAR)
	_place(PANEL, &"lift_panel", FAR + Vector3(4, 0, 0))
	_place(BIN, &"bin_spark_plug", FAR + Vector3(8, 0, 0))
	_place(PICTURE, &"part_picture", FAR + Vector3(12, 0, 0))
	FixtureCarRepairClient.fold(_model, PartNeededEvent.new(PICTURE, &"spark_plug"))


func after_test() -> void:
	Input.action_release(&"interact")
	_world.free()
	_harness.close()


func test_e_on_the_panel_sends_interact_and_its_release_one_stop_raise() -> void:
	_place(PANEL, &"lift_panel", SPOT)
	await _look_at(TargetChoice.aim_point(_model.stations[PANEL]))
	assert_int(_keys.station_target()).is_equal(PANEL)
	await _press()
	var sent := _harness.sent_named(Intents.INTERACT)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["station"] as int).is_equal(PANEL)
	assert_int(_keys.hold_station()).is_equal(PANEL)
	await _idle(3)
	assert_int(_harness.sent_named(Intents.STOP_RAISE).size()).is_equal(0)
	await _release()
	assert_int(_harness.sent_named(Intents.STOP_RAISE).size()).is_equal(1)
	assert_int(_keys.hold_station()).is_equal(-1)
	await _idle(3)
	assert_int(_harness.sent_named(Intents.STOP_RAISE).size()).is_equal(1)


func test_the_release_sends_stop_raise_with_the_crosshair_off_the_panel() -> void:
	_place(PANEL, &"lift_panel", SPOT)
	await _look_at(TargetChoice.aim_point(_model.stations[PANEL]))
	await _press()
	await _look_at(Vector3(0, 30, -1))
	assert_int(_keys.station_target()).is_equal(-1)
	await _release()
	assert_int(_harness.sent_named(Intents.STOP_RAISE).size()).is_equal(1)


func test_the_keys_falling_silent_send_stop_raise_once() -> void:
	_place(PANEL, &"lift_panel", SPOT)
	await _look_at(TargetChoice.aim_point(_model.stations[PANEL]))
	await _press()
	_keys.listening = false
	await _idle(3)
	_harness.pump()
	assert_int(_harness.sent_named(Intents.STOP_RAISE).size()).is_equal(1)
	await _release()
	assert_int(_harness.sent_named(Intents.STOP_RAISE).size()).is_equal(1)


func test_a_knockdown_during_the_hold_sends_nothing() -> void:
	_place(PANEL, &"lift_panel", SPOT)
	await _look_at(TargetChoice.aim_point(_model.stations[PANEL]))
	await _press()
	_model.lives[_model.own_peer] = ClientModel.Life.DOWNED
	await _idle(2)
	await _release()
	assert_int(_harness.sent_named(Intents.STOP_RAISE).size()).is_equal(0)
	assert_int(_keys.hold_station()).is_equal(-1)


func test_a_bin_is_a_tap() -> void:
	_place(BIN, &"bin_spark_plug", SPOT)
	await _look_at(TargetChoice.aim_point(_model.stations[BIN]))
	assert_int(_keys.station_target()).is_equal(BIN)
	await _press()
	await _release()
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(1)
	assert_int(_harness.sent_named(Intents.STOP_RAISE).size()).is_equal(0)
	assert_int(_keys.hold_station()).is_equal(-1)


func test_the_raised_car_s_lift_on_the_movers_layer_names_the_car() -> void:
	_place(CAR, &"car", SPOT)
	FixtureCarRepairClient.hold(_model, PART, &"spark_plug", _model.own_peer)
	_fold(LiftChangedEvent.new(PANEL, true, 0))
	FixtureCarRepairClient.at_tick(_model, 10000)
	var lift := _mover(DEVICE_AT)
	_keys.station_of_hit = func(body: Object, _shape: int) -> int:
		return CAR if body == lift else -1
	await _look_at(DEVICE_AT)
	assert_int(_keys.station_target()).is_equal(CAR)
	await _press()
	var sent := _harness.sent_named(Intents.INTERACT)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["station"] as int).is_equal(CAR)
	assert_int(_keys.hold_station()).is_equal(CAR)


func test_an_item_behind_the_lowered_car_s_hull_is_not_aimed() -> void:
	FixtureCarRepairClient.fold(
		_model, ItemSpawnedEvent.new(PART, &"spark_plug", Vector3(0, 0, -1.6))
	)
	await _look_at(Vector3(0, 0.1, -1.6))
	assert_int(_keys.target()).is_equal(PART)
	_mover(Vector3(0, 0.4, -1.0), Vector3(1.6, 0.8, 0.3))
	await _frames(2)
	assert_int(_keys.target()).is_equal(-1)


func test_a_shelf_hit_names_the_bin_station_near_hit_gives() -> void:
	_place(BIN, &"bin_spark_plug", SPOT)
	_world.call(&"add_box", DEVICE_AT, Vector3(0.4, 0.4, 0.2))
	var shelf := _world.get_child(_world.get_child_count() - 1)
	var asked: Array[Vector3] = []
	_keys.station_near_hit = func(body: Object, point: Vector3) -> int:
		asked.append(point)
		return BIN if body == shelf else -1
	await _look_at(DEVICE_AT)
	assert_int(_keys.station_target()).is_equal(BIN)
	assert_bool(asked.is_empty()).is_false()
	assert_float(asked[asked.size() - 1].distance_to(DEVICE_AT)).is_less(0.3)


func _place(id: int, kind: StringName, at: Vector3) -> void:
	_fold(StationPlacedEvent.new(id, kind, Color.WHITE, at))


func _fold(event: MatchEvent) -> void:
	_model.fold(event.event_name(), event.to_dict())


## A body on the movers layer alone (the car's Lift), a box of `size` at `center`.
func _mover(center: Vector3, size := Vector3(0.4, 0.4, 0.2)) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.collision_layer = PhysicsLayers.MOVERS
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


func _press() -> void:
	Input.action_press(&"interact")
	await _idle(2)
	_harness.pump()


func _release() -> void:
	Input.action_release(&"interact")
	await _idle(2)
	_harness.pump()


func _idle(count: int) -> void:
	for i in count:
		await get_tree().process_frame


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
