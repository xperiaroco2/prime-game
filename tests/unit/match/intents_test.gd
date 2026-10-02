extends GdUnitTestSuite
## Intents.FIELDS (ARCHITECTURE §4.1, §4.4): every intent, ForceRole and ForceClock declare their
## fields, which the rules read through and the wire table is checked against (3d).


func test_every_intent_and_debug_command_declare_their_fields_and_nothing_else_does() -> void:
	var expected: Array[StringName] = Intents.ALL.duplicate()
	expected.append_array([Intents.FORCE_ROLE, Intents.FORCE_CLOCK])
	assert_array(Intents.FIELDS.keys()).contains_exactly_in_any_order(expected)


func test_each_field_is_named_by_a_string_with_a_variant_type() -> void:
	for intent: StringName in Intents.FIELDS:
		var fields: Dictionary = Intents.FIELDS[intent]
		for field: Variant in fields:
			(
				assert_bool(field is String)
				. override_failure_message("%s: %s" % [intent, field])
				. is_true()
			)
			var type: Variant = fields[field]
			assert_bool(type is int and type > TYPE_NIL and type < TYPE_MAX).is_true()


func test_move_claim_carries_a_jump_count_and_hello_the_content_hash() -> void:
	assert_int(Intents.FIELDS[Intents.MOVE_CLAIM]["jumps"]).is_equal(TYPE_INT)
	assert_bool(Intents.FIELDS[Intents.MOVE_CLAIM].has("jumped")).is_false()
	assert_int(Intents.FIELDS[Intents.HELLO]["content"]).is_equal(TYPE_INT)
	assert_bool(Intents.FIELDS[Intents.HELLO].has("name")).is_false()
