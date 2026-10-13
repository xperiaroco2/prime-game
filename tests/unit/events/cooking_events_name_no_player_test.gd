extends GdUnitTestSuite
## "No cooking event names a player" (the cooking ADR §7, §3's "Who did it"), checked apart from the
## declarations: each cooking event's to_dict() keys and its wire row's fields are held to a list
## written here, so a `peer` added to either fails this test even if its audience still says
## everyone. Each part adds its own events (C2, C3, C4, C10): ItemVanished is C10's (#779),
## ItemChanged C2's (#771), OrderPosted and HerbsDealt C3's (#772), GrillLoaded and
## IngredientPlaced C4's (#773).

## Event -> the keys of its to_dict() and the fields of its wire row, in order.
const KEYS := {
	&"ItemVanished": ["item"],
	&"ItemChanged": ["item", "kind"],
	&"OrderPosted": ["station", "bun", "patty", "icon"],
	&"HerbsDealt": ["code", "beds"],
	&"GrillLoaded": ["station", "item", "fried", "burnt"],
	&"IngredientPlaced": ["item", "station", "right"],
}


func test_each_cooking_event_names_no_player() -> void:
	for event: MatchEvent in _samples():
		var event_name := event.event_name()
		var missing := "%s has no keys here" % event_name
		assert_bool(KEYS.has(event_name)).override_failure_message(missing).is_true()
		assert_array(event.to_dict().keys()).is_equal(KEYS[event_name])
		assert_int(event.audience().kind).is_equal(Audience.Kind.EVERYONE)


func test_each_cooking_event_s_wire_row_carries_the_same_fields_and_no_peer() -> void:
	var schema := WireSchema.game(false)
	for row_name: StringName in KEYS:
		var row := schema.row_named(row_name)
		assert_object(row).override_failure_message("no wire row %s" % row_name).is_not_null()
		var names: Array = []
		for field: WireField in row.fields:
			names.append(field.name)
			assert_int(field.type).is_not_equal(WireField.Type.PEER)
		assert_array(names).is_equal(KEYS[row_name])


func _samples() -> Array[MatchEvent]:
	return [
		ItemVanishedEvent.new(7),
		ItemChangedEvent.new(7, &"patty_fried"),
		OrderPostedEvent.new(3, &"bun_white", &"patty_light", 1),
		HerbsDealtEvent.new(
			PackedStringArray(["mint", "dill"]), PackedStringArray(["dill", "mint"])
		),
		GrillLoadedEvent.new(4, 9, 220, 320),
		IngredientPlacedEvent.new(9, 5, true),
	]
