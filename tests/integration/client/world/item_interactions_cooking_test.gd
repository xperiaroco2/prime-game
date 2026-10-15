extends GdUnitTestSuite
## E on a cooking box against a fixture world (ARCHITECTURE §4.7.55, #776; cooking ADR §6): the
## real PlayerController on a floor, looking through its own camera at a box of
## FixtureCookingModes. A tap (E released before ItemInteractions.HOLD_SECONDS) sends
## Interact(station -1, item box), which takes an ingredient out; a hold reaching HOLD_SECONDS sends
## PickUp(box) once and nothing on the release. The box is the one aimed at when E went down; the
## hold is dropped, sending nothing, when the keys stop listening (the Esc menu) or the crosshair
## leaves the box. An item that is no box is still picked up on the press.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const BOX := 7
const KNIFE := 8
const AT := Vector3(0, 0, -1.4)

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
	_keys.setup(_harness.session, FixtureCookingModes.basic(1))
	_keys.player = _player
	_world.add_child(_keys)
	_model.fold(&"ItemSpawned", {"item": BOX, "kind": &"box_bun_a", "position": AT})


func after_test() -> void:
	_world.free()
	_harness.close()


func test_a_tap_on_a_box_sends_interact_with_the_box_on_the_release() -> void:
	await _look_at(AT)
	assert_int(_keys.target()).is_equal(BOX)
	assert_int(_keys.press_interact()).is_equal(-1)
	assert_int(_keys.held_box()).is_equal(BOX)
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS * 0.5)).is_equal(-1)
	assert_int(_keys.release_interact()).is_greater(0)
	_harness.pump()
	var sent := _harness.sent_named(Intents.INTERACT)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["station"] as int).is_equal(-1)
	assert_int(sent[0].fields["item"] as int).is_equal(BOX)
	assert_int(_harness.sent_named(Intents.PICK_UP).size()).is_equal(0)
	assert_int(_keys.held_box()).is_equal(-1)


func test_a_hold_on_a_box_picks_it_up_once_and_the_release_sends_nothing() -> void:
	await _look_at(AT)
	_keys.press_interact()
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS * 0.6)).is_equal(-1)
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS * 0.6)).is_greater(0)
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS)).is_equal(-1)
	assert_int(_keys.release_interact()).is_equal(-1)
	_harness.pump()
	var sent := _harness.sent_named(Intents.PICK_UP)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].fields["item"] as int).is_equal(BOX)
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(0)


func test_the_esc_menu_drops_the_hold_and_sends_nothing() -> void:
	await _look_at(AT)
	_keys.press_interact()
	_keys.listening = false
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS)).is_equal(-1)
	assert_int(_keys.held_box()).is_equal(-1)
	_keys.listening = true
	assert_int(_keys.release_interact()).is_equal(-1)
	_harness.pump()
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(0)
	assert_int(_harness.sent_named(Intents.PICK_UP).size()).is_equal(0)


func test_looking_away_from_the_box_drops_the_hold_and_sends_nothing() -> void:
	await _look_at(AT)
	_keys.press_interact()
	await _look_at(Vector3(0, 6, -1.4))
	assert_int(_keys.target()).is_equal(-1)
	assert_int(_keys.hold_step(ItemInteractions.HOLD_SECONDS)).is_equal(-1)
	assert_int(_keys.release_interact()).is_equal(-1)
	_harness.pump()
	assert_int(_harness.sent_named(Intents.INTERACT).size()).is_equal(0)
	assert_int(_harness.sent_named(Intents.PICK_UP).size()).is_equal(0)


func test_an_item_that_is_no_box_is_picked_up_on_the_press() -> void:
	_model.fold(&"ItemVanished", {"item": BOX})
	_model.fold(&"ItemSpawned", {"item": KNIFE, "kind": &"bun_a", "position": AT})
	await _look_at(AT)
	assert_int(_keys.target()).is_equal(KNIFE)
	assert_int(_keys.press_interact()).is_greater(0)
	assert_int(_keys.held_box()).is_equal(-1)
	_harness.pump()
	assert_int(_harness.sent_named(Intents.PICK_UP).size()).is_equal(1)


## Turns the player's camera at the middle of a box lying at `at`, then lets two physics frames
## cast.
func _look_at(at: Vector3) -> void:
	await get_tree().physics_frame
	var eye := _player.get_camera().global_position
	var to := ItemView.centre_of(&"box_bun_a", at) - eye
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	_player.look(0.0, pitch - _player.get_camera().get_parent_node_3d().rotation.x)
	await get_tree().physics_frame
	await get_tree().physics_frame
