extends GdUnitTestSuite
## A player who joins the lobby after the others took, stashed and put down items learns them from
## its Welcome (ARCHITECTURE §3.5, §4.2, #1404): over a LoopbackHub with a fake clock
## (host_session_harness.gd), the host's own client puts one item down and carries two (hand and
## belt), a station holds a locked one; a joiner's decoded Welcome and its model hold each as the
## host does, its later events name only items it knows, and it decodes what view_of its peer
## holds. Only the joiner gets the Welcome.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const OWN := 1
const STATION_AT := Vector3(3, 0, -3)

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_joiner_sees_the_items_put_down_carried_and_locked_before_it_came() -> void:
	_h = Harness.new(FixtureLobbyHands.with_hands(Harness.fixture_mode()))
	assert_bool(_h.started).is_true()
	_h.pump_frames(4)
	var game := _h.session.game
	var put := _take(_lay())
	assert_int(_h.own.send_intent(Intents.PUT_DOWN, {"facing": Vector3.FORWARD})).is_greater(0)
	_h.pump_frames(6)
	var belted := _take(_lay())
	var held := _take(_lay())
	var locked := _locked_at_a_station()
	assert_array(_h.own.view.events_named(&"Rejected")).is_empty()
	assert_int(game.state.items[put.id].where).is_equal(ItemState.Where.GROUND)
	assert_int(game.state.items[belted.id].where).is_equal(ItemState.Where.BELT)
	assert_int(game.state.items[held.id].where).is_equal(ItemState.Where.HAND)
	var joiner := _h.join()
	_h.pump_frames(6)
	var welcomes := joiner.view.events_named(&"Welcome")
	assert_int(welcomes.size()).is_equal(1)
	assert_int(_h.own.view.events_named(&"Welcome").size()).is_equal(1)
	var rows: Array = welcomes[0].fields["items"]
	assert_int(rows.size()).is_equal(4)
	var model := joiner.model
	assert_array(model.items.keys()).contains_exactly_in_any_order(
		[put.id, belted.id, held.id, locked.id]
	)
	assert_int(model.hand_item(OWN)).is_equal(held.id)
	assert_int(model.belt_item(OWN)).is_equal(belted.id)
	assert_int(model.selected_place(OWN)).is_equal(game.state.player(OWN).selected_place)
	assert_int(model.item_in_place(OWN, model.selected_place(OWN))).is_equal(held.id)
	assert_bool(model.items[put.id].rests()).is_true()
	assert_vector(model.items[put.id].position).is_equal(game.state.items[put.id].position)
	assert_bool(model.items[locked.id].rests()).is_true()
	assert_bool(model.items[locked.id].locked).is_true()
	assert_vector(model.items[locked.id].position).is_equal(STATION_AT)
	for id: int in model.items:
		assert_str(String(model.items[id].kind)).is_equal("tool")
	# The station that holds the locked item, replayed after the Welcome.
	assert_int(model.stations.size()).is_equal(1)
	var station: ClientModel.Station = model.stations.values()[0]
	assert_vector(station.position).is_equal(STATION_AT)
	# A later take of the put-down item names one the joiner knows: it is in the own hand now.
	_take(game.state.items[put.id])
	assert_int(game.state.items[put.id].where).is_equal(ItemState.Where.HAND)
	assert_array(game.view_of(joiner.model.own_peer).events_named(&"ItemPickedUp")).has_size(1)
	assert_int(model.items[put.id].holder).is_equal(OWN)
	assert_int(model.hand_item(OWN)).is_equal(put.id)
	assert_array(_h.mismatches(joiner)).is_empty()
	assert_int(_h.session.bad_payloads).is_equal(0)


## A tool lying at the own player's feet, straight into the host's state (no event: the own client
## takes it by id at once).
func _lay() -> ItemState:
	var at := _h.session.game.state.player(OWN).position + Vector3(0, 0, -0.5)
	return FixtureItemModes.lay(_h.session.game, &"tool", at)


## The own client takes `item` over the wire.
func _take(item: ItemState) -> ItemState:
	assert_int(_h.own.send_intent(Intents.PICK_UP, {"item": item.id})).is_greater(0)
	_h.pump_frames(6)
	return item


## A tool locked at a placed station, as Items.lock_at leaves it; no lobby rule does this today.
func _locked_at_a_station() -> ItemState:
	var game := _h.session.game
	var kind := StationKind.new()
	kind.id = &"bar"
	game.state.add_station(kind, STATION_AT, Color.WHITE)
	var item := FixtureItemModes.lay(game, &"tool", STATION_AT)
	Items.lock(item)
	return item
