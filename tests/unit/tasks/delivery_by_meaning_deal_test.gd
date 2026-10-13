extends GdUnitTestSuite
## DeliveryByMeaning's deal (#683's ADR §2.1, DD2 (a), DE3, DE5 (b), DE6; ARCHITECTURE §3.3,
## §9.5.24): the routes shuffled, every route an item before any has two, one station per drop-off
## in use in `routes` order, the items by tag then the markers' level order, everything white.

const P1 := 1
const P2 := 2


func test_every_route_gets_an_item_before_any_gets_a_second() -> void:
	var order := PackedInt32Array([2, 0, 3, 1])
	assert_array(Array(DeliveryByMeaning.counts(4, order))).is_equal([1, 1, 1, 1])
	assert_array(Array(DeliveryByMeaning.counts(3, order))).is_equal([1, 0, 1, 1])
	assert_array(Array(DeliveryByMeaning.counts(1, order))).is_equal([0, 0, 1, 0])
	assert_array(Array(DeliveryByMeaning.counts(6, order))).is_equal([2, 1, 2, 1])
	assert_array(Array(DeliveryByMeaning.counts(10, order))).is_equal([3, 2, 3, 2])
	assert_array(Array(DeliveryByMeaning.counts(0, order))).is_equal([0, 0, 0, 0])


func test_n_equal_to_the_routes_deals_one_item_per_route_and_every_place() -> void:
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(4), [P1, P2])
	assert_str(game.phase_id()).is_equal("round")
	assert_array(Array(game.diagnostics)).is_empty()
	assert_int(game.state.tasks.size()).is_equal(1)
	var task := FixtureMeaningModes.task_of(game)
	assert_int(task.state.total()).is_equal(4)
	assert_int(task.state.done_count()).is_equal(0)
	# Station ids follow `routes`: drop_a is 1, drop_d is 4, whatever the shuffle.
	assert_array(_station_kinds(game)).is_equal(Array(FixtureMeaningModes.DROP_OFFS))
	var kinds: Array[String] = []
	for id: int in game.state.items:
		kinds.append(String(game.state.items[id].kind.id))
	kinds.sort()
	assert_array(kinds).is_equal(["gnome", "oil", "parasol", "wine"])
	_assert_bound_to_routes(game)


func test_station_ids_follow_the_routes_and_only_the_places_in_use_stand() -> void:
	# N below K: the routes drawn first get an item; the others no station. Over several seeds the
	# shuffle differs, the station ids still ascend in routes order.
	var orders := {}
	for seed_value in range(1, 9):
		var game := FixtureMeaningModes.in_round(
			FixtureMeaningModes.basic(2), [P1, P2], {}, seed_value
		)
		assert_int(game.state.items.size()).is_equal(2)
		assert_int(game.state.stations.size()).is_equal(2)
		assert_array(game.view_of(P1).events_named(&"StationPlaced")).has_size(2)
		var used := _station_kinds(game)
		var last := -1
		for kind: StringName in used:
			var at := FixtureMeaningModes.DROP_OFFS.find(kind)
			assert_int(at).is_greater(last)
			last = at
		orders[str(used)] = true
		_assert_bound_to_routes(game)
	# The draw is a draw: not the same two places every time.
	assert_int(orders.size()).is_greater(1)


func test_n_above_the_routes_spreads_the_items_evenly() -> void:
	for n: int in [6, 10]:
		var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(n), [P1, P2])
		assert_int(game.state.items.size()).is_equal(n)
		assert_int(game.state.stations.size()).is_equal(4)
		var per_kind := {}
		for id: int in game.state.items:
			var kind := game.state.items[id].kind.id
			per_kind[kind] = (per_kind.get(kind, 0) as int) + 1
		var counts: Array = per_kind.values()
		counts.sort()
		@warning_ignore("integer_division")
		var each := n / 4
		var expected: Array = []
		for p in 4:
			expected.append(each + (1 if p >= 4 - n % 4 else 0))
		assert_array(counts).is_equal(expected)
		_assert_bound_to_routes(game)


func test_no_items_deal_a_done_task_and_nothing_else() -> void:
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(0), [P1, P2])
	assert_int(game.state.tasks.size()).is_equal(1)
	var task := FixtureMeaningModes.task_of(game)
	assert_int(task.state.total()).is_equal(0)
	assert_bool(task.state.is_done()).is_true()
	assert_int(game.state.stations.size()).is_equal(0)
	assert_int(game.state.items.size()).is_equal(0)
	assert_array(game.view_of(P1).events_named(&"StationPlaced")).is_empty()
	assert_array(game.view_of(P1).events_named(&"ItemSpawned")).is_empty()


func test_item_ids_follow_the_tags_in_routes_order_then_the_markers_level_order() -> void:
	var game := FixtureMeaningModes.in_round(
		FixtureMeaningModes.basic(4, true), [P1, P2], FixtureMeaningModes.layouts(10, 10)
	)
	assert_array(Array(game.diagnostics)).is_empty()
	var state := FixtureMeaningModes.state_of(game)
	# Subtask i is the i-th item in id order.
	assert_array(Array(state.items)).is_equal([1, 2, 3, 4])
	var tags: Array[StringName] = []
	for id: int in game.state.items:
		tags.append(game.state.items[id].kind.spawn_tag)
	# The `package` tag (wine's, the first route) before the `crate` tag.
	assert_array(tags).is_equal([&"package", &"package", &"crate", &"crate"])
	assert_bool(game.state.items[1].position.x < game.state.items[2].position.x).is_true()
	assert_bool(game.state.items[3].position.x < game.state.items[4].position.x).is_true()
	assert_float(game.state.items[3].position.z).is_equal(-40.0)
	_assert_bound_to_routes(game)


func test_everyone_sees_the_places_then_the_items_in_id_order_all_white() -> void:
	var game := FixtureMeaningModes.in_round(FixtureMeaningModes.basic(6), [P1, P2])
	var state := FixtureMeaningModes.state_of(game)
	for peer: int in [P1, P2]:
		var view := game.view_of(peer)
		var placed := view.events_named(&"StationPlaced")
		var spawned := view.events_named(&"ItemSpawned")
		assert_array(placed).has_size(4)
		assert_array(spawned).has_size(6)
		for i in 4:
			var station := game.state.stations[i + 1]
			assert_dict(placed[i].to_dict()).is_equal(
				{
					"station": station.id,
					"kind": station.kind.id,
					"colour": Color(1, 1, 1),
					"position": station.position
				}
			)
		for i in 6:
			var item := game.state.items[state.items[i]]
			assert_dict(spawned[i].to_dict()).is_equal(
				{
					"item": item.id,
					"kind": item.kind.id,
					"position": item.position,
					"station": state.stations[i],
					"colour": Color(1, 1, 1)
				}
			)
		var names := view.event_names()
		assert_int(names.rfind(&"StationPlaced")).is_less(names.find(&"ItemSpawned"))
		assert_int(names.find(&"TaskProgress")).is_greater(names.rfind(&"ItemSpawned"))
		assert_dict(view.events_named(&"TaskProgress")[0].to_dict()).is_equal(
			{"done": 0, "total": 6}
		)


func test_a_map_short_of_markers_deals_nothing_and_logs_a_match_error() -> void:
	var short_items := FixtureMeaningModes.in_round(
		FixtureMeaningModes.basic(4), [P1, P2], FixtureMeaningModes.layouts(3)
	)
	assert_int(short_items.state.tasks.size()).is_equal(0)
	assert_int(short_items.state.items.size()).is_equal(0)
	assert_int(short_items.state.stations.size()).is_equal(0)
	assert_int(short_items.diagnostics.size()).is_equal(1)
	var no_place := FixtureModes.layouts()
	var map := no_place[FixtureModes.MAP]
	for j in 3:
		map.add_marker(FixtureMeaningModes.DROP_OFFS[j], Vector3(20 * j, 0, 20))
	for i in 10:
		map.add_marker(&"package", Vector3(10 * i, 0, -20))
	# A map with no marker of a drop-off is refused before any deal: exactly one per tag (GE10).
	var missing := Match.new(FixtureMeaningModes.basic(4), 7, FlatWorldQuery.new(), no_place)
	assert_array(Array(missing.refusals)).is_equal(
		["fixture://map has 0 drop_d marker(s), and the row lobby, all_ready needs exactly 1"]
	)


func test_an_item_that_spawns_inside_its_own_place_is_delivered_at_once() -> void:
	var mode := FixtureMeaningModes.basic(1)
	var type := FixtureMeaningModes.type_of(mode)
	type.routes = [type.routes[0]]
	var found := FixtureModes.layouts()
	found[FixtureModes.MAP].add_marker(&"drop_a", Vector3(3, 0, 3))
	found[FixtureModes.MAP].add_marker(&"package", Vector3(3.5, 0, 3))
	var game := FixtureMeaningModes.in_round(mode, [P1], found)
	assert_int(game.state.items[1].where).is_equal(ItemState.Where.LOCKED)
	assert_bool(game.state.stations[1].done).is_true()
	assert_bool(FixtureMeaningModes.task_of(game).state.is_done()).is_true()
	var names := game.view_of(P1).event_names()
	var spawned := names.find(&"ItemSpawned")
	assert_array(names.slice(spawned, spawned + 4)).is_equal(
		[&"ItemSpawned", &"PackageDelivered", &"TaskState", &"TaskProgress"]
	)


func test_the_same_seed_deals_the_same_and_each_draw_has_its_purpose() -> void:
	var mode := FixtureMeaningModes.basic(6)
	var first := FixtureMeaningModes.in_round(mode, [P1, P2], {}, 11)
	var again := FixtureMeaningModes.in_round(mode, [P1, P2], {}, 11)
	assert_array(FixtureModes.describe(again)).is_equal(FixtureModes.describe(first))
	# Another packages purpose moves the items; the places, one marker each, stay.
	var other_mode := FixtureMeaningModes.basic(6)
	FixtureMeaningModes.type_of(other_mode).packages_rng = &"other_packages"
	var second := FixtureMeaningModes.in_round(other_mode, [P1, P2], {}, 11)
	assert_array(_station_kinds(second)).is_equal(_station_kinds(first))
	assert_array(_item_spots(second)).is_not_equal(_item_spots(first))


## The kind ids of the stations, in id order.
func _station_kinds(game: Match) -> Array:
	var found: Array = []
	for id: int in game.state.stations:
		found.append(game.state.stations[id].kind.id)
	return found


func _item_spots(game: Match) -> Array:
	var found: Array = []
	for id: int in game.state.items:
		found.append([game.state.items[id].kind.id, game.state.items[id].position])
	return found


## Each subtask's item, in id order, is bound to the drop-off of its kind's route.
func _assert_bound_to_routes(game: Match) -> void:
	var state := FixtureMeaningModes.state_of(game)
	var last := 0
	for i in state.total():
		assert_int(state.items[i]).is_greater(last)
		last = state.items[i]
		var kind := FixtureMeaningModes.item_of(game, i).kind.id
		var drop := FixtureMeaningModes.DROP_OFFS[FixtureMeaningModes.KINDS.find(kind)]
		assert_str(String(FixtureMeaningModes.station_of(game, i).kind.id)).is_equal(String(drop))
