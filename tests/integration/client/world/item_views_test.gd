extends GdUnitTestSuite
## ItemViews and CircleViews (ARCHITECTURE §4.7, Hands; M4-8; the M4 ADR's D7 (a), D10 (b)):
## every item of the model where it lies, at another player's hand or belt attach point, a
## two-handed package in front, hidden while its holder has no body, and the own hand item in the
## first-person view only; circles of their station kind's size in their colour, dimmed when done;
## nothing of either draws through walls (`no_depth_test`): no marker over a circle, no label over
## an item (the M4 ADR's §3 item 5; the marker of D10 (b) went with Delivery by meaning, D3a).

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const MODE := "res://content/modes/base_mode.tres"
const OTHER := 2
const TICK_USEC := 50000

var _mode: GameMode
var _model: ClientModel
var _world: Node3D
var _avatars: AvatarViews
var _items: ItemViews
var _circles: CircleViews
var _player: PlayerController
var _now := 1000000


func before_test() -> void:
	_mode = load(MODE) as GameMode
	_model = ClientModel.new(_mode)
	_model.own_peer = 1
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
	_circles = CircleViews.new()
	_circles.model = _model
	_circles.mode = _mode
	_world.add_child(_circles)


func after_test() -> void:
	_world.free()


func test_an_item_on_the_ground_lies_where_the_events_put_it() -> void:
	_spawn(1, &"knife", Vector3(2, 0, -1))
	await _drawn()
	var view := _items.view_of(1)
	assert_object(view).is_not_null()
	assert_that(view.global_position).is_equal(Vector3(2, 0, -1))
	assert_bool(view.is_look_shown()).is_true()
	assert_bool(view.is_in_group(SightHider.GROUP)).is_true()
	_model.fold(&"ItemPlaced", {"item": 1, "position": Vector3(3, 0, 0), "cause": &"put_down"})
	await _drawn()
	assert_that(view.global_position).is_equal(Vector3(3, 0, 0))


func test_an_item_in_flight_is_drawn_neither_in_a_hand_nor_where_it_lay() -> void:
	# §7.1.16: from ItemThrown until its rest the item is in no hand and lies nowhere. With no
	# arc to draw (ItemViews heard no ItemThrown here; at a phase change it drops its arcs) it is
	# not drawn at all; the arcs: item_views_flight_test.gd.
	_other_at(Vector3(4, 0, 0))
	_spawn(1, &"knife", Vector3(2, 0, -1))
	_model.fold(&"ItemPickedUp", {"peer": OTHER, "item": 1})
	await _drawn()
	var view := _items.view_of(1)
	assert_bool(view.is_look_shown()).is_true()
	var launch := {"item": 1, "peer": OTHER, "origin": Vector3(4, 1.6, 0), "tick": 9}
	launch["velocity"] = Vector3(0, 5, -8)
	launch["gravity"] = Vector3(0, -9.8, 0)
	_model.fold(&"ItemThrown", launch)
	await _drawn()
	assert_bool(view.is_look_shown()).is_false()
	_model.fold(&"ItemPlaced", {"item": 1, "position": Vector3(4, 0, -6), "cause": &"thrown"})
	await _drawn()
	assert_that(view.global_position).is_equal(Vector3(4, 0, -6))
	assert_bool(view.is_look_shown()).is_true()


func test_another_players_items_hang_at_its_attach_points() -> void:
	_other_at(Vector3(4, 0, 0))
	_spawn(1, &"knife", Vector3.ZERO)
	_spawn(2, &"package", Vector3.ZERO, 0)
	_model.fold(&"ItemPickedUp", {"peer": OTHER, "item": 1})
	await _drawn()
	var body := _avatars.body_of(OTHER)
	assert_object(body).is_not_null()
	_assert_at(_items.view_of(1), body.hand_point())
	# The package in front with both hands; the knife it moved to the belt.
	_model.fold(&"ItemPickedUp", {"peer": OTHER, "item": 2, "belted": 1, "place": 1})
	await _drawn()
	_assert_at(_items.view_of(2), body.carry_point())
	_assert_at(_items.view_of(1), body.belt_point())
	assert_bool(_items.view_of(1).is_look_shown()).is_true()


func test_an_item_of_a_player_with_no_body_drawn_is_hidden() -> void:
	_spawn(1, &"knife", Vector3.ZERO)
	_model.fold(&"ItemPickedUp", {"peer": 7, "item": 1})
	await _drawn()
	assert_bool(_items.view_of(1).is_look_shown()).is_false()


func test_the_own_hand_item_is_drawn_in_first_person_only() -> void:
	_spawn(1, &"knife", Vector3.ZERO)
	_spawn(2, &"package", Vector3.ZERO, 0)
	_model.fold(&"ItemPickedUp", {"peer": 1, "item": 1})
	await _drawn()
	assert_bool(_items.view_of(1).is_look_shown()).is_false()
	assert_str(String(_player.hand_view().shown_kind())).is_equal("knife")
	assert_bool(_player.hand_view().is_ancestor_of(_player.get_camera()) == false).is_true()
	assert_bool(_player.get_camera().is_ancestor_of(_player.hand_view())).is_true()
	_model.fold(&"ItemPickedUp", {"peer": 1, "item": 2, "belted": 1, "place": 1})
	await _drawn()
	assert_str(String(_player.hand_view().shown_kind())).is_equal("package")
	_model.fold(&"ItemPlaced", {"item": 2, "position": Vector3(0, 0, 4), "cause": &"put_down"})
	_model.fold(&"Swapped", {"peer": 1, "place": 0})
	await _drawn()
	assert_str(String(_player.hand_view().shown_kind())).is_equal("knife")
	_model.fold(&"Swapped", {"peer": 1, "place": 1})
	await _drawn()
	assert_str(String(_player.hand_view().shown_kind())).is_empty()


func test_the_own_downed_players_items_lie_at_its_body_not_in_the_hand_view() -> void:
	# The downed camera looks at the own body from 2 m back: a hand item under the inactive
	# first-person camera would hang in mid-air over the body.
	_spawn(1, &"knife", Vector3.ZERO)
	_model.fold(&"ItemPickedUp", {"peer": 1, "item": 1})
	await _drawn()
	assert_str(String(_player.hand_view().shown_kind())).is_equal("knife")
	_model.fold(&"KnockedDown", {"peer": 1, "position": _player.global_position})
	await _drawn()
	assert_str(String(_player.hand_view().shown_kind())).is_empty()
	var view := _items.view_of(1)
	assert_bool(view.is_look_shown()).is_true()
	assert_bool(view.global_position.is_equal_approx(_player.global_position)).is_true()


## KE5: knocked down, the own body moves with the host's while the controller holds still where
## the knockdown found it: the own items lie at the own avatar's point, not at the controller.
func test_the_own_downed_players_items_follow_its_avatars_point_not_the_controller() -> void:
	_spawn(1, &"knife", Vector3.ZERO)
	_model.fold(&"ItemPickedUp", {"peer": 1, "item": 1})
	_model.fold(&"KnockedDown", {"peer": 1, "position": _player.global_position})
	var moved := _player.global_position + Vector3(2, 0, -1)
	_own_at(moved)
	await _drawn()
	assert_vector(_avatars.point_of(1, Vector3.INF)).is_equal(moved)
	var view := _items.view_of(1)
	assert_bool(view.is_look_shown()).is_true()
	assert_vector(view.global_position).is_equal_approx(moved, Vector3.ONE * 0.001)


func test_an_item_put_out_of_the_bodys_sight_is_hidden_in_that_physics_frame() -> void:
	# The downed camera's sight hiding (SightHider, M4-9) must see the view where it is now: placed
	# after it cast, the item would be drawn for a frame where the body's eye cannot see it.
	_world.call(&"add_box", Vector3(0, 1.0, -2.0), Vector3(4.0, 2.0, 0.2))
	var hider := SightHider.new()
	_world.add_child(hider)
	hider.watch_from(Vector3(0, 0.5, 0))
	_spawn(1, &"knife", Vector3(2, 0, 0))
	await _drawn()
	var view := _items.view_of(1)
	assert_bool(view.visible).is_true()
	# The event lands at the start of a physics frame (before the views' and the hider's steps);
	# by the next one the view must have moved and been hidden, with no drawn frame between.
	await get_tree().physics_frame
	_model.fold(&"ItemPlaced", {"item": 1, "position": Vector3(0, 0, -4), "cause": &"put_down"})
	await get_tree().physics_frame
	assert_that(view.global_position).is_equal(Vector3(0, 0, -4))
	assert_bool(view.visible).is_false()


func test_an_unknown_kind_gets_a_labelled_box_hidden_by_walls() -> void:
	_spawn(1, &"wrench", Vector3.ZERO)
	await _drawn()
	var labels := _items.view_of(1).find_children("*", "Label3D", true, false)
	assert_int(labels.size()).is_equal(1)
	assert_str((labels[0] as Label3D).text).is_equal("wrench")
	assert_bool((labels[0] as Label3D).no_depth_test).is_false()


func test_views_go_with_the_models_items() -> void:
	_spawn(1, &"knife", Vector3.ZERO)
	await _drawn()
	assert_int(_items.count()).is_equal(1)
	_model.clear_match()
	await _drawn()
	assert_int(_items.count()).is_equal(0)


func test_an_id_freed_and_reused_in_one_frame_gets_the_new_kinds_view() -> void:
	_spawn(1, &"knife", Vector3.ZERO)
	await _drawn()
	assert_str(_items.view_of(1).kind).is_equal(&"knife")
	_model.fold(&"ItemVanished", {"item": 1})
	_spawn(1, &"wrench", Vector3(1, 0, 1))
	await _drawn()
	assert_int(_items.count()).is_equal(1)
	assert_str(_items.view_of(1).kind).is_equal(&"wrench")


func test_an_id_reused_in_one_frame_by_the_same_kind_gets_a_new_view() -> void:
	_spawn(1, &"package", Vector3.ZERO, 0)
	await _drawn()
	var old_view := _items.view_of(1)
	_model.fold(&"ItemVanished", {"item": 1})
	_model.fold(
		&"ItemSpawned",
		{
			"item": 1,
			"kind": &"package",
			"position": Vector3(2, 0, 2),
			"station": 1,
			"colour": Color(0.9, 0.2, 0.2)
		}
	)
	await _drawn()
	assert_int(_items.count()).is_equal(1)
	var view := _items.view_of(1)
	assert_object(view).is_not_same(old_view)
	assert_vector(view.global_position).is_equal(Vector3(2, 0, 2))


func test_a_circle_has_its_kinds_size_and_colour_and_dims_when_done() -> void:
	_station(0, Color(0.9, 0.2, 0.2), Vector3(5, 0, 5))
	await _drawn()
	var view := _circles.view_of(0)
	var kind := CircleViews.station_kind(_mode, &"circle")
	assert_object(kind).is_not_null()
	var mesh := view.mesh as CylinderMesh
	assert_float(mesh.top_radius).is_equal(kind.radius_m)
	assert_float(mesh.height).is_equal(kind.height_m)
	var open := (view.material_override as StandardMaterial3D).albedo_color
	assert_float(open.r).is_equal_approx(0.9, 1e-5)
	_spawn(3, &"package", Vector3.ZERO, 0)
	_model.fold(&"PackageDelivered", {"item": 3, "station": 0})
	await _drawn()
	var done := (view.material_override as StandardMaterial3D).albedo_color
	assert_float(done.a).is_less(open.a)
	assert_float(done.r).is_less(open.r)


func test_nothing_draws_through_walls_not_even_over_a_carried_packages_circle() -> void:
	_station(0, Color(0.9, 0.2, 0.2), Vector3(5, 0, 5))
	_station(1, Color(0.2, 0.2, 0.9), Vector3(-5, 0, -5))
	_spawn(3, &"package", Vector3.ZERO, 1)
	_spawn(4, &"wrench", Vector3(1, 0, 0))
	_model.fold(&"ItemPickedUp", {"peer": 1, "item": 3})
	await _drawn()
	# The own package is carried and nothing floats over its circle; no item, label, circle or
	# other node draws through walls.
	assert_int(_circles.find_children("*", "", true, false).size()).is_equal(2)
	for node: Node in _world.find_children("*", "", true, false):
		assert_bool(_draws_through_walls(node)).override_failure_message(str(node.name)).is_false()


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


func _assert_at(view: ItemView, point: Node3D) -> void:
	assert_bool(view.global_position.is_equal_approx(point.global_position)).is_true()
	assert_bool(view.is_look_shown()).is_true()


func _spawn(id: int, kind: StringName, at: Vector3, station := -1) -> void:
	var fields := {"item": id, "kind": kind, "position": at}
	if station >= 0:
		fields["station"] = station
		fields["colour"] = Color(0.2, 0.2, 0.9)
	_model.fold(&"ItemSpawned", fields)


func _station(id: int, colour: Color, at: Vector3) -> void:
	_model.fold(
		&"StationPlaced", {"station": id, "kind": &"circle", "colour": colour, "position": at}
	)


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


## The own avatar at `at` in three snapshots (KE5: a knocked-down player's own snapshot has it).
func _own_at(at: Vector3) -> void:
	for tick: int in range(1, 4):
		_now += TICK_USEC
		var avatar := {
			"position": at,
			"velocity": Vector3.ZERO,
			"facing": Vector3.FORWARD,
			"downed": true,
			"held_item": 1,
		}
		var fields := {"tick": tick, "avatars": {_model.own_peer: avatar}}
		_model.fold_snapshot(fields)
		_avatars.buffer.add(tick, fields["avatars"] as Dictionary, _now)
	_now += TICK_USEC * 10


## Waits until the views have run since the state the test folded: ItemViews places in its
## _physics_process (two physics frames), CircleViews draws in its _process. Under load several
## physics frames run inside one idle frame, before its _process, and process_frame is emitted
## before that frame's _process: the second one comes after a _process that saw the state (#222).
func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
