extends GdUnitTestSuite
## "No ship engine event names a player" (GDD §8: the blast names nobody, the hologram shows
## where, not what; #1453), checked apart from the declarations: each event's to_dict() keys and
## its wire row's fields are held to a list written here, so a `peer` or a kind added to either
## fails this test even if its audience still says everyone. The wire's bound of one problem's
## stations is pinned to core's (net/ names no core/ class).

## Event -> the keys of its to_dict() and the fields of its wire row, in order.
const KEYS := {
	&"EngineProblemOpened": ["problem", "stations", "deadline"],
	&"EngineProblemFixed": ["problem"],
	&"EngineBlast": ["stage"],
	&"GillFlipped": ["station", "slit", "open"],
	&"BreakerChain": ["problem", "breakers", "next", "since"],
	&"CrystalChanged": ["station", "charger", "phase", "item", "tick"],
}


func test_each_engine_event_names_no_player_and_reaches_everyone() -> void:
	var samples: Array[MatchEvent] = [
		EngineProblemOpenedEvent.new(1, PackedInt32Array([2, 3]), 40),
		EngineProblemFixedEvent.new(1),
		EngineBlastEvent.new(1),
		GillFlippedEvent.new(1, 2, true),
		BreakerChainEvent.new(1, PackedInt32Array([3, 5]), 1, 40),
		CrystalChangedEvent.new(2, 4, CrystalProblem.CHARGING, 1, 200),
	]
	for event: MatchEvent in samples:
		var event_name := event.event_name()
		assert_array(event.to_dict().keys()).is_equal(KEYS[event_name])
		assert_int(event.audience().kind).is_equal(Audience.Kind.EVERYONE)


func test_each_engine_event_s_wire_row_carries_the_same_fields_and_no_peer() -> void:
	var schema := WireSchema.game(false)
	for row_name: StringName in KEYS:
		var row := schema.row_named(row_name)
		assert_object(row).override_failure_message("no wire row %s" % row_name).is_not_null()
		var names: Array = []
		for field: WireField in row.fields:
			names.append(field.name)
			assert_int(field.type).is_not_equal(WireField.Type.PEER)
		assert_array(names).is_equal(KEYS[row_name])


func test_the_wire_holds_as_many_stations_of_a_problem_as_the_engine_allows() -> void:
	assert_int(WireSchema.MAX_PROBLEM_STATIONS).is_equal(ShipEngine.MAX_PROBLEM_STATIONS)
