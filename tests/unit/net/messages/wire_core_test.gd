extends GdUnitTestSuite
## The table checked against core/ (ARCHITECTURE §4.4): net/ names core/'s fields as strings, so
## this suite is what notices a drift. Every event class with a peer audience has a row whose
## fields are its to_dict() keys; every intent's row, and ForceRole's debug row, carries the fields
## Intents.FIELDS declares with their Variant types; core/'s constant ids fit the wire's id
## alphabet; and a decoded ForceRole and Hello, turned into MatchCommands, do in a Match what
## core/ means them to.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const EVENTS_FOLDER := "res://core/events/"
## The wire's own fields (§4.4): the payload never holds them, so no intent declares them.
## ForceRole's `peer` becomes MatchCommand.peer and is allowed on its row only.
const WIRE_ONLY: Array[String] = ["seq", "has_map", "has_station", "has_role"]
const CONTENT := Samples.CONTENT_HASH
## A map path the wire accepts (a `res://` path): the fixture maps' `fixture://` paths do not.
const WIRE_MAP := "res://levels/maps/fixture_wire_map.tscn"


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


## §4.4: a field renamed on one side (a wire `jumps` against a rule reading `jumped`) would read as
## absent, so each row's fields, flags and guarded parts must be the declared names and types.
func test_every_intent_row_carries_the_fields_intents_declares_with_their_types() -> void:
	var expected: Array[StringName] = Intents.ALL.duplicate()
	expected.append(Intents.FORCE_ROLE)
	assert_array(Intents.FIELDS.keys()).contains_exactly_in_any_order(expected)
	var schema := WireSchema.game(true)
	for intent: StringName in Intents.FIELDS:
		var row := schema.row_named(intent)
		assert_object(row).override_failure_message(str(intent)).is_not_null()
		if row == null:
			continue
		var declared: Dictionary = Intents.FIELDS[intent]
		var drift := _type_drift(_arg_types(row.fields), declared)
		assert_str(drift).override_failure_message("%s: %s" % [intent, drift]).is_empty()
		var allowed: Array[String] = WIRE_ONLY.duplicate()
		if intent == Intents.FORCE_ROLE:
			allowed.append("peer")
		for wire_only: String in _wire_only(row.fields):
			(
				assert_array(allowed)
				. override_failure_message("%s: wire-only field %s" % [intent, wire_only])
				. contains([wire_only])
			)


## The decoder's output, not only the table's declaration, has the declared Variant types: a
## String role, an int content hash, bools for MoveClaim's flags.
func test_decoded_intents_hold_the_declared_variant_types() -> void:
	var schema := WireSchema.game(true)
	var messages := Samples.intents()
	messages.append_array(Samples.debug_commands())
	for message: WireMessage in messages:
		var decoded := schema.decode(schema.kind_of(message.name), schema.encode(message))
		assert_object(decoded).override_failure_message(str(message.name)).is_not_null()
		if decoded == null:
			continue
		var declared: Dictionary = Intents.FIELDS[message.name]
		for key: Variant in decoded.fields:
			var where := "%s.%s" % [message.name, key]
			assert_bool(declared.has(key)).override_failure_message(where).is_true()
			var type: Variant.Type = declared.get(key, TYPE_NIL)
			(
				assert_str(type_string(typeof(decoded.fields[key])))
				. override_failure_message(where)
				. is_equal(type_string(type))
			)


func test_the_join_refusals_of_3e_are_reject_reasons_that_fit_the_wire() -> void:
	assert_str(str(RejectReasons.WRONG_CONTENT)).is_equal("wrong_content")
	assert_str(str(RejectReasons.JOINS_CLOSED)).is_equal("joins_closed")
	var schema := WireSchema.game(false)
	for reason: StringName in [RejectReasons.WRONG_CONTENT, RejectReasons.JOINS_CLOSED]:
		assert_bool(WireField.is_id(str(reason))).override_failure_message(reason).is_true()
		var sent := RejectedEvent.new(2, 0xFFFFFFFF, reason).to_dict()
		var payload := schema.encode(WireMessage.new(&"Rejected", sent))
		var decoded := schema.decode(WireSchema.REJECTED, payload)
		assert_object(decoded).override_failure_message(reason).is_not_null()
		if decoded != null:
			(
				assert_bool(Samples.same(decoded.fields, sent))
				. override_failure_message(reason)
				. is_true()
			)


## ForceRole's role decodes as a String because Match._force_role reads it with get_string, which
## gives "" (clear the role) for a StringName: this decodes the debug row, turns it into the
## MatchCommand server/ will make (the player as the command's peer), and deals.
func test_a_decoded_force_role_forces_the_role_in_a_match() -> void:
	var schema := WireSchema.game(true)
	var sent := WireMessage.new(&"ForceRole", {"role": "dissident"}, 1, 3)
	var peers: Array[int] = [1, 2, 3]
	for seed_value: int in [1, 2, 3, 7]:
		var game := _deal_lobby(peers, seed_value)
		var forced := _decoded(schema, sent)
		if forced == null:
			return
		assert_int(forced.peer).is_equal(3)
		game.apply(_command_of(forced, forced.peer, game))
		assert_dict(game.state.forced_roles).is_equal({3: &"dissident"})
		for peer: int in peers:
			FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
		assert_str(game.phase_id()).is_equal("round")
		assert_array(FixtureDealModes.players_of(game, &"dissident")).is_equal([3])
		assert_array(Array(game.diagnostics)).is_empty()


func test_a_decoded_force_role_without_a_role_clears_the_forced_one() -> void:
	var schema := WireSchema.game(true)
	var sent := WireMessage.new(&"ForceRole", {"role": ""}, 2, 3)
	var game := _deal_lobby([1, 2, 3], 7)
	FixtureModes.send(game, Intents.FORCE_ROLE, 3, {"role": "dissident"})
	assert_dict(game.state.forced_roles).is_equal({3: &"dissident"})
	var cleared := _decoded(schema, sent)
	if cleared == null:
		return
	assert_int(cleared.peer).is_equal(3)
	game.apply(_command_of(cleared, cleared.peer, game))
	assert_dict(game.state.forced_roles).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


## Hello.content is an s64 on the wire and an int in Intents.FIELDS (#97): a decoded Hello with
## the host's hash joins; one with another hash gets Rejected(wrong_content), which encodes.
func test_a_decoded_hello_joins_only_with_the_hosts_content_hash() -> void:
	var schema := WireSchema.game(false)
	var game := Match.new(
		FixtureBaseMode.mode(), 7, FlatWorldQuery.new(), FixtureBaseMode.layouts(), CONTENT
	)
	game.keep_history = true
	game.start(0)
	for peer: int in [1, 2]:
		FixtureModes.send(game, Intents.PEER_CONNECTED, peer)
	var host_hash := _decoded(
		schema, WireMessage.new(&"Hello", {"version": WireSchema.VERSION, "content": CONTENT})
	)
	var other_hash := _decoded(
		schema, WireMessage.new(&"Hello", {"version": WireSchema.VERSION, "content": CONTENT + 1})
	)
	if host_hash == null or other_hash == null:
		return
	game.apply(_command_of(host_hash, 1, game))
	game.apply(_command_of(other_hash, 2, game))
	assert_object(game.state.player(1)).is_not_null()
	assert_array(FixtureModes.rejections(game, 1)).is_empty()
	assert_object(game.state.player(2)).is_null()
	assert_array(FixtureModes.rejections(game, 2)).is_equal([&"wrong_content"])
	var rejects := game.view_of(2).events_named(&"Rejected")
	if rejects.is_empty():
		return
	var rejected := rejects[0] as RejectedEvent
	var payload := schema.encode(WireMessage.new(&"Rejected", rejected.to_dict()))
	assert_object(schema.decode(WireSchema.REJECTED, payload)).is_not_null()
	assert_array(Array(game.diagnostics)).is_empty()


## Intents.FIELDS says only that `settings` is a Dictionary: the wire decodes it untyped, with
## StringName keys, an int for a number and a PackedStringArray for a set of task type ids (§4.4).
## A decoded ChangeSettings with a number, a ban and a map changes all three in the lobby.
func test_a_decoded_change_settings_changes_numbers_bans_and_the_map() -> void:
	var mode := FixtureBanModes.mode()
	mode.maps.append(WIRE_MAP)
	var layouts := FixtureBanModes.layouts()
	layouts[WIRE_MAP] = layouts[FixtureBaseMode.MAP]
	var game := Match.new(mode, 7, FlatWorldQuery.new(), layouts)
	game.keep_history = true
	game.start(0)
	FixtureBaseMode.join(game, FixtureBaseMode.HOST)
	var settings := {&"knives": 3, &"banned_task_types": PackedStringArray(["second"])}
	var sent := WireMessage.new(&"ChangeSettings", {"settings": settings, "map": WIRE_MAP}, 4)
	var decoded := _decoded(WireSchema.game(false), sent)
	if decoded == null:
		return
	game.apply(_command_of(decoded, FixtureBaseMode.HOST, game))
	assert_array(FixtureModes.rejections(game, FixtureBaseMode.HOST)).is_empty()
	assert_int(game.state.settings[&"knives"]).is_equal(3)
	var banned: PackedStringArray = game.state.id_sets.get(
		&"banned_task_types", PackedStringArray()
	)
	assert_array(Array(banned)).is_equal(["second"])
	assert_str(game.state.map).is_equal(WIRE_MAP)
	assert_array(Array(game.diagnostics)).is_empty()


func test_cores_constant_ids_fit_the_wire() -> void:
	var ids: Array[String] = []
	for script: Script in [RejectReasons, CountdownCancelledEvent, DisconnectingEvent]:
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


## Field name -> the Variant type the row decodes it to, for the fields that become args: the
## flags as bools, an optional group's parts; the slots (`seq`, ForceRole's `peer`) and the
## presence flags left out.
func _arg_types(fields: Array[WireField]) -> Dictionary:
	var found := {}
	for field: WireField in fields:
		if field.slot != WireField.Slot.FIELD:
			continue
		match field.type:
			WireField.Type.FLAGS:
				for flag: String in field.flags:
					found[flag] = TYPE_BOOL
			WireField.Type.OPTIONAL:
				found.merge(_arg_types(field.parts))
			_:
				found[field.name] = field.decoded_type()
	return found


## The names of a row's wire-only fields: its slots and the presence flags of its optional groups.
func _wire_only(fields: Array[WireField]) -> PackedStringArray:
	var found := PackedStringArray()
	for field: WireField in fields:
		if field.slot != WireField.Slot.FIELD or field.type == WireField.Type.OPTIONAL:
			found.append(field.name)
		if field.type == WireField.Type.OPTIONAL:
			found.append_array(_wire_only(field.parts))
	return found


## What differs between the wire's arg types and the declared ones; empty when they agree.
func _type_drift(carried: Dictionary, declared: Dictionary) -> String:
	var problems := PackedStringArray()
	for key: Variant in declared:
		if not carried.has(key):
			problems.append("%s declared, not on the wire" % key)
		elif carried[key] != declared[key]:
			var carried_type: int = carried[key]
			var declared_type: int = declared[key]
			var types := [key, type_string(carried_type), type_string(declared_type)]
			problems.append("%s decodes as %s, declared %s" % types)
	for key: Variant in carried:
		if not declared.has(key):
			problems.append("%s on the wire, not declared" % key)
	return ", ".join(problems)


## The deal fixture's lobby with `peers` joined and nobody ready yet.
func _deal_lobby(peers: Array[int], seed_value: int) -> Match:
	var game := Match.new(
		FixtureDealModes.deal_mode(), seed_value, FlatWorldQuery.new(), FixtureDealModes.layouts()
	)
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	return game


## `message` through the encoder and the decoder, as the host receives it.
func _decoded(schema: WireSchema, message: WireMessage) -> WireMessage:
	var kind := schema.kind_of(message.name)
	var payload := schema.encode(message)
	var decoded := schema.decode(kind, payload)
	assert_object(decoded).override_failure_message(schema.explain(kind, payload)).is_not_null()
	return decoded


## The MatchCommand a decoded intent becomes (§4.4): its fields are the args and its seq the
## command's; `peer` is the sender the transport reports, or ForceRole's player.
func _command_of(decoded: WireMessage, peer: int, game: Match) -> MatchCommand:
	return MatchCommand.new(
		decoded.name, peer, game.ticked_through() + 1, decoded.fields, decoded.seq
	)
