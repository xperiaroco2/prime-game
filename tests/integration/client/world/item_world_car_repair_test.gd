extends GdUnitTestSuite
## ItemWorld's HUD numbers for the car repair (#811, ARCHITECTURE §4.7.56): the raise bar
## (`HudText.Local.raising`) shows the own fit at the car from FitChanged's tick and the client's
## copy of the fit's seconds, only while the own player is the car's fitter; another fitter, no
## fitter and a stopped fit show nothing (-1); a running raise shows instead (the larger wins, the
## two never run at once). The model is a real ClientSession's, fed off the loopback wire.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")

const CAR := 1
const START := 500

var _harness: Harness
var _items: ItemWorld
var _ticks := 0


func before_test() -> void:
	AudioBuses.ensure()
	_harness = Harness.new()
	_harness.welcome(&"round")
	var mode := FixtureCarRepairModes.basic()
	_ticks = CarRepairUse.fit_ticks(FixtureCarRepairModes.type_of(mode))
	_items = ItemWorld.new()
	add_child(_items)
	var avatars := AvatarViews.new()
	_items.add_child(avatars)
	_items.setup(_harness.session, mode, avatars)
	_items.interactions.reads_device_input = false
	_send(StationPlacedEvent.new(CAR, &"car", Color.WHITE, FixtureCarRepairModes.CAR_AT))


func after_test() -> void:
	_items.free()
	_harness.close()


func test_the_own_fit_fills_the_raise_bar() -> void:
	assert_int(_ticks).is_greater(1)
	assert_float(_items.hud_local(START).raising).is_equal(-1.0)
	_send(FitChangedEvent.new(CAR, _own(), START))
	assert_float(_items.hud_local(START).raising).is_equal_approx(0.0, 1e-6)
	var half := START + _ticks / 2.0
	assert_float(_items.hud_local(half).raising).is_equal_approx(0.5, 1e-6)
	assert_float(_items.hud_local(START + _ticks + 3).raising).is_equal_approx(1.0, 1e-6)
	_send(FitChangedEvent.new(CAR, 0, START + 4))
	assert_float(_items.hud_local(half).raising).is_equal(-1.0)


func test_another_player_s_fit_shows_nothing() -> void:
	_send(FitChangedEvent.new(CAR, _own() + 1, START))
	assert_float(_items.hud_local(START + _ticks / 2.0).raising).is_equal(-1.0)
	assert_float(_items.fit_shown(START + _ticks / 2.0)).is_equal(-1.0)


func test_a_raise_shows_when_no_fit_runs() -> void:
	assert_float(_items.hud_local(START, 0.25).raising).is_equal_approx(0.25, 1e-6)
	_send(FitChangedEvent.new(CAR, _own(), START))
	var quarter := START + _ticks / 4.0
	assert_float(_items.hud_local(quarter, -1.0).raising).is_equal_approx(0.25, 1e-6)
	assert_float(_items.hud_local(quarter).raising).is_equal_approx(0.25, 1e-6)


func _own() -> int:
	return _harness.session.model.own_peer


func _send(event: MatchEvent) -> void:
	_harness.send(event)
	_harness.deliver()
