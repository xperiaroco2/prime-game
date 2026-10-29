extends GdUnitTestSuite
## The holder's photo (#787, photo P8; the photo ADR §3.3): the primary button with a photo in the
## own hand holds it up close in front of the eye, or back, and sends nothing (a photo has no Use
## rule); the close-up ends when the hand item changes, at a knockdown and when the keys stop
## listening. The hand shows the photo's picture (ItemViews.picture_for, keyed on the item, so a
## swap to another photo shows the other picture), and a photo lying beyond PICTURE_RANGE_M of
## the drawing camera shows none, so PhotoPictures can free its texture. The real PlayerController,
## ItemInteractions and ItemViews against a fixture photo mode; the pictures are a stub.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const PHOTO_A := 50
const PHOTO_B := 51
const FILM := 40
const NEAR_PHOTO := 52
const FAR_PHOTO := 53

var _world: Node3D
var _player: PlayerController
var _keys: ItemInteractions
var _items: ItemViews
var _pictures: StubPictures
var _harness: Harness
var _model: ClientModel
var _mode: GameMode
var _red: Texture2D
var _blue: Texture2D


## Pictures by shot id, no render.
class StubPictures:
	extends PhotoPictures
	var textures: Dictionary[int, Texture2D] = {}

	func texture_of(shot: int) -> Texture2D:
		return textures.get(shot)


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_model = _harness.session.model
	_mode = FixturePhotoModes.basic()
	_keys = ItemInteractions.new()
	_keys.reads_device_input = false
	_keys.setup(_harness.session, _mode)
	_keys.player = _player
	_world.add_child(_keys)
	_pictures = StubPictures.new()
	_red = _texture(Color.RED)
	_blue = _texture(Color.BLUE)
	_pictures.textures = {7: _red, 8: _blue}
	_world.add_child(_pictures)
	_items = ItemViews.new()
	_items.model = _model
	_items.mode = _mode
	_items.player = _player
	_items.pictures = _pictures
	_world.add_child(_items)


func after_test() -> void:
	_world.free()
	_harness.close()


func test_the_primary_button_holds_a_photo_up_close_and_back_sending_nothing() -> void:
	_hold(PHOTO_A, 7)
	await _frames(2)
	assert_int(_keys.use()).is_equal(-1)
	assert_bool(_keys.close_up()).is_true()
	assert_bool(_player.hand_view().is_close()).is_true()
	await _frames(2)
	assert_bool(_player.hand_view().is_close()).is_true()
	assert_int(_keys.use()).is_equal(-1)
	assert_bool(_keys.close_up()).is_false()
	assert_bool(_player.hand_view().is_close()).is_false()
	_harness.pump()
	assert_array(_harness.sent_named(Intents.USE)).is_empty()


func test_another_item_in_hand_still_sends_use() -> void:
	_model.fold(&"ItemSpawned", {"item": FILM, "kind": &"film", "position": Vector3(0, 0, 3)})
	_model.fold(&"ItemPickedUp", {"peer": _model.own_peer, "item": FILM})
	await _frames(2)
	assert_int(_keys.use()).is_greater(0)
	assert_bool(_keys.close_up()).is_false()
	_harness.pump()
	assert_int(_harness.sent_named(Intents.USE).size()).is_equal(1)


func test_the_close_up_shows_the_photo_s_picture() -> void:
	_hold(PHOTO_A, 7)
	await _frames(2)
	_keys.use()
	await _frames(2)
	assert_bool(_player.hand_view().is_close()).is_true()
	assert_object(_player.hand_view().view().picture()).is_same(_red)


func test_a_swap_to_the_belt_photo_shows_its_picture_and_ends_the_close_up() -> void:
	_hold(PHOTO_B, 8)
	_hold(PHOTO_A, 7, PHOTO_B)
	await _frames(2)
	assert_object(_player.hand_view().view().picture()).is_same(_red)
	_keys.use()
	_model.fold(&"Swapped", SwappedEvent.new(_model.own_peer, 0).to_dict())
	await _frames(2)
	assert_int(_model.hand_item(_model.own_peer)).is_equal(PHOTO_B)
	assert_object(_player.hand_view().view().picture()).is_same(_blue)
	assert_bool(_keys.close_up()).is_false()
	assert_bool(_player.hand_view().is_close()).is_false()


func test_a_knockdown_ends_the_close_up() -> void:
	_hold(PHOTO_A, 7)
	await _frames(2)
	_keys.use()
	var down := KnockedDownEvent.new(_model.own_peer, Vector3.ZERO)
	_model.fold(down.event_name(), down.to_dict())
	await _frames(2)
	assert_bool(_keys.close_up()).is_false()
	assert_bool(_player.hand_view().is_close()).is_false()


func test_the_keys_no_longer_listening_end_the_close_up() -> void:
	_hold(PHOTO_A, 7)
	await _frames(2)
	_keys.use()
	_keys.listening = false
	await _frames(2)
	assert_bool(_keys.close_up()).is_false()
	assert_bool(_player.hand_view().is_close()).is_false()


func test_a_photo_beyond_the_picture_range_shows_none() -> void:
	var eye := _player.get_camera().global_position
	assert_object(get_viewport().get_camera_3d()).is_same(_player.get_camera())
	_lying(NEAR_PHOTO, 7, Vector3(0, 0, -3))
	_lying(FAR_PHOTO, 8, Vector3(0, 0, -ItemViews.PICTURE_RANGE_M - 3.0))
	await _frames(2)
	assert_float(eye.distance_to(_items.view_of(FAR_PHOTO).global_position)).is_greater(
		ItemViews.PICTURE_RANGE_M
	)
	assert_object(_items.view_of(NEAR_PHOTO).picture()).is_same(_red)
	assert_object(_items.view_of(FAR_PHOTO).picture()).is_null()
	# Walked away from, the near one lets its texture go too.
	_player.global_position = Vector3(0, 0, ItemViews.PICTURE_RANGE_M + 3.0)
	await _frames(2)
	assert_object(_items.view_of(NEAR_PHOTO).picture()).is_null()


## Photo `id` showing shot `shot`, picked up by the own player (`belted`: the hand item that goes
## to the belt).
func _hold(id: int, shot: int, belted := -1) -> void:
	_lying(id, shot, Vector3(0, 0, 3))
	var fields := {"peer": _model.own_peer, "item": id}
	if belted >= 0:
		fields["belted"] = belted
		# The belted item keeps place 0; this one goes into the free place 1 (GDD §6).
		fields["place"] = 1
	_model.fold(&"ItemPickedUp", fields)


func _lying(id: int, shot: int, at: Vector3) -> void:
	_model.fold(&"ItemSpawned", {"item": id, "kind": &"photo", "position": at})
	(_model.items[id] as ClientModel.Item).shot = shot


func _texture(colour: Color) -> Texture2D:
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
