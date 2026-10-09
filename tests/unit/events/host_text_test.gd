extends GdUnitTestSuite
## HostText (#548): host text as an id plus arguments, and its to_dict() in exactly the Variant
## types the wire decodes it to (a list<record{id, list<id>, map<id, s32>}>), which the leak test
## compares byte for byte.


func test_to_dict_has_the_decoders_types() -> void:
	var text := HostText.of(
		HostText.MARKERS, PackedStringArray(["package"]), {&"need": 4, &"have": 2}
	)
	var found := text.to_dict()
	assert_array(found.keys()).is_equal(["id", "ids", "numbers"])
	assert_int(typeof(found["id"])).is_equal(TYPE_STRING_NAME)
	assert_int(typeof(found["ids"])).is_equal(TYPE_PACKED_STRING_ARRAY)
	var numbers: Dictionary = found["numbers"]
	assert_int(numbers.get_typed_key_builtin()).is_equal(TYPE_STRING_NAME)
	assert_int(numbers.get_typed_value_builtin()).is_equal(TYPE_INT)
	assert_dict(numbers).is_equal({&"need": 4, &"have": 2})


func test_to_dicts_is_a_typed_array_in_order_and_copies() -> void:
	var subjects := PackedStringArray(["circle"])
	var texts: Array[HostText] = [
		HostText.of(HostText.PLAYERS_FEW, PackedStringArray(), {&"count": 1}),
		HostText.of(HostText.COLOURS, subjects, {&"need": 3, &"have": 2}),
	]
	subjects.append("square")
	var found := HostText.to_dicts(texts)
	assert_int(found.get_typed_builtin()).is_equal(TYPE_DICTIONARY)
	(
		assert_array(found.map(func(each: Dictionary) -> StringName: return each["id"]))
		. is_equal([&"players_few", &"colours"])
	)
	var copied: PackedStringArray = found[1]["ids"]
	assert_array(Array(copied)).is_equal(["circle"])
	assert_array(HostText.to_dicts([])).is_empty()
