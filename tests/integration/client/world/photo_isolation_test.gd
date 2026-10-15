extends GdUnitTestSuite
## The render stays out of the live view (#787, the photo ADR's §3.3): every live camera (the
## first-person one, the knocked-down and spectate cameras, the viewfinder's lens) drops the photo
## layer from its cull mask and still draws the level and the live avatars; the own and spectate
## hand items, remote bodies, a knocked-down player's live ragdoll and carried items are on the
## live-avatar layer, which the picture's camera skips; ground items and dead bodies (the ragdoll
## handed over at a death too) stay on the ground layer, which the picture draws.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const PEER := 2
const OWN := 3
const TICK_USEC := 50000

var _world: Node3D
var _model: ClientModel
var _now := 1000000


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_model = ClientModel.new(FixtureBaseMode.mode())
	_model.own_peer = OWN


func after_test() -> void:
	_world.free()


func test_the_first_person_camera_drops_the_photo_layer() -> void:
	var player := _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_assert_live(player.get_camera())


func test_the_downed_camera_drops_the_photo_layer() -> void:
	var downed := DownedCamera.new()
	_world.add_child(downed)
	_assert_live(downed.camera())


func test_the_spectate_camera_drops_the_photo_layer() -> void:
	var life := LifeView.new()
	life.reads_device_input = false
	_world.add_child(life)
	_assert_live(life.spectate_camera())


func test_the_viewfinder_lens_drops_the_photo_layer() -> void:
	var viewfinder := PhotoViewfinder.new()
	_world.add_child(viewfinder)
	_assert_live(viewfinder.camera)


func test_the_own_and_the_spectate_hand_items_are_on_the_live_avatar_layer() -> void:
	var player := _world.call(&"add_player", Vector3.ZERO) as PlayerController
	player.hand_view().show_item(&"knife", Color.WHITE)
	assert_int(PhotoLayers.layers_of(player.hand_view())).is_equal(PhotoLayers.LIVE_AVATAR)
	var life := LifeView.new()
	life.reads_device_input = false
	_world.add_child(life)
	life.spectate_hand().show_item(&"package", Color.RED, true)
	assert_int(PhotoLayers.layers_of(life.spectate_hand())).is_equal(PhotoLayers.LIVE_AVATAR)


func test_a_carried_item_is_on_the_live_avatar_layer_and_back_on_the_ground_when_dropped() -> void:
	var view := auto_free(ItemView.make(9, &"knife", Color.WHITE)) as ItemView
	assert_int(PhotoLayers.layers_of(view)).is_equal(PhotoLayers.GROUND)
	view.set_layer(PhotoLayers.LIVE_AVATAR)
	assert_int(PhotoLayers.layers_of(view)).is_equal(PhotoLayers.LIVE_AVATAR)
	view.set_layer(PhotoLayers.GROUND)
	assert_int(PhotoLayers.layers_of(view)).is_equal(PhotoLayers.GROUND)


func test_item_views_put_a_held_item_on_the_live_avatar_layer() -> void:
	var views := ItemViews.new()
	views.model = _model
	views.mode = FixtureBaseMode.mode()
	_world.add_child(views)
	_model.fold(&"ItemSpawned", {"item": 7, "kind": &"knife", "position": Vector3(1, 0, 0)})
	await _drawn()
	assert_int(PhotoLayers.layers_of(views.view_of(7))).is_equal(PhotoLayers.GROUND)
	_model.fold(&"ItemPickedUp", {"peer": PEER, "item": 7})
	await _drawn()
	assert_int(PhotoLayers.layers_of(views.view_of(7))).is_equal(PhotoLayers.LIVE_AVATAR)


func test_a_body_and_a_downed_ragdoll_are_live_and_the_dead_body_is_on_the_ground() -> void:
	var avatars := AvatarViews.new()
	avatars.model = _model
	avatars.buffer = SnapshotBuffer.new()
	avatars.rules = FixtureModes.player_rules()
	avatars.clock = func() -> int: return _now
	_world.add_child(avatars)
	var bodies := BodyViews.new()
	bodies.model = _model
	bodies.rules = FixtureModes.player_rules()
	bodies.avatars = avatars
	_world.add_child(bodies)
	_snapshot(1, avatars)
	await _drawn()
	assert_int(PhotoLayers.layers_of(avatars.body_of(PEER))).is_equal(PhotoLayers.LIVE_AVATAR)
	_model.fold(&"KnockedDown", {"peer": PEER, "position": Vector3.ZERO})
	_snapshot(2, avatars, true)
	await _drawn()
	var ragdoll := avatars.ragdoll_of(PEER)
	assert_object(ragdoll).is_not_null()
	assert_int(PhotoLayers.layers_of(ragdoll)).is_equal(PhotoLayers.LIVE_AVATAR)
	_model.fold(&"Died", {"peer": PEER, "position": Vector3.ZERO})
	await _drawn()
	assert_bool(is_instance_valid(ragdoll)).is_true()
	assert_object(ragdoll.get_parent()).is_not_same(avatars)
	assert_int(PhotoLayers.layers_of(ragdoll)).is_equal(PhotoLayers.GROUND)
	assert_int(PhotoLayers.layers_of(ragdoll) & PhotoLayers.PHOTO_VIEW).is_not_equal(0)


func _assert_live(camera: Camera3D) -> void:
	assert_object(camera).is_not_null()
	assert_int(camera.cull_mask & PhotoLayers.PHOTO).is_equal(0)
	assert_int(camera.cull_mask & PhotoLayers.GROUND).is_equal(PhotoLayers.GROUND)
	assert_int(camera.cull_mask & PhotoLayers.LIVE_AVATAR).is_equal(PhotoLayers.LIVE_AVATAR)


func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _snapshot(tick: int, avatars: AvatarViews, downed := false) -> void:
	var avatar := {
		"position": Vector3.ZERO,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"downed": downed,
		"held_item": -1,
	}
	_now += TICK_USEC
	var fields := {"tick": tick, "avatars": {PEER: avatar}}
	_model.fold_snapshot(fields)
	avatars.buffer.add(tick, fields["avatars"] as Dictionary, _now)
