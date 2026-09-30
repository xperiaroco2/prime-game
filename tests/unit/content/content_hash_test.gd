extends GdUnitTestSuite
## ContentHash (ARCHITECTURE §3.3): the same content hashes the same, however it was built; any
## stored value, in any sub-resource, changes it.


func test_the_same_content_hashes_the_same() -> void:
	assert_int(ContentHash.of(FixtureModes.basic())).is_equal(ContentHash.of(FixtureModes.basic()))


func test_a_number_deep_inside_changes_the_hash() -> void:
	var base := ContentHash.of(FixtureModes.basic())
	var mode := FixtureModes.basic()
	mode.win_conditions[1].conditions[0].negate = true
	assert_int(ContentHash.of(mode)).is_not_equal(base)
	mode = FixtureModes.basic()
	mode.player_rules.walk_speed_mps = 4.6
	assert_int(ContentHash.of(mode)).is_not_equal(base)
	mode = FixtureModes.basic()
	mode.phases[0].settings[&"countdown_ticks"] = 1.0
	assert_int(ContentHash.of(mode)).is_not_equal(base)


func test_order_counts() -> void:
	var mode := FixtureModes.basic()
	var base := ContentHash.of(mode)
	mode.win_conditions.reverse()
	assert_int(ContentHash.of(mode)).is_not_equal(base)


func test_a_part_class_counts_by_its_script() -> void:
	var a := FixtureModes.basic()
	var b := FixtureModes.basic()
	b.phases[1].phase_class = FixturePhase
	assert_int(ContentHash.of(a)).is_not_equal(ContentHash.of(b))
	assert_str(ContentHash.text_of(a)).contains("script res://core/match/phases/round_phase.gd")


func test_a_shared_resource_is_written_once() -> void:
	var mode := FixtureModes.basic()
	var shared := FixtureNote.of("shared")
	mode.transitions[0].actions = [shared, shared]
	var text := ContentHash.text_of(mode)
	assert_int(text.count("FixtureNote") + text.count("fixture_note.gd")).is_greater(0)
	assert_str(text).contains("ref ")
