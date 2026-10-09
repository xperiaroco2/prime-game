extends GdUnitTestSuite
## MatchCommand reads its args through Intents.FIELDS (ARCHITECTURE §4.4): a declared field as sent,
## a typed getter's default for another type, and an undeclared field as absent, kept in
## undeclared_reads for Match to record, so a rule that reads a name the wire does not carry
## cannot pass silently.


func test_a_declared_field_reads_as_sent() -> void:
	var command := MatchCommand.new(Intents.MOVE_CLAIM, 2, 5, {"jumps": 3, "sprint": true})
	assert_int(command.field("jumps")).is_equal(3)
	assert_int(command.get_int("jumps")).is_equal(3)
	assert_bool(command.get_bool("sprint")).is_true()
	assert_bool(command.has_field("jumps")).is_true()
	assert_bool(command.has_field("moving")).is_false()


func test_a_typed_getter_gives_its_default_for_another_type() -> void:
	var command := MatchCommand.new(Intents.MOVE_CLAIM, 2, 5, {"jumps": 1.0})
	assert_int(command.get_int("jumps", -1)).is_equal(-1)
	assert_float(command.field("jumps")).is_equal(1.0)


func test_an_undeclared_field_reads_as_absent_even_when_sent() -> void:
	var command := MatchCommand.new(Intents.MOVE_CLAIM, 2, 5, {"jumped": true})
	assert_bool(command.declares("jumped")).is_false()
	assert_object(command.field("jumped")).is_null()
	assert_bool(command.get_bool("jumped")).is_false()
	assert_array(Array(command.undeclared_reads)).is_equal(["jumped"])
	var hello := MatchCommand.new(Intents.HELLO, 2, 5, {"nick": "Ann", "version": 1})
	assert_str(hello.get_string("nick", "none")).is_equal("none")
	assert_int(hello.get_int("version")).is_equal(1)
	assert_array(Array(hello.undeclared_reads)).is_equal(["nick"])


func test_force_role_reads_its_role() -> void:
	var command := MatchCommand.new(Intents.FORCE_ROLE, 3, 0, {"role": "dissident"})
	assert_str(command.get_string("role")).is_equal("dissident")
