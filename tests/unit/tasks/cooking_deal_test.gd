extends GdUnitTestSuite
## Cooking's deal (the cooking ADR's §2.1, CE8, CE9, CE12, CD11 (a), CD13 (b); ARCHITECTURE §3.3,
## §9.5): the order board, the herb board and the grill on their markers, a bed on every bed marker,
## N places on the first N place markers, ids in that order; one box per box kind on a random marker
## of its tag; per place an order of a bun, a raw patty and a herb drawn independently; the code and
## the beds two permutations of the herbs; StationPlaced, ItemSpawned, OrderPosted, HerbsDealt to
## everyone in that order, then the task's TaskState and TaskProgress; each draw from its own
## purpose. With N = 0 nothing is dealt and the task is done; a short map deals nothing and says
## so. Driven on FixtureCookingModes; fixture values only.

const P1 := 1
const P2 := 2
const DEAL_EVENTS: Array[StringName] = [
	&"StationPlaced", &"ItemSpawned", &"OrderPosted", &"HerbsDealt", &"TaskState", &"TaskProgress"
]


func test_the_stations_stand_on_their_markers_in_the_deal_s_order() -> void:
	var game := _dealt(2)
	var task_state := FixtureCookingModes.state_of(game)
	var positions: Array[Vector3] = [
		FixtureCookingModes.ORDER_BOARD_AT,
		FixtureCookingModes.HERB_BOARD_AT,
		FixtureCookingModes.GRILL_AT,
	]
	positions.append_array(FixtureCookingModes.BED_SPOTS)
	positions.append_array(FixtureCookingModes.PLACE_SPOTS.slice(0, 2))
	var kinds: Array[StringName] = [&"order_board", &"herb_board", &"grill"]
	kinds.append_array([&"herb_bed", &"herb_bed", &"herb_bed", &"place", &"place"])
	var ids := game.state.stations.keys()
	ids.sort()
	assert_int(ids.size()).is_equal(positions.size())
	for i in ids.size():
		var station: StationState = game.state.stations[ids[i]]
		assert_object(station.position).is_equal(positions[i])
		assert_str(String(station.kind.id)).is_equal(String(kinds[i]))
	assert_int(task_state.order_board).is_equal(ids[0])
	assert_int(task_state.herb_board).is_equal(ids[1])
	assert_int(task_state.grill).is_equal(ids[2])
	assert_array(Array(task_state.beds)).is_equal(ids.slice(3, 6))
	var places: Array = []
	for order: Cooking.Order in task_state.orders:
		places.append(order.station)
	assert_array(places).is_equal(ids.slice(6, 8))
	assert_int(task_state.total()).is_equal(2)
	assert_int(task_state.done_count()).is_equal(0)
	assert_int(task_state.grill_item).is_equal(-1)


func test_one_box_per_box_kind_lies_on_a_marker_of_its_tag() -> void:
	var game := _dealt(1)
	var boxes := _boxes(game)
	var kinds: Array[StringName] = []
	for item: ItemState in boxes:
		kinds.append(item.kind.id)
		assert_bool(item.where == ItemState.Where.GROUND).is_true()
		var layout := FixtureCookingModes.layouts()[FixtureModes.MAP]
		assert_bool(Array(layout.positions(item.kind.spawn_tag)).has(item.position)).is_true()
	assert_array(kinds).is_equal(FixtureCookingModes.BOXES.keys())
	for peer: int in [P1, P2]:
		var spawned: Array[Dictionary] = []
		for event: Dictionary in FixtureCookingModes.dicts(game, peer, &"ItemSpawned"):
			if str(event["kind"]).begins_with("box_"):
				spawned.append(event)
		assert_int(spawned.size()).is_equal(boxes.size())
		for i in boxes.size():
			assert_int(spawned[i]["item"]).is_equal(boxes[i].id)
			assert_object(spawned[i]["position"]).is_equal(boxes[i].position)
			assert_bool(spawned[i].has("station")).is_false()


func test_each_order_is_posted_with_its_fried_patty_and_icon_never_its_herb() -> void:
	var game := _dealt(3)
	var type := FixtureCookingModes.type_of(game.mode)
	var task_state := FixtureCookingModes.state_of(game)
	assert_int(task_state.orders.size()).is_equal(3)
	for peer: int in [P1, P2]:
		var posted := FixtureCookingModes.dicts(game, peer, &"OrderPosted")
		assert_int(posted.size()).is_equal(3)
		for i in 3:
			var order := task_state.orders[i]
			assert_bool(type.buns.has(order.bun)).is_true()
			assert_bool(type.raw_patties.has(order.raw_patty)).is_true()
			assert_bool(type.herbs.has(order.herb)).is_true()
			(
				assert_dict(posted[i])
				. is_equal(
					{
						"station": order.station,
						"bun": order.bun.id,
						"patty": type.fried_of(order.raw_patty).id,
						"icon": task_state.code.find(order.herb),
					}
				)
			)
			for value: Variant in posted[i].values():
				for herb: ItemKind in type.herbs:
					assert_bool(str(value) == String(herb.id)).is_false()


func test_the_code_and_the_beds_are_permutations_of_the_herbs_sent_to_everyone() -> void:
	var game := _dealt(1)
	var type := FixtureCookingModes.type_of(game.mode)
	var task_state := FixtureCookingModes.state_of(game)
	var herbs := _sorted_ids(type.herbs)
	assert_array(_sorted_ids(task_state.code)).is_equal(herbs)
	assert_array(_sorted_ids(task_state.bed_herbs)).is_equal(herbs)
	for peer: int in [P1, P2]:
		var dealt := FixtureCookingModes.dicts(game, peer, &"HerbsDealt")
		assert_int(dealt.size()).is_equal(1)
		assert_array(Array(dealt[0]["code"] as PackedStringArray)).is_equal(
			Array(_ids(task_state.code))
		)
		assert_array(Array(dealt[0]["beds"] as PackedStringArray)).is_equal(
			Array(_ids(task_state.bed_herbs))
		)


func test_everyone_gets_the_stations_the_boxes_the_orders_the_herbs_then_the_task() -> void:
	var game := _dealt(2)
	var expected: Array[StringName] = []
	for i in 8:
		expected.append(&"StationPlaced")
	for i in FixtureCookingModes.BOXES.size():
		expected.append(&"ItemSpawned")
	expected.append_array([&"OrderPosted", &"OrderPosted", &"HerbsDealt"])
	expected.append_array([&"TaskState", &"TaskProgress"])
	for peer: int in [P1, P2]:
		assert_array(_deal_stream(game, peer)).is_equal(expected)
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_same_seed_deals_the_same_and_the_seed_moves_the_draws() -> void:
	assert_array(_deal_of(_dealt(3, 11))).is_equal(_deal_of(_dealt(3, 11)))
	assert_array(FixtureModes.describe(_dealt(3, 11))).is_equal(
		FixtureModes.describe(_dealt(3, 11))
	)
	var deals := {}
	for seed_value in 12:
		deals[str(_deal_of(_dealt(3, seed_value)))] = true
	assert_int(deals.size()).is_greater(1)


func test_each_draw_comes_from_its_own_purpose() -> void:
	# Renaming one purpose moves only its own draws: the boxes, the orders, the code, the beds.
	var parts := ["boxes", "orders", "code", "beds"]
	var purposes := {
		"boxes": "boxes_rng", "orders": "orders_rng", "code": "code_rng", "beds": "beds_rng"
	}
	for part: String in parts:
		var moved := false
		for seed_value in 8:
			var plain := _deal_of(_dealt(3, seed_value))
			var mode := FixtureCookingModes.basic(3)
			FixtureCookingModes.type_of(mode).set(
				StringName(purposes[part] as String), StringName("other_" + part)
			)
			var reshuffled := _deal_of(FixtureCookingModes.in_round(mode, [P1, P2], {}, seed_value))
			for i in parts.size():
				if parts[i] == part:
					moved = moved or str(reshuffled[i]) != str(plain[i])
				else:
					assert_str(str(reshuffled[i])).override_failure_message(part).is_equal(
						str(plain[i])
					)
		assert_bool(moved).override_failure_message(part).is_true()


func test_zero_burgers_deal_nothing_and_the_task_is_done() -> void:
	var game := _dealt(0)
	var task := FixtureCookingModes.task_of(game)
	assert_int(task.state.total()).is_equal(0)
	assert_bool(task.state.is_done()).is_true()
	assert_dict(game.state.stations).is_empty()
	assert_array(_boxes(game)).is_empty()
	assert_array(_deal_stream(game, P2)).is_equal([&"TaskState", &"TaskProgress"])
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_map_short_of_markers_deals_nothing_and_says_so() -> void:
	# The load check (LayoutCheck) refuses such a map, so the shortfall comes in after the start:
	# a setting above the place markers, then a fourth herb on a map of three beds.
	var short_places := _joined(FixtureCookingModes.basic(3))
	short_places.state.settings[&"burgers"] = 4
	FixtureModes.send(short_places, Intents.SET_READY, P1, {"ready": true})
	assert_str(short_places.phase_id()).is_equal("round")
	assert_int(short_places.state.tasks.size()).is_equal(0)
	assert_dict(short_places.state.stations).is_empty()
	assert_array(_boxes(short_places)).is_empty()
	assert_str(short_places.diagnostics[0]).contains(
		"Cooking: 4 burgers need 4 place markers, the map has 3"
	)
	assert_array(short_places.view_of(P1).events_named(&"OrderPosted")).is_empty()
	var mode := FixtureCookingModes.basic(1)
	var short_beds := _joined(mode)
	FixtureCookingModes.type_of(mode).herbs.append(FixtureCookingModes.ingredient(&"herb_d", true))
	FixtureModes.send(short_beds, Intents.SET_READY, P1, {"ready": true})
	assert_int(short_beds.state.tasks.size()).is_equal(0)
	assert_str(short_beds.diagnostics[0]).contains("4 herb_bed markers, the map has 3")


func test_reset_match_clears_the_deal_and_a_new_round_deals_afresh() -> void:
	var game := FixtureCookingModes.in_round(FixtureCookingModes.winning(2), [P1, P2])
	assert_int(FixtureCookingModes.state_of(game).orders.size()).is_equal(2)
	game.state.clock_ticks_left = 1
	FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("end")
	FixtureModes.send(game, Intents.RETURN_TO_LOBBY, P1)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_dict(game.state.tasks).is_empty()
	assert_dict(game.state.stations).is_empty()
	assert_array(_boxes(game)).is_empty()
	for peer: int in [P1, P2]:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_str(game.phase_id()).is_equal("round")
	assert_int(FixtureCookingModes.state_of(game).orders.size()).is_equal(2)
	assert_int(_boxes(game).size()).is_equal(FixtureCookingModes.BOXES.size())
	assert_array(Array(game.diagnostics)).is_empty()


## A round of the cooking fixture mode with `burgers` burgers, P1 and P2 joined.
func _dealt(burgers: int, seed_value: int = 7) -> Match:
	return FixtureCookingModes.in_round(
		FixtureCookingModes.basic(burgers), [P1, P2], {}, seed_value
	)


## A match of `mode` on the fixture layouts, P1 joined, still in the lobby.
func _joined(mode: GameMode) -> Match:
	var game := FixtureCookingModes.in_round(mode, [])
	FixtureModes.send(game, Intents.HELLO, P1, {"name": "p1"})
	return game


## The boxes lying in the match, in id order.
func _boxes(game: Match) -> Array[ItemState]:
	var ids := game.state.items.keys()
	ids.sort()
	var found: Array[ItemState] = []
	for id: int in ids:
		var item: ItemState = game.state.items[id]
		if String(item.kind.id).begins_with("box_"):
			found.append(item)
	return found


## The deal's draws, one entry per purpose: the boxes' positions, the orders, the code, the beds.
func _deal_of(game: Match) -> Array:
	var boxes: Array[Vector3] = []
	for item: ItemState in _boxes(game):
		boxes.append(item.position)
	var task_state := FixtureCookingModes.state_of(game)
	var orders: Array[String] = []
	for order: Cooking.Order in task_state.orders:
		orders.append("%s/%s/%s" % [order.bun.id, order.raw_patty.id, order.herb.id])
	return [boxes, orders, _ids(task_state.code), _ids(task_state.bed_herbs)]


## The deal's events `peer` received, in order, the boxes' ItemSpawned alone among the items'.
func _deal_stream(game: Match, peer: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: MatchEvent in game.view_of(peer).events:
		var event_name := event.event_name()
		if not event_name in DEAL_EVENTS:
			continue
		if event_name == &"ItemSpawned" and not str(event.to_dict()["kind"]).begins_with("box_"):
			continue
		found.append(event_name)
	return found


func _ids(kinds: Array[ItemKind]) -> PackedStringArray:
	var found := PackedStringArray()
	for kind: ItemKind in kinds:
		found.append(String(kind.id))
	return found


func _sorted_ids(kinds: Array[ItemKind]) -> Array:
	var found := Array(_ids(kinds))
	found.sort()
	return found
