extends GdUnitTestSuite
## ItemViews' items in flight (ARCHITECTURE §4.7.25, §7.1.16; the throwing ADR's TE5 (a); 37e) in
## a fixture world with a local player and AvatarViews on a fake clock, the throw fixture mode
## (FixtureThrowModes: 10 m/s, 9.8 m/s², radius 0.15 m): another player's throw leaves its body's
## hand as the body is drawn throwing it, flies on the arc at the avatars' drawn tick, holds to
## the stop over its rest and falls there; an item in flight is hidden at a phase change; the
## view in flight is the ordinary ItemView in SightHider's group, nothing drawn through walls; the
## own throw empties the hand at the press, its Rejected fills it again, and its drawn item stops
## at a wall of the own scene.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const OTHER := 2
const TICK_USEC := 50000
const ORIGIN := Vector3(4, 1.6, 0)
const VELOCITY := Vector3(0, 4, -8)
const GRAVITY := Vector3(0, -9.8, 0)

var _mode: GameMode
var _model: ClientModel
var _world: Node3D
var _avatars: AvatarViews
var _items: ItemViews
var _player: PlayerController
var _now := 1000000


func before_test() -> void:
	_mode = FixtureThrowModes.basic()
	_model = ClientModel.new(_mode)
	_model.own_peer = 1
	_model.phase = &"round"
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3(0, 0, 5)) as PlayerController
	_avatars = AvatarViews.new()
	_avatars.model = _model
	_avatars.buffer = SnapshotBuffer.new()
	_avatars.rules = _mode.player_rules
	_avatars.clock = func() -> int: return _now
	_world.add_child(_avatars)
	_items = ItemViews.new()
	_items.model = _model
	_items.mode = _mode
	_items.avatars = _avatars
	_items.player = _player
	_world.add_child(_items)


func after_test() -> void:
	_world.free()


func test_another_players_throw_leaves_its_hand_then_flies_lands_and_falls() -> void:
	_other_at(Vector3(4, 0, 0))
	_spawn(1, OTHER)
	await _drawn()
	var view := _items.view_of(1)
	var launch := ceili(_avatars.drawn_at()) + 2
	_event(&"ItemThrown", _launch(1, launch))
	await _drawn()
	# Before the drawn tick reaches the launch, still in the body's hand.
	var body := _avatars.body_of(OTHER)
	assert_bool(view.global_position.is_equal_approx(body.hand_point().global_position)).is_true()
	assert_bool(view.is_look_shown()).is_true()
	await _tick(4)
	var n := _avatars.drawn_at() - launch
	assert_float(n).is_greater(0.0)
	assert_vector(view.global_position).is_equal_approx(
		ItemArc.point_at(ORIGIN, VELOCITY, GRAVITY, n), Vector3.ONE * 1e-4
	)
	assert_bool(view.is_look_shown()).is_true()
	# The ordinary depth-tested view, in SightHider's group: no trail, outline or overlay.
	assert_bool(view.is_in_group(SightHider.GROUP)).is_true()
	assert_int(view.get_child_count()).is_equal(1)
	for node: Node in view.find_children("*", "", true, false):
		assert_bool(_draws_through_walls(node)).override_failure_message(str(node)).is_false()
	# The host stopped it at the latest tick it can have (the estimate at the arrival): the drawn
	# item flies on to the point above the rest, then falls to it.
	var stop := float(_avatars.host_tick() - launch)
	var above := ItemArc.point_at(ORIGIN, VELOCITY, GRAVITY, stop)
	var rest := Vector3(above.x, 0, above.z)
	_event(&"ItemPlaced", {"item": 1, "position": rest, "cause": Items.THROWN})
	await _drawn()
	assert_float(view.global_position.distance_to(rest)).is_greater(0.5)
	assert_float(_avatars.drawn_at() - launch).is_less(stop)
	await _tick(int(stop - n) + 2)
	assert_float(view.global_position.y).is_less(above.y)
	await _tick(20)
	assert_vector(view.global_position).is_equal(rest)
	assert_bool(view.is_look_shown()).is_true()
	assert_bool(_items.flights.has(1)).is_false()


func test_an_item_in_flight_at_a_phase_change_is_hidden_until_it_rests() -> void:
	_other_at(Vector3(4, 0, 0))
	_spawn(1, OTHER)
	await _drawn()
	_event(&"ItemThrown", _launch(1, floori(_avatars.drawn_at()) - 2))
	await _drawn()
	var view := _items.view_of(1)
	assert_bool(view.is_look_shown()).is_true()
	_event(&"PhaseChanged", {"phase": &"end", "end_tick": -1})
	await _drawn()
	assert_bool(view.is_look_shown()).is_false()
	# No later phase draws it again; its rest, if it comes, shows it there.
	await _tick(3)
	assert_bool(view.is_look_shown()).is_false()
	_event(&"ItemPlaced", {"item": 1, "position": Vector3(4, 0, -3), "cause": Items.THROWN})
	await _drawn()
	assert_vector(view.global_position).is_equal(Vector3(4, 0, -3))
	assert_bool(view.is_look_shown()).is_true()


func test_the_own_throw_empties_the_hand_and_its_rejected_fills_it_again() -> void:
	_spawn(1, _model.own_peer)
	await _drawn()
	assert_str(String(_player.hand_view().shown_kind())).is_equal("tool")
	var view := _items.view_of(1)
	assert_bool(view.is_look_shown()).is_false()
	var eye := _player.get_camera().global_position
	assert_bool(_items.predict_throw(5, eye, _player.look_vector())).is_true()
	assert_bool(_items.is_predicting()).is_true()
	await _drawn()
	assert_str(String(_player.hand_view().shown_kind())).is_empty()
	assert_bool(view.is_look_shown()).is_true()
	assert_float(view.global_position.distance_to(eye)).is_greater(0.1)
	_event(&"Rejected", {"seq": 5, "reason": &"no_floor"})
	await _drawn()
	assert_str(String(_player.hand_view().shown_kind())).is_equal("tool")
	assert_bool(view.is_look_shown()).is_false()


func test_the_own_drawn_item_stops_at_a_wall_of_the_own_scene() -> void:
	_spawn(1, _model.own_peer)
	await _drawn()
	var eye := _player.get_camera().global_position
	var look := _player.look_vector()
	assert_float(look.z).is_less(-0.9)
	# A wall 1.5 m ahead, 0.2 m thick: its near face at eye.z - 1.4.
	_world.call(&"add_box", Vector3(eye.x, 1.5, eye.z - 1.5), Vector3(4, 3, 0.2))
	await get_tree().physics_frame
	_items.predict_throw(5, eye, look)
	for i: int in 30:
		await get_tree().physics_frame
	var at := _items.view_of(1).global_position
	# Unblocked, the arc would be far beyond the wall by now.
	var arc: ItemArc = _items.flights.arcs[1]
	assert_float(ItemArc.point_at(arc.origin, arc.velocity, arc.gravity, arc.n).z).is_less(
		eye.z - 3.0
	)
	assert_float(at.z).is_greater(eye.z - 1.4)
	assert_float(at.z).is_less(eye.z - 0.5)


func _spawn(id: int, holder: int) -> void:
	_model.fold(&"ItemSpawned", {"item": id, "kind": &"tool", "position": Vector3.ZERO})
	_model.fold(&"ItemPickedUp", {"peer": holder, "item": id})


func _launch(id: int, tick: int) -> Dictionary:
	return {
		"item": id,
		"peer": OTHER,
		"origin": ORIGIN,
		"velocity": VELOCITY,
		"gravity": GRAVITY,
		"tick": tick,
	}


## An event as the session delivers it: folded into the model, then heard by the views.
func _event(event_name: StringName, fields: Dictionary) -> void:
	_model.fold(event_name, fields)
	_items.on_event(event_name, fields)


func _other_at(at: Vector3) -> void:
	for tick: int in range(1, 4):
		_now += TICK_USEC
		var avatar := {
			"position": at,
			"velocity": Vector3.ZERO,
			"facing": Vector3.FORWARD,
			"downed": false,
			"held_item": -1,
		}
		var fields := {"tick": tick, "avatars": {OTHER: avatar}}
		_model.fold_snapshot(fields)
		_avatars.buffer.add(tick, fields["avatars"] as Dictionary, _now)
	_now += TICK_USEC * 10


## The fake clock moves `ticks` host ticks on, then the views draw.
func _tick(ticks: int) -> void:
	_now += TICK_USEC * ticks
	await _drawn()


## Waits until the views have run since the state the test folded (item_views_test's _drawn()).
func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _draws_through_walls(node: Node) -> bool:
	var label := node as Label3D
	if label != null:
		return label.no_depth_test
	var mesh_view := node as MeshInstance3D
	if mesh_view == null:
		return false
	var materials: Array[Material] = [mesh_view.material_override]
	if mesh_view.mesh != null:
		for surface: int in mesh_view.mesh.get_surface_count():
			materials.append(mesh_view.mesh.surface_get_material(surface))
	for material: Material in materials:
		var standard := material as BaseMaterial3D
		if standard != null and standard.no_depth_test:
			return true
	return false
