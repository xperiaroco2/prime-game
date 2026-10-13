extends GdUnitTestSuite
## PlayerRules (ARCHITECTURE §9.5): neutral class defaults that fail the mode check, so a mode
## writes every number in its data; the bounds, the knockdown time's and the respawn numbers'
## included. A downed player has no speed of its own (the knockdown rework's KE4).


func test_the_neutral_defaults_fail_the_check_so_a_mode_writes_its_numbers() -> void:
	var found := "\n".join(PlayerRules.new().check(null))
	assert_str(found).contains("health is 0, outside 1 to 1000")
	assert_str(found).contains("stamina is 0, outside 1 to 1000")
	assert_str(found).contains("walk_speed_mps is 0, outside 0.5 to 20")
	assert_str(found).contains("knockdown_s is 0, outside 1 to 120")
	assert_str(found).contains("capsule_radius_m is 0, outside 0.1 to 1")


func test_the_mvp_numbers_pass() -> void:
	assert_array(Array(FixtureModes.player_rules().check(null))).is_empty()


func test_the_knockdown_time_is_bounded_from_1_to_120_seconds() -> void:
	var rules := FixtureModes.player_rules()
	rules.knockdown_s = 0.5
	assert_str("\n".join(rules.check(null))).contains("knockdown_s is 0.5, outside 1 to 120")
	rules.knockdown_s = 121.0
	assert_str("\n".join(rules.check(null))).contains("knockdown_s is 121, outside 1 to 120")
	rules.knockdown_s = 1.0
	assert_array(Array(rules.check(null))).is_empty()


func test_the_respawn_numbers_are_bounded() -> void:
	var found := "\n".join(PlayerRules.new().check(null))
	assert_str(found).contains("respawn_s is 0, outside 1 to 300")
	var rules := FixtureModes.player_rules()
	rules.respawn_s = 301.0
	rules.invulnerable_s = 30.5
	rules.respawn_free_m = 5.5
	found = "\n".join(rules.check(null))
	assert_str(found).contains("respawn_s is 301, outside 1 to 300")
	assert_str(found).contains("invulnerable_s is 30.5, outside 0 to 30")
	assert_str(found).contains("respawn_free_m is 5.5, outside 0 to 5")
	rules.respawn_s = 1.0
	rules.invulnerable_s = 0.0
	rules.respawn_free_m = 0.0
	assert_array(Array(rules.check(null))).is_empty()


func test_the_crouch_numbers_are_bounded_by_the_standing_ones() -> void:
	# The crouch ADR's bounds: the crouched capsule between its own width and the standing one,
	# its eye inside it, the crouch walk up to the walk and the faster one between the two.
	var found := "\n".join(PlayerRules.new().check(null))
	assert_str(found).contains("crouch_speed_mps is 0, outside 0.1 to 0")
	var rules := FixtureModes.player_rules()
	rules.crouch_height_m = 0.7
	rules.crouch_eye_height_m = 0.8
	rules.crouch_speed_mps = 4.6
	rules.crouch_fast_speed_mps = 2.0
	found = "\n".join(rules.check(null))
	assert_str(found).contains("crouch_height_m is 0.7, outside 0.8 to 1.8")
	assert_str(found).contains("crouch_eye_height_m is 0.8, outside 0 to 0.7")
	assert_str(found).contains("crouch_speed_mps is 4.6, outside 0.1 to 4.5")
	assert_str(found).contains("crouch_fast_speed_mps is 2, outside 4.6 to 4.5")
	rules.crouch_height_m = 1.9
	assert_str("\n".join(rules.check(null))).contains("crouch_height_m is 1.9, outside 0.8 to 1.8")
	rules.crouch_height_m = 1.8
	rules.crouch_eye_height_m = 1.8
	rules.crouch_speed_mps = 4.5
	rules.crouch_fast_speed_mps = 4.5
	assert_array(Array(rules.check(null))).is_empty()


func test_crouch_maps_lists_only_the_modes_maps() -> void:
	var mode := FixtureModes.basic()
	var rules := mode.player_rules
	rules.crouch_maps = PackedStringArray([FixtureModes.MAP])
	assert_array(Array(rules.check(mode))).is_empty()
	rules.crouch_maps = PackedStringArray([FixtureModes.MAP, "fixture://elsewhere"])
	assert_array(Array(rules.check(mode))).is_equal(
		["crouch_maps lists fixture://elsewhere, which is not one of the mode's maps"]
	)


func test_the_crouched_pick_of_the_height_and_the_eye_and_where_it_plays() -> void:
	var rules := FixtureModes.player_rules()
	assert_float(rules.height_of(false)).is_equal(1.8)
	assert_float(rules.height_of(true)).is_equal(1.2)
	assert_float(rules.eye_height_of(false)).is_equal(1.6)
	assert_float(rules.eye_height_of(true)).is_equal(1.0)
	# An empty list: every map; a list: its maps alone.
	assert_bool(rules.crouch_plays_on("fixture://a")).is_true()
	assert_bool(rules.crouch_plays_on("fixture://b")).is_true()
	rules.crouch_maps = PackedStringArray(["fixture://a"])
	assert_bool(rules.crouch_plays_on("fixture://a")).is_true()
	assert_bool(rules.crouch_plays_on("fixture://b")).is_false()
