extends GdUnitTestSuite
## Delivery by meaning's events over the real wire (the delivery-by-meaning ADR §7, DE7; #828): the
## host's StationPlaced, ItemSpawned and PackageDelivered of a dealt round, encoded and decoded by
## WireSchema as HostSession does, folded into a ClientModel. No bot carries this type's events
## over the wire (the bots play the greybox's Delivery by colours), so this is where a drop-off id
## or a white package colour that the codec mangles shows up.

const P1 := 1
const P2 := 2
## The House's drop-off ids (content/tasks/delivery.tres), the longest 18 characters.
const HOUSE_IDS: Array[StringName] = [
	&"drop_dining_table", &"drop_workbench", &"drop_garden", &"drop_terrace_table"
]
const CARRIED: Array[StringName] = [&"StationPlaced", &"ItemSpawned", &"PackageDelivered"]

var _schema: WireSchema
var _model: ClientModel
var _sent := 0
var _seen := 0


func before_test() -> void:
	_schema = WireSchema.game(false)
	_sent = 0
	_seen = 0


func test_two_items_on_one_drop_off_cross_the_wire_and_it_is_done_only_after_both() -> void:
	# N = 5 over 4 routes: one drop-off takes two items.
	var mode := FixtureMeaningModes.basic(5)
	var routes := FixtureMeaningModes.type_of(mode).routes
	for i in routes.size():
		routes[i].drop_off.id = HOUSE_IDS[i]
	var game := FixtureMeaningModes.in_round(mode, [P1, P2])
	_model = ClientModel.new(mode)
	var state := FixtureMeaningModes.state_of(game)
	var pair: Array[int] = []
	for i in state.total():
		for j in range(i + 1, state.total()):
			if state.stations[i] == state.stations[j]:
				pair = [i, j]
	assert_array(pair).has_size(2)
	var place := FixtureMeaningModes.station_of(game, pair[0])
	_send_new(game)
	# Every drop-off and item arrived as the host dealt it.
	assert_int(_model.stations.size()).is_equal(game.state.stations.size())
	for id: int in game.state.stations:
		var sent := game.state.stations[id]
		assert_str(String(_model.stations[id].kind)).is_equal(String(sent.kind.id))
		assert_vector(_model.stations[id].position).is_equal(sent.position)
		assert_bool(_model.stations[id].done).is_false()
	for i in state.total():
		var item := _model.items[state.items[i]]
		assert_str(String(item.kind)).is_equal(String(FixtureMeaningModes.item_of(game, i).kind.id))
		assert_int(item.station).is_equal(state.stations[i])
		assert_bool(item.colour == Color.WHITE).is_true()
	# The shared drop-off dims only after its second item.
	FixtureDeliveryModes.carry_to(
		game, P1, FixtureMeaningModes.item_of(game, pair[0]), place.position
	)
	_send_new(game)
	assert_bool(_model.items[state.items[pair[0]]].delivered).is_true()
	assert_bool(_model.stations[place.id].done).is_false()
	FixtureDeliveryModes.carry_to(
		game, P2, FixtureMeaningModes.item_of(game, pair[1]), place.position + Vector3(0, 0, 0.5)
	)
	_send_new(game)
	assert_bool(_model.items[state.items[pair[1]]].delivered).is_true()
	assert_bool(_model.stations[place.id].done).is_true()
	assert_int(_sent).is_equal(game.state.stations.size() + state.total() + 2)


## Encodes P2's new events of the carried kinds as HostSession._deliver does, decodes each and
## folds the decoded fields into the model.
func _send_new(game: Match) -> void:
	var events := game.view_of(P2).events
	for event: MatchEvent in events.slice(_seen):
		var event_name := event.event_name()
		if not CARRIED.has(event_name):
			continue
		var payload := _schema.encode(WireMessage.new(event_name, event.to_dict()))
		assert_int(payload.size()).override_failure_message(str(event_name)).is_greater(0)
		var kind := _schema.kind_of(event_name)
		var decoded := _schema.decode(kind, payload)
		(
			assert_object(decoded)
			. override_failure_message("%s: %s" % [event_name, _schema.explain(kind, payload)])
			. is_not_null()
		)
		if decoded == null:
			continue
		_model.fold(decoded.name, decoded.fields)
		_sent += 1
	_seen = events.size()
