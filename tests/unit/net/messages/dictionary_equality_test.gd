extends GdUnitTestSuite
## Pins how Godot 4.7.2's `==` treats the collections a decoded event holds (ARCHITECTURE §4.4):
## the leak test compares a decoded payload with to_dict() by `==`. It holds between typed and
## untyped containers and ignores key order; a String key equals a StringName key, though a String
## value does not equal a StringName value. So the codec's own tests compare through
## WireSamples.same(), which checks every Variant type and each container's typing as well.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")


func test_typed_and_untyped_dictionaries_compare_equal() -> void:
	var typed: Dictionary[StringName, int] = {&"a": 1, &"b": 2}
	var untyped := {&"a": 1, &"b": 2}
	assert_bool(typed == untyped).is_true()
	assert_bool(untyped == typed).is_true()
	var built := Dictionary({}, TYPE_STRING_NAME, &"", null, TYPE_INT, &"", null)
	built[&"a"] = 1
	built[&"b"] = 2
	assert_bool(built == typed).is_true()
	assert_bool(built.is_same_typed(typed)).is_true()
	var peers: Dictionary[int, Vector3] = {1: Vector3.ONE}
	assert_bool(peers == {1: Vector3.ONE}).is_true()


func test_key_order_does_not_matter() -> void:
	assert_bool({&"a": 1, &"b": 2} == {&"b": 2, &"a": 1}).is_true()


func test_typed_and_untyped_arrays_compare_equal() -> void:
	var typed: Array[Dictionary] = [{"peer": 1}]
	assert_bool(typed == [{"peer": 1}]).is_true()


func test_a_string_key_equals_a_string_name_key_so_same_checks_types() -> void:
	# As keys a String and a StringName are one key; as values they differ.
	assert_bool({"a": 1} == {&"a": 1}).is_true()
	assert_bool({"k": "x"} == {"k": &"x"}).is_false()
	assert_bool(&"x" == "x").is_true()
	assert_bool(Samples.same({"a": 1}, {&"a": 1})).is_false()
	assert_bool(Samples.same({"k": "x"}, {"k": &"x"})).is_false()
	var typed: Dictionary[StringName, int] = {&"a": 1}
	assert_bool(Samples.same(typed, {&"a": 1})).is_false()
	assert_bool(Samples.same(typed, typed.duplicate())).is_true()


func test_a_packed_array_never_equals_an_array() -> void:
	# Inside a Dictionary the two compare unequal; at the top level `==` between them is a script
	# error ("Invalid operands"), so a decoder must build the packed type to_dict() holds.
	var packed: Variant = {"ids": PackedStringArray(["a"])}
	var plain: Variant = {"ids": ["a"]}
	assert_bool(packed == plain).is_false()
