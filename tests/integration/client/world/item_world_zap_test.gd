extends GdUnitTestSuite
## ItemWorld's wiring of the ship's zap (#1585; ShipZapScreen's suite has the flash and the notice):
## through the session's event, with a real local player and the crystal's mode as the client's own
## copy, the private ShipZapped reaches the flash, the own camera's shake and the HUD's notice.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")

var _world: Node3D
var _player: PlayerController
var _harness: Harness
var _items: ItemWorld


func before_test() -> void:
	AudioBuses.ensure()
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_items = ItemWorld.new()
	_world.add_child(_items)
	var avatars := AvatarViews.new()
	_world.add_child(avatars)
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.crystal()]
	_items.setup(_harness.session, FixtureEngineKindModes.of(kinds), avatars)
	_items.set_player(_player)


func after_test() -> void:
	_world.free()
	_harness.close()


func test_the_zap_starts_the_flash_the_shake_and_the_notice() -> void:
	await _world.call(&"frames", 2)
	assert_bool(_items.hud_local().zap_notice).is_false()
	assert_float(_items.zap.flash_alpha()).is_equal(0.0)
	_harness.session.event_received.emit(&"ShipZapped", {"peer": _harness.session.model.own_peer})
	assert_float(_items.zap.flash_alpha()).is_greater(0.0)
	assert_float(_player.shake_left()).is_equal(FixtureEngineKindModes.ZAP_FLASH_SECONDS)
	assert_bool(_items.hud_local().zap_notice).is_true()
