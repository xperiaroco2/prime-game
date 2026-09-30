extends GdUnitTestSuite
## The table checked against core/ (ARCHITECTURE §4.4): net/ names core/'s fields as strings, so
## this suite is what notices a drift. Every event class with a peer audience has a row whose
## fields are its to_dict() keys, every intent has a row, and core/'s constant ids fit the wire's
## id alphabet. The comparison of intents with Intents.FIELDS comes with #97.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const EVENTS_FOLDER := "res://core/events/"


func test_every_event_class_with_a_peer_audience_has_samples() -> void:
	var samples := Samples.events()
	var classes := _event_classes()
	assert_int(classes.size()).is_greater(20)
	for event_class: String in classes:
		var script := load(classes[event_class]) as Script
		var audience: Audience.Kind = script.get_script_constant_map()["AUDIENCE_KIND"]
		assert_bool(samples.has(event_class)).override_failure_message(event_class).is_equal(
			audience != Audience.Kind.SERVER
		)


## A directive reaches no peer (§4.3): a row named after one would let a by-name encode send it.
func test_no_server_audience_event_has_a_row() -> void:
	var schema := WireSchema.game(true)
	var directives := 0
	var classes := _event_classes()
	for event_class: String in classes:
		var script := load(classes[event_class]) as Script
		var audience: Audience.Kind = script.get_script_constant_map()["AUDIENCE_KIND"]
		if audience != Audience.Kind.SERVER:
			continue
		directives += 1
		assert_str(event_class).ends_with("Event")
		var row_name := StringName(event_class.trim_suffix("Event"))
		assert_object(schema.row_named(row_name)).override_failure_message(event_class).is_null()
	assert_int(directives).is_greater_equal(3)


func test_every_sent_event_has_a_row_with_its_to_dict_keys() -> void:
	var schema := WireSchema.game(false)
	for event_class: String in Samples.events():
		var names := {}
		var row: WireRow = null
		for event: MatchEvent in Samples.events()[event_class]:
			row = schema.row_named(event.event_name())
			assert_object(row).override_failure_message(event_class).is_not_null()
			if row == null:
				break
			for key: Variant in event.to_dict():
				names[str(key)] = true
				assert_bool(key is String).is_true()
			assert_bool(row.kind >= WireSchema.FIRST_EVENT).is_true()
			assert_bool(row.kind < WireSchema.FIRST_STATE).is_true()
		if row != null:
			(
				assert_array(Array(row.field_names()))
				. override_failure_message(event_class)
				. contains_exactly_in_any_order(names.keys())
			)


func test_every_intent_has_a_row_and_force_role_a_debug_row() -> void:
	var schema := WireSchema.game(true)
	for intent: StringName in Intents.ALL:
		var row := schema.row_named(intent)
		assert_object(row).override_failure_message(str(intent)).is_not_null()
		if row != null:
			assert_bool(row.kind < WireSchema.FIRST_DEBUG).is_true()
	var forced := schema.row_named(Intents.FORCE_ROLE)
	assert_int(forced.kind).is_between(WireSchema.FIRST_DEBUG, WireSchema.FIRST_EVENT - 1)
	for command: StringName in [Intents.PEER_CONNECTED, Intents.PEER_LEFT]:
		assert_object(schema.row_named(command)).is_null()


func test_cores_constant_ids_fit_the_wire() -> void:
	var ids: Array[String] = []
	for script: Script in [RejectReasons, CountdownCancelledEvent]:
		for value: Variant in script.get_script_constant_map().values():
			if value is StringName:
				ids.append(str(value))
	for cause: StringName in [Items.PUT_DOWN, Items.SWAP, Items.DEATH, Items.LEAVE, Items.SPAWN]:
		ids.append(str(cause))
	assert_int(ids.size()).is_greater(15)
	for id: String in ids:
		assert_bool(WireField.is_id(id)).override_failure_message(id).is_true()


func test_the_items_causes_are_every_string_name_constant_of_items() -> void:
	var causes: Array[String] = []
	var items: Script = Items
	for value: Variant in items.get_script_constant_map().values():
		if value is StringName:
			causes.append(str(value))
	assert_array(causes).contains_exactly_in_any_order(
		["put_down", "swap", "death", "leave", "spawn"]
	)


## Event class name -> script path, for every MatchEvent subclass in core/events/.
func _event_classes() -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = entry["path"]
		if path.begins_with(EVENTS_FOLDER) and entry["base"] == &"MatchEvent":
			found[str(entry["class"])] = path
	return found
