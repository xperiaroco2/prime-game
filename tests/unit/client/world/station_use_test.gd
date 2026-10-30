extends GdUnitTestSuite
## StationUse (client/world/station_use.gd; #801, ARCHITECTURE §4.7.54): which placed stations E
## offers, from the own ClientModel and the client's own copy of the mode only. A Generator's
## generator and switches until the charge is done; never with a two-handed item in the hand
## (HandNotTwoHanded); never a station of a type this client draws no view for; never by a
## switch's state; a station a phase places itself (StationTicks: the lobby's tap, #1408) by its
## Interact rule alone.

const G := preload("res://tests/fixtures/client/fixture_generator_client.gd")

var _model: ClientModel
var _mode: GameMode


func before_test() -> void:
	_mode = FixtureGeneratorModes.basic()
	_model = G.dealt(FixtureGeneratorModes.SWITCHES, _mode)


func test_the_generator_and_every_active_switch_are_offered_until_the_charge_is_done() -> void:
	assert_bool(StationUse.usable(_model, _mode, G.GENERATOR)).is_true()
	for i in FixtureGeneratorModes.SWITCHES:
		assert_bool(StationUse.usable(_model, _mode, G.FIRST_SWITCH + i)).is_true()
	G.charge(_model, FixtureGeneratorModes.NEEDED, false, 40)
	assert_bool(_model.stations[G.GENERATOR].done).is_true()
	assert_bool(StationUse.usable(_model, _mode, G.GENERATOR)).is_false()
	for i in FixtureGeneratorModes.SWITCHES:
		assert_bool(StationUse.usable(_model, _mode, G.FIRST_SWITCH + i)).is_false()


func test_a_station_the_model_does_not_know_is_never_offered() -> void:
	# A fixed switch is no station (GE14): nothing to name.
	assert_bool(StationUse.usable(_model, _mode, 99)).is_false()


func test_a_switchs_state_never_changes_the_offer() -> void:
	var id := G.FIRST_SWITCH
	var off := StationUse.usable(_model, _mode, id)
	G.switch_to(_model, 0, true)
	assert_bool(StationUse.usable(_model, _mode, id)).is_equal(off)
	G.switch_to(_model, 0, false)
	assert_bool(StationUse.usable(_model, _mode, id)).is_equal(off)


func test_a_two_handed_item_in_the_hand_offers_no_station() -> void:
	_model.fold(&"ItemSpawned", {"item": 50, "kind": &"package", "position": Vector3(0, 0, 19)})
	_model.fold(&"ItemPickedUp", {"peer": G.OWN, "item": 50})
	assert_int(_model.hand_item(G.OWN)).is_equal(50)
	assert_bool(StationUse.usable(_model, _mode, G.GENERATOR)).is_false()
	# A one-handed knife in the hand does not stop it.
	_model.fold(&"ItemPlaced", {"item": 50, "position": Vector3(0, 0, 19), "cause": Items.PUT_DOWN})
	_model.fold(&"ItemSpawned", {"item": 51, "kind": &"knife", "position": Vector3(0, 0, 19)})
	_model.fold(&"ItemPickedUp", {"peer": G.OWN, "item": 51})
	assert_int(_model.hand_item(G.OWN)).is_equal(51)
	assert_bool(StationUse.usable(_model, _mode, G.GENERATOR)).is_true()


func test_a_display_kind_or_one_with_no_interact_rule_is_never_offered() -> void:
	var type := FixtureGeneratorModes.type_of(_mode)
	type.switch.display = true
	assert_bool(StationUse.usable(_model, _mode, G.FIRST_SWITCH)).is_false()
	type.switch.display = false
	type.generator.actions = []
	assert_bool(StationUse.usable(_model, _mode, G.GENERATOR)).is_false()


func test_a_station_of_a_type_with_no_client_view_is_never_offered() -> void:
	# The station fixture's panel has the same use rule, but no client issue has drawn it yet.
	var mode := FixtureStationModes.basic()
	var model := ClientModel.new(mode)
	G.fold(model, StationPlacedEvent.new(1, &"panel", Color.ORANGE, Vector3.ZERO))
	assert_object(StationUse.rule_of(StationUse.kind_of(mode, &"panel"))).is_not_null()
	assert_bool(StationUse.usable(model, mode, 1)).is_false()


func test_the_generator_kinds_are_told_apart() -> void:
	assert_bool(StationUse.is_generator(_mode, &"generator")).is_true()
	assert_bool(StationUse.is_generator(_mode, &"switch")).is_false()
	assert_object(StationUse.generator_of(_mode, &"switch")).is_same(
		FixtureGeneratorModes.type_of(_mode)
	)
	assert_object(StationUse.generator_of(_mode, &"circle")).is_null()
	assert_int(StationUse.generator_station(_model, FixtureGeneratorModes.type_of(_mode))).is_equal(
		G.GENERATOR
	)


func test_a_station_a_phase_places_itself_is_offered_by_its_rule_alone() -> void:
	# The lobby's tap (StationTicks, #1408): no task type holds its kind, so no TaskClient owns it;
	# its Interact rule decides, a hand holding a mug or a two-handed package included (the rule has
	# no HandNotTwoHanded).
	var mode := FixtureBar.mode()
	var model := ClientModel.new(mode)
	model.own_peer = G.OWN
	G.fold(model, StationPlacedEvent.new(1, &"tap", Color.WHITE, FixtureBar.TAP))
	assert_object(Stations.owner_of(mode, StationUse.kind_of(mode, &"tap"))).is_null()
	assert_bool(StationUse.usable(model, mode, 1)).is_true()
	model.fold(&"ItemSpawned", {"item": 50, "kind": &"package", "position": FixtureBar.TAP})
	model.fold(&"ItemPickedUp", {"peer": G.OWN, "item": 50})
	assert_int(model.hand_item(G.OWN)).is_equal(50)
	assert_bool(StationUse.usable(model, mode, 1)).is_true()
	# Without its Interact rule it is not offered.
	StationUse.kind_of(mode, &"tap").actions = []
	assert_bool(StationUse.usable(model, mode, 1)).is_false()
