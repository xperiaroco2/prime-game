extends GdUnitTestSuite
## DeliveryByMeaning's demands (#683's ADR DE6, GE10; ARCHITECTURE §9.4, §9.5.24) and its map
## (DE9, `TaskType.maps`): exactly one marker per drop-off tag, per item tag the most items a draw
## can put there, no colours; a map the type does not list asks none of its markers and deals it
## not.

const OTHER_MAP := "fixture://other_map"


func test_one_shared_tag_asks_n_items_and_exactly_one_marker_per_place() -> void:
	var mode := FixtureMeaningModes.basic()
	var demands := Demands.new(mode)
	FixtureMeaningModes.type_of(mode).add_demands({&"packages": 6}, 10, demands)
	assert_dict(demands.markers).is_equal(
		{&"drop_a": 1, &"drop_b": 1, &"drop_c": 1, &"drop_d": 1, &"package": 6}
	)
	assert_dict(demands.exact).is_equal(
		{&"drop_a": true, &"drop_b": true, &"drop_c": true, &"drop_d": true}
	)
	assert_dict(demands.colours).is_empty()


func test_two_tags_ask_what_a_draw_can_put_on_each() -> void:
	var mode := FixtureMeaningModes.basic(4, true)
	var type := FixtureMeaningModes.type_of(mode)
	# r = 2 routes per tag, K = 4: min(N, 2 * floor(N / 4) + min(2, N mod 4)).
	for case: Array in [[1, 1], [2, 2], [3, 2], [4, 2], [5, 3], [6, 4], [7, 4], [10, 6]]:
		var demands := Demands.new(mode)
		type.add_demands({&"packages": case[0] as int}, 2, demands)
		assert_int(demands.markers[&"package"]).is_equal(case[1] as int)
		assert_int(demands.markers[&"crate"]).is_equal(case[1] as int)


func test_no_items_ask_nothing() -> void:
	var mode := FixtureMeaningModes.basic()
	var demands := Demands.new(mode)
	FixtureMeaningModes.type_of(mode).add_demands({&"packages": 0}, 4, demands)
	assert_dict(demands.markers).is_empty()
	assert_dict(demands.exact).is_empty()


func test_a_second_marker_of_a_place_is_a_shortfall() -> void:
	var mode := FixtureMeaningModes.basic()
	var demands := Demands.new(mode)
	FixtureMeaningModes.type_of(mode).add_demands({&"packages": 4}, 4, demands)
	var layout := FixtureMeaningModes.layouts()[FixtureModes.MAP]
	assert_array(demands.shortfalls(layout)).is_empty()
	layout.add_marker(&"drop_b", Vector3(5, 0, 40))
	var found := demands.shortfalls(layout)
	assert_array(found).has_size(1)
	assert_str(String(found[0].id)).is_equal(String(HostText.MARKERS_EXACT))


func test_each_delivery_deals_and_asks_only_on_its_own_map() -> void:
	var mode := _two_maps()
	var meaning := FixtureMeaningModes.type_of(mode)
	var colour := mode.find_task_type(&"colour_delivery")
	assert_bool(meaning.plays_on(FixtureModes.MAP)).is_true()
	assert_bool(meaning.plays_on(OTHER_MAP)).is_false()
	assert_bool(colour.plays_on(OTHER_MAP)).is_true()
	assert_bool(colour.plays_on(FixtureModes.MAP)).is_false()
	assert_array(DealTasks.pool_of(mode, PackedStringArray(), FixtureModes.MAP)).is_equal([meaning])
	assert_array(DealTasks.pool_of(mode, PackedStringArray(), OTHER_MAP)).is_equal([colour])
	var deal := FixtureDealModes.deal_tasks()
	var settings: Dictionary[StringName, int] = {&"tasks": 1, &"packages": 3}
	var here := Demands.new(mode, FixtureModes.MAP)
	deal.add_demands(settings, 2, here)
	assert_dict(here.markers).is_equal(
		{&"drop_a": 1, &"drop_b": 1, &"drop_c": 1, &"drop_d": 1, &"package": 3}
	)
	assert_dict(here.colours).is_empty()
	var there := Demands.new(mode, OTHER_MAP)
	deal.add_demands(settings, 2, there)
	assert_dict(there.markers).is_equal({&"circle": 3, &"package": 3})
	assert_dict(there.colours).is_equal({&"circle": 3})


func test_the_match_on_its_map_deals_delivery_by_meaning_alone() -> void:
	var found := FixtureMeaningModes.layouts()
	found[OTHER_MAP] = FixtureDeliveryModes.layouts()[FixtureModes.MAP]
	var game := FixtureMeaningModes.in_round(_two_maps(), [1, 2], found)
	assert_array(Array(game.refusals)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()
	assert_int(game.state.tasks.size()).is_equal(1)
	assert_object(FixtureMeaningModes.task_of(game)).is_not_null()


## The fixture mode with a second map, on which today's Delivery (id `colour_delivery`) plays alone,
## and DeliveryByMeaning on the fixture map alone.
func _two_maps() -> GameMode:
	var mode := FixtureMeaningModes.basic(3)
	mode.maps.append(OTHER_MAP)
	var meaning := FixtureMeaningModes.type_of(mode)
	meaning.maps = PackedStringArray([FixtureModes.MAP])
	var colour := FixtureDeliveryModes.delivery(mode.find_item_kind(&"package"))
	colour.id = &"colour_delivery"
	colour.maps = PackedStringArray([OTHER_MAP])
	mode.task_types.append(colour)
	return mode
