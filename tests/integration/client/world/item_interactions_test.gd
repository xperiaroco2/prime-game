extends GdUnitTestSuite
## The crosshair's target and the item keys against a fixture world (ARCHITECTURE §4.7,
## Interactions; M4-8): the real PlayerController on a floor with a crate, looking through its
## own camera. The camera's ray picks the candidate; the hint and E apply only if the base mode's
## InReach of PickUp (2 m) holds from the feet, as the host measures it, less the hint's margin
## (1.7 m, #319): a crate-top item the host would refuse gets no hint, a floor item 1.3 to 1.7 m
## away gets one, one 1.85 m away none, and a wall hides an item behind it.
## The keys send their intents through the ClientSession; the host decides everything. G throws
## (#645) only with a Throw rule in the own mode copy, in a phase that takes it, one at a time,
## right after the last claim's reliable twin.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const MODE := "res://content/modes/base_mode.tres"

var _world: Node3D
var _player: PlayerController
var _keys: ItemInteractions
var _harness: Harness
var _model: ClientModel


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_model = _harness.session.model
	_keys = ItemInteractions.new()
	_keys.reads_device_input = false
	_keys.setup(_harness.session, load(MODE) as GameMode)
	_keys.player = _player
	_world.add_child(_keys)


func after_test() -> void:
	_world.free()
	_harness.close()


func test_a_crate_top_item_the_host_would_refuse_gets_no_hint() -> void:
	# A 1.2 m crate whose top is 1.7 m ahead: 2.08 m from the feet, 1.75 m from the eye.
	_world.call(&"add_box", Vector3(0, 0.6, -2.0), Vector3(1.0, 1.2, 1.0))
	var on_top := Vector3(0, 1.2, -1.7)
	_spawn(1, on_top)
	await _look_at(on_top)
	var eye := _player.get_camera().global_position
	# The ray reaches it (along the ray it is within 2 m) ...
	assert_int(TargetChoice.along_ray(_model, eye, _player.look_vector(), 2.0)).is_equal(1)
	# ... but the host measures from the feet, and refuses it: no target, no hint, no key.
	assert_int(_keys.target()).is_equal(-1)
	assert_str(_keys.hint()).is_empty()
	assert_int(_keys.pick_up()).is_equal(-1)


func test_a_floor_item_1_3_to_1_7_m_away_gets_the_hint_and_e_picks_it_up() -> void:
	for distance: float in [1.3, 1.5, 1.69]:
		var at := Vector3(0, 0, -distance)
		_model.items.clear()
		_spawn(2, at)
		await _look_at(at)
		var eye := _player.get_camera().global_position
		# Along the ray from the eye it is farther than the reach: only the feet's measure offers it.
		assert_float(eye.distance_to(at)).is_greater(2.0)
		assert_int(_keys.target()).override_failure_message("at %.2f m" % distance).is_equal(2)
		assert_str(_keys.hint()).is_equal("E: pick up Knife")
	assert_int(_keys.pick_up()).is_greater(0)
	_harness.pump()
	var sent := _harness.sent_named(Intents.PICK_UP)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["item"] as int).is_equal(2)


func test_an_item_behind_a_wall_gets_no_hint() -> void:
	var behind := Vector3(0, 0, -1.6)
	_spawn(3, behind)
	_world.call(&"add_box", Vector3(0, 1.0, -1.0), Vector3(2.0, 2.0, 0.1))
	await _look_at(behind)
	assert_int(_keys.target()).is_equal(-1)


func test_an_item_just_behind_a_thin_wall_is_never_named() -> void:
	# The knife lies 0.03 m behind a 0.1 m wall, in reach of the feet: the ray enters its pick
	# sphere before it meets the wall, but the eye cannot see it (the host's InSight refuses it).
	var behind := Vector3(0, 0, -1.08)
	_spawn(9, behind)
	_world.call(&"add_box", Vector3(0, 1.0, -1.0), Vector3(2.0, 2.0, 0.1))
	await _look_at(behind)
	var eye := _eye()
	# Where the camera's ray meets the wall's front face (z = -0.95): the ray alone would pick it.
	var wall_at := eye.distance_to(ItemView.centre_of(&"knife", behind)) * 0.95 / 1.08
	assert_int(TargetChoice.along_ray(_model, eye, _player.look_vector(), wall_at)).is_equal(9)
	assert_int(_keys.target()).is_equal(-1)
	assert_str(_keys.hint()).is_empty()
	assert_int(_keys.pick_up()).is_equal(-1)


func test_a_downed_player_in_front_hides_the_item_behind() -> void:
	# E on a downed player is M4-9's raise: it must not also pick up the item behind them.
	var behind := Vector3(0, 0, -1.6)
	_spawn(8, behind)
	var downed := _world.call(&"add_remote", Vector3(0, 0, -1.0)) as RemotePlayerBody
	downed.set_living(false)
	await _look_at(behind)
	assert_int(_keys.target()).is_equal(-1)
	downed.position = Vector3(3, 0, 0)
	await _look_at(behind)
	assert_int(_keys.target()).is_equal(8)


func test_a_floor_item_within_the_hints_margin_of_the_reach_gets_no_hint() -> void:
	# 1.85 m: within the host's 2 m, past the hint's 1.7 m (#319). Walking in, the host's feet
	# trail the player's; standing, it would accept, but the hint keeps to its margin.
	var near_edge := Vector3(0, 0, -1.85)
	_spawn(10, near_edge)
	await _look_at(near_edge)
	assert_int(TargetChoice.along_ray(_model, _eye(), _player.look_vector(), 4.0)).is_equal(10)
	assert_int(_keys.target()).is_equal(-1)
	assert_str(_keys.hint()).is_empty()
	assert_int(_keys.pick_up()).is_equal(-1)


func test_a_floor_item_beyond_the_reach_gets_no_hint() -> void:
	var far := Vector3(0, 0, -2.3)
	_spawn(4, far)
	await _look_at(far)
	assert_int(TargetChoice.along_ray(_model, _eye(), _player.look_vector(), 4.0)).is_equal(4)
	assert_int(_keys.target()).is_equal(-1)


func test_the_hand_keys_send_their_intents_with_the_cameras_facing() -> void:
	assert_int(_keys.put_down()).is_equal(-1)
	assert_int(_keys.use()).is_equal(-1)
	assert_int(_keys.swap()).is_equal(-1)
	_spawn(5, Vector3(0, 0, -1))
	_model.fold(&"ItemPickedUp", {"peer": _model.own_peer, "item": 5})
	await _look_at(Vector3(0, 1.0, -3))
	var facing := _player.look_vector()
	assert_int(_keys.put_down()).is_greater(0)
	assert_int(_keys.use()).is_greater(0)
	assert_int(_keys.swap()).is_greater(0)
	_harness.pump()
	var put := _harness.sent_named(Intents.PUT_DOWN)
	var used := _harness.sent_named(Intents.USE)
	assert_int(put.size()).is_equal(1)
	assert_int(used.size()).is_equal(1)
	assert_int(_harness.sent_named(Intents.SWAP).size()).is_equal(1)
	assert_bool((put[0].fields["facing"] as Vector3).is_equal_approx(facing)).is_true()
	assert_bool((used[0].fields["facing"] as Vector3).is_equal_approx(facing)).is_true()
	# Nothing predicted: the slots change only with the host's events.
	assert_int(_model.hand_item(_model.own_peer)).is_equal(5)


func test_the_throw_key_sends_throw_right_after_the_claims_twin() -> void:
	# A mode copy with a Throw rule (the throw fixture mode; the base mode gets its rule in 37f).
	_keys.setup(_harness.session, FixtureThrowModes.basic())
	var sent_throws: Array[Array] = []
	_keys.throw_sent.connect(
		func(seq: int, eye: Vector3, look: Vector3) -> void: sent_throws.append([seq, eye, look])
	)
	assert_int(_keys.throw()).is_equal(-1)
	_hold(5)
	_harness.session.set_motion(Vector3(0, 0, 0), Vector3.ZERO, Vector3.FORWARD, true, true, true)
	_harness.pump(50000)
	await _look_at(Vector3(0, 1.0, -3))
	var facing := _player.look_vector()
	var seq := _keys.throw()
	assert_int(seq).is_greater(0)
	_harness.deliver()
	var last := _harness.sent.slice(-3)
	var names: Array[StringName] = []
	for message: WireMessage in last:
		names.append(message.name)
	assert_array(names).contains_exactly(
		[Intents.MOVE_CLAIM, WireSchema.RELIABLE_CLAIM, Intents.THROW]
	)
	assert_int(last[2].seq).is_equal(seq)
	assert_bool((last[2].fields["facing"] as Vector3).is_equal_approx(facing)).is_true()
	assert_int(sent_throws.size()).is_equal(1)
	assert_int(sent_throws[0][0] as int).is_equal(seq)
	assert_vector(sent_throws[0][1] as Vector3).is_equal(_eye())
	# One at a time: while the arc waits for the host's answer, G sends nothing.
	_keys.predicting = func() -> bool: return true
	assert_int(_keys.throw()).is_equal(-1)
	_keys.predicting = func() -> bool: return false
	assert_int(_keys.throw()).is_greater(seq)
	# Q is still an exact put-down.
	assert_int(_keys.put_down()).is_greater(0)
	_harness.pump()
	assert_int(_harness.sent_named(Intents.PUT_DOWN).size()).is_equal(1)
	assert_int(_harness.sent_named(Intents.THROW).size()).is_equal(2)


func test_the_throw_key_sends_nothing_without_a_rule_a_phase_or_a_hand_item() -> void:
	_keys.setup(_harness.session, FixtureThrowModes.basic())
	_hold(5)
	# A mode copy with no Throw rule: nothing is sent, nothing is predicted.
	_keys.setup(_harness.session, FixtureItemModes.basic())
	assert_int(_keys.throw()).is_equal(-1)
	_keys.setup(_harness.session, FixtureThrowModes.basic())
	# A phase that takes no Throw from the living.
	_model.phase = &"lobby"
	assert_int(_keys.throw()).is_equal(-1)
	_model.phase = &"round"
	# A belt item is never thrown.
	_model.fold(&"Swapped", {"peer": _model.own_peer})
	assert_int(_keys.throw()).is_equal(-1)
	_model.fold(&"Swapped", {"peer": _model.own_peer})
	# The downed throw nothing.
	_model.fold(&"KnockedDown", {"peer": _model.own_peer, "position": Vector3.ZERO})
	assert_int(_keys.throw()).is_equal(-1)
	_harness.pump()
	assert_array(_harness.sent_named(Intents.THROW)).is_empty()


func test_the_downed_get_no_target_and_send_no_item_key() -> void:
	var at := Vector3(0, 0, -1.5)
	_spawn(6, at)
	_model.fold(&"ItemPickedUp", {"peer": _model.own_peer, "item": 6})
	_spawn(7, at)
	_model.fold(&"KnockedDown", {"peer": _model.own_peer, "position": Vector3.ZERO})
	await _look_at(at)
	assert_int(_keys.target()).is_equal(-1)
	assert_int(_keys.pick_up()).is_equal(-1)
	assert_int(_keys.put_down()).is_equal(-1)
	assert_int(_keys.swap()).is_equal(-1)


func _eye() -> Vector3:
	return _player.get_camera().global_position


func _spawn(id: int, at: Vector3) -> void:
	_model.fold(&"ItemSpawned", {"item": id, "kind": &"knife", "position": at})


## The own hand holds item `id`, of the throw fixture mode's kind `tool`.
func _hold(id: int) -> void:
	_model.fold(&"ItemSpawned", {"item": id, "kind": &"tool", "position": Vector3(0, 0, -1)})
	_model.fold(&"ItemPickedUp", {"peer": _model.own_peer, "item": id})


## Turns the player's camera at the middle of an item lying at `at`, then lets two physics frames
## cast.
func _look_at(at: Vector3) -> void:
	await get_tree().physics_frame
	var eye := _player.get_camera().global_position
	var to := ItemView.centre_of(&"knife", at) - eye
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	_player.look(0.0, pitch - _player.get_camera().get_parent_node_3d().rotation.x)
	await get_tree().physics_frame
	await get_tree().physics_frame
