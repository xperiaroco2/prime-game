extends GdUnitTestSuite
## The booth's strip in the hands (#1397, ARCHITECTURE §4.7.62): ItemViews asks StripPictures for a
## strip's picture through the BoothBook that bound it at PRINTED, so the own hand, a strip lying
## near and a strip in a friend's hand show the same session's frames; a strip beyond
## PICTURE_RANGE_M shows none; an id freed and reused shows no old strip. A strip printed into the
## own hand slides in once; the secondary button holds it up close and sends nothing. The real
## PlayerController, ItemInteractions and ItemViews against the booth fixture mode; the strip
## pictures are a stub.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const STRIP_A := 60
const STRIP_B := 61
const FRIEND := 9

var _world: Node3D
var _player: PlayerController
var _keys: ItemInteractions
var _items: ItemViews
var _strips: StubStrips
var _book: BoothBook
var _harness: Harness
var _model: ClientModel
var _red: Texture2D


## A texture for every session asked, no render.
class StubStrips:
	extends StripPictures
	var texture: Texture2D

	func texture_of(session: BoothBook.Session) -> Texture2D:
		return texture if session != null else null


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_model = _harness.session.model
	var mode := FixtureBooth.mode()
	_keys = ItemInteractions.new()
	_keys.reads_device_input = false
	_keys.setup(_harness.session, mode)
	_keys.player = _player
	_world.add_child(_keys)
	_book = BoothBook.new()
	_strips = StubStrips.new()
	_strips.enabled = false
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	_red = ImageTexture.create_from_image(image)
	_strips.texture = _red
	_world.add_child(_strips)
	_items = ItemViews.new()
	_items.model = _model
	_items.mode = mode
	_items.player = _player
	_items.strips = _strips
	_items.booth = _book
	_world.add_child(_items)


func after_test() -> void:
	_world.free()
	_harness.close()


func test_a_strip_printed_into_the_hand_shows_its_frames_and_slides_in_once() -> void:
	_print_into_hand(STRIP_A)
	await _frames(2)
	var hand := _player.hand_view()
	assert_object(hand.shown_kind()).is_equal(StripLooks.STRIP)
	assert_object(hand.view().picture()).is_same(_red)
	assert_bool(hand.is_sliding()).is_true()
	assert_bool(_book.take_fresh(STRIP_A)).is_false()


func test_the_secondary_button_holds_a_strip_up_close_sending_nothing() -> void:
	_print_into_hand(STRIP_A)
	await _frames(2)
	assert_int(_keys.use_secondary()).is_equal(-1)
	assert_bool(_player.hand_view().is_close()).is_true()
	assert_int(_keys.use_secondary()).is_equal(-1)
	assert_bool(_player.hand_view().is_close()).is_false()
	_harness.pump()
	assert_array(_harness.sent_named(Intents.USE_SECONDARY)).is_empty()


func test_a_friend_holding_the_strip_shows_the_same_picture() -> void:
	_print_into_hand(STRIP_A)
	await _frames(2)
	var own: Texture2D = _items.picture_for(_model.items[STRIP_A] as ClientModel.Item)
	_fold(&"ItemPickedUp", {"peer": FRIEND, "item": STRIP_A})
	# Looked up by the item alone (LifeView's spectate hand has no id at hand).
	assert_object(_items.picture_for(_model.items[STRIP_A] as ClientModel.Item)).is_same(own)
	assert_object(_book.session_of(STRIP_A)).is_not_null()


func test_a_strip_lying_near_shows_its_picture_and_beyond_the_range_none() -> void:
	_fold(
		&"ItemSpawned", {"item": STRIP_A, "kind": StripLooks.STRIP, "position": Vector3(0, 0, -3)}
	)
	var far := Vector3(0, 0, -ItemViews.PICTURE_RANGE_M - 3.0)
	_fold(&"ItemSpawned", {"item": STRIP_B, "kind": StripLooks.STRIP, "position": far})
	_printed([STRIP_A, STRIP_B])
	await _frames(2)
	assert_object(_items.view_of(STRIP_A).picture()).is_same(_red)
	assert_object(_items.view_of(STRIP_B).picture()).is_null()


func test_a_reused_id_shows_no_old_strip() -> void:
	_fold(
		&"ItemSpawned", {"item": STRIP_A, "kind": StripLooks.STRIP, "position": Vector3(0, 0, -3)}
	)
	_printed([STRIP_A])
	await _frames(2)
	assert_object(_items.view_of(STRIP_A).picture()).is_same(_red)
	_fold(&"ItemVanished", {"item": STRIP_A})
	_fold(
		&"ItemSpawned", {"item": STRIP_A, "kind": StripLooks.STRIP, "position": Vector3(0, 0, -3)}
	)
	await _frames(2)
	assert_object(_items.view_of(STRIP_A).picture()).is_null()


## Strip `id` printed into the own hand: its ItemSpawned and ItemPickedUp before the PRINTED, as
## the host sends them (GiveItem.give_new, §9.5.29).
func _print_into_hand(id: int) -> void:
	_fold(&"ItemSpawned", {"item": id, "kind": StripLooks.STRIP, "position": Vector3(0, 0, 3)})
	_fold(&"ItemPickedUp", {"peer": _model.own_peer, "item": id})
	_printed([id])


func _printed(ids: Array[int]) -> void:
	var fields := {
		"station": 0,
		"strip": 1,
		"step": BoothStepEvent.STARTED,
		"frames": 1,
	}
	_fold(BoothBook.STEP_EVENT, fields)
	var printed := fields.duplicate()
	printed["step"] = BoothStepEvent.PRINTED
	printed["items"] = PackedInt32Array(ids)
	_fold(BoothBook.STEP_EVENT, printed)


## The model folds first, then the book, as ItemWorld forwards an event.
func _fold(event_name: StringName, fields: Dictionary) -> void:
	_model.fold(event_name, fields)
	_book.fold(event_name, fields)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
