extends GdUnitTestSuite
## PlayerRules (ARCHITECTURE §9.5): neutral class defaults that fail the mode check, so a mode
## writes every number in its data; the bounds, the ghost speed factor's included.


func test_the_neutral_defaults_fail_the_check_so_a_mode_writes_its_numbers() -> void:
	var found := "\n".join(PlayerRules.new().check(null))
	assert_str(found).contains("health is 0, outside 1 to 1000")
	assert_str(found).contains("stamina is 0, outside 1 to 1000")
	assert_str(found).contains("walk_speed_mps is 0, outside 0.5 to 20")
	assert_str(found).contains("ghost_speed_factor is 0, outside 1 to 3")
	assert_str(found).contains("capsule_radius_m is 0, outside 0.1 to 1")


func test_the_mvp_numbers_pass() -> void:
	assert_array(Array(FixtureModes.player_rules().check(null))).is_empty()


func test_the_ghost_speed_factor_is_bounded_from_1_to_3() -> void:
	var rules := FixtureModes.player_rules()
	rules.ghost_speed_factor = 0.9
	assert_str("\n".join(rules.check(null))).contains("ghost_speed_factor is 0.9, outside 1 to 3")
	rules.ghost_speed_factor = 3.1
	assert_str("\n".join(rules.check(null))).contains("ghost_speed_factor is 3.1, outside 1 to 3")
	rules.ghost_speed_factor = 3.0
	assert_array(Array(rules.check(null))).is_empty()
