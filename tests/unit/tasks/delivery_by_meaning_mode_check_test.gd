extends GdUnitTestSuite
## DeliveryByMeaning's mode checks (#683's ADR DE13) and its station kinds (DE4): its drop-offs are
## the kinds every finder sees (ZE3, the markers' floor snap, the wire's budget).


func test_the_fixture_mode_passes() -> void:
	assert_array(Array(ModeCheck.run(FixtureMeaningModes.basic()).errors)).is_empty()


func test_no_routes_is_refused() -> void:
	var mode := FixtureMeaningModes.basic()
	FixtureMeaningModes.type_of(mode).routes = []
	_expect(mode, "DeliveryByMeaning delivery has no routes")


func test_a_route_without_an_item_or_a_drop_off_is_refused() -> void:
	var mode := FixtureMeaningModes.basic()
	var type := FixtureMeaningModes.type_of(mode)
	type.routes[1].item = null
	type.routes[2].drop_off = null
	_expect(mode, "DeliveryByMeaning delivery: route 1 has no item kind")
	_expect(mode, "DeliveryByMeaning delivery: route 2 has no drop-off")


func test_an_item_kind_the_mode_does_not_declare_is_refused() -> void:
	var mode := FixtureMeaningModes.basic()
	var stray := FixtureItemModes.item_kind(&"stray", [], 2)
	stray.spawn_tag = &"package"
	FixtureMeaningModes.type_of(mode).routes[0].item = stray
	_expect(
		mode,
		"DeliveryByMeaning delivery: route 0 names item kind stray, which the mode does not declare"
	)


func test_an_item_kind_with_no_spawn_tag_or_that_vanishes_is_refused() -> void:
	var mode := FixtureMeaningModes.basic()
	mode.find_item_kind(&"oil").spawn_tag = &""
	mode.find_item_kind(&"gnome").vanish_seconds = 30
	_expect(mode, "DeliveryByMeaning delivery: the item kind oil has no spawn_tag to place it on")
	_expect(mode, "DeliveryByMeaning delivery: the item kind gnome must not vanish")


func test_one_kind_in_two_routes_is_refused() -> void:
	var mode := FixtureMeaningModes.basic()
	var type := FixtureMeaningModes.type_of(mode)
	type.routes[3].item = type.routes[0].item
	_expect(mode, "DeliveryByMeaning delivery: item kind wine is in two routes")


func test_a_drop_off_sharing_an_item_tag_is_refused() -> void:
	var mode := FixtureMeaningModes.basic()
	FixtureMeaningModes.type_of(mode).routes[1].drop_off.spawn_tag = &"package"
	_expect(
		mode,
		"DeliveryByMeaning delivery: the drop-off drop_b and an item kind share spawn tag package"
	)


func test_a_palette_on_a_drop_off_is_refused() -> void:
	var mode := FixtureMeaningModes.basic()
	FixtureMeaningModes.type_of(mode).routes[2].drop_off.palette = PackedColorArray([Color.RED])
	_expect(mode, "DeliveryByMeaning delivery: the drop-off drop_c has a palette")


func test_an_empty_rng_purpose_is_refused() -> void:
	var mode := FixtureMeaningModes.basic()
	FixtureMeaningModes.type_of(mode).tasks_rng = &""
	_expect(mode, "DeliveryByMeaning delivery has an empty RNG purpose")


func test_its_station_kinds_are_its_drop_offs_each_once_in_routes_order() -> void:
	var mode := FixtureMeaningModes.basic()
	var type := FixtureMeaningModes.type_of(mode)
	# Two routes to one place: the place is listed once.
	type.routes[3].drop_off = type.routes[1].drop_off
	var ids: Array[StringName] = []
	for kind: StationKind in type.station_kinds():
		ids.append(kind.id)
	assert_array(ids).is_equal([&"drop_a", &"drop_b", &"drop_c"])
	assert_array(Stations.kinds_in(mode)).is_equal(type.station_kinds())
	assert_object(CircleViews.station_kind(mode, &"drop_c")).is_same(type.routes[2].drop_off)
	assert_array(type.item_spawn_tags()).is_equal([&"package"])
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_the_markers_of_its_drop_offs_snap_to_the_floor() -> void:
	var tags := MarkerReader.floor_tags_of(FixtureMeaningModes.basic())
	for tag: StringName in FixtureMeaningModes.DROP_OFFS:
		assert_bool(tags.has(tag)).is_true()


func test_ze3_sees_a_drop_off_tag_another_type_uses() -> void:
	var mode := FixtureMeaningModes.basic()
	var colour := FixtureDeliveryModes.delivery(mode.find_item_kind(&"package"))
	colour.id = &"colour_delivery"
	colour.circle.spawn_tag = &"drop_a"
	mode.task_types.append(colour)
	var errors := Array(ModeCheck.run(mode).errors)
	var found := false
	for error: String in errors:
		found = found or (error.contains("share spawn tag drop_a"))
	assert_bool(found).override_failure_message(str(errors)).is_true()


func test_the_wire_budget_sizes_station_placed_by_its_longest_drop_off_id() -> void:
	var mode := FixtureMeaningModes.basic()
	var longest := StringName("drop_" + "x".repeat(27))
	FixtureMeaningModes.type_of(mode).routes[2].drop_off.id = longest
	var placed: WireMessage = null
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"StationPlaced":
			placed = message
	assert_object(placed).is_not_null()
	assert_str(str(placed.fields["kind"])).is_equal(String(longest))


func _expect(mode: GameMode, message: String) -> void:
	var errors := Array(ModeCheck.run(mode).errors)
	var found := false
	for error: String in errors:
		found = found or error.ends_with(message)
	assert_bool(found).override_failure_message("%s not in %s" % [message, errors]).is_true()
