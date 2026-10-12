extends GdUnitTestSuite
## "No car repair event names a player" (the car repair ADR §3: nobody is told who holds the lift
## or who let go; RE10), checked apart from the declarations: each event's to_dict() keys and its
## wire row's fields (an optional field's parts included) are held to a list written here, so a
## `peer` added to either fails this test even if its audience still says everyone. R3 (#807)
## adds LiftChanged and PartNeeded; R4 (#808) adds its own.

## Event -> the keys of its to_dict() and the fields of its wire row, in order.
const KEYS := {
	&"LiftChanged": ["station", "up", "tick"],
	&"PartNeeded": ["station", "kind"],
}


func test_each_car_repair_event_names_no_player() -> void:
	for event: MatchEvent in _samples():
		var event_name := event.event_name()
		var missing := "%s has no keys here" % event_name
		assert_bool(KEYS.has(event_name)).override_failure_message(missing).is_true()
		assert_array(event.to_dict().keys()).is_equal(KEYS[event_name])
		assert_int(event.audience().kind).is_equal(Audience.Kind.EVERYONE)


func test_each_car_repair_event_s_wire_row_carries_the_same_fields_and_no_peer() -> void:
	var schema := WireSchema.game(false)
	for row_name: StringName in KEYS:
		var row := schema.row_named(row_name)
		assert_object(row).override_failure_message("no wire row %s" % row_name).is_not_null()
		var names: Array = []
		for field: WireField in row.fields:
			var inner: Array[WireField] = [field]
			if field.type == WireField.Type.OPTIONAL:
				inner = field.parts
			for part: WireField in inner:
				names.append(part.name)
				assert_int(part.type).is_not_equal(WireField.Type.PEER)
		assert_array(names).is_equal(KEYS[row_name])


func _samples() -> Array[MatchEvent]:
	return [LiftChangedEvent.new(2, true, 40), PartNeededEvent.new(5, &"spark_plug")]
