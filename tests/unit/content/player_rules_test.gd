extends GdUnitTestSuite
## PlayerRules (ARCHITECTURE §9.5): neutral class defaults that fail the mode check, so a mode
## writes every number in its data; the bounds, the knockdown time's and the respawn numbers'
## included. A downed player has no speed of its own (the knockdown rework's KE4); the rest's
## numbers and motion_maps (KE12, KE15, #847).


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


func test_the_direction_caps_are_none_or_up_to_the_sprint() -> void:
	# #1334: 0 is no cap (the neutral default passes); a cap above the sprint means nothing.
	var rules := FixtureModes.player_rules()
	rules.side_speed_mps = 0.0
	rules.back_speed_mps = 0.0
	assert_array(Array(rules.check(null))).is_empty()
	rules.sprint_speed_mps = 7.0
	rules.side_speed_mps = 8.0
	rules.back_speed_mps = -1.0
	var found := "\n".join(rules.check(null))
	assert_str(found).contains("side_speed_mps is 8, outside 0 to 7")
	assert_str(found).contains("back_speed_mps is -1, outside 0 to 7")
	rules.side_speed_mps = 3.0
	rules.back_speed_mps = 2.0
	assert_array(Array(rules.check(null))).is_empty()


func test_the_crouch_has_no_per_map_option() -> void:
	# The engineer's change (#989, #991): the crouch plays everywhere, "we need no such option
	# at all". crouch_maps and crouch_plays_on (the crouch ADR's KE10 (a)) are gone for good.
	var rules := PlayerRules.new()
	var names: Array[String] = []
	for property: Dictionary in rules.get_property_list():
		names.append(property["name"] as String)
	assert_array(names).not_contains(["crouch_maps"])
	assert_bool(rules.has_method(&"crouch_plays_on")).is_false()


func test_the_crouched_pick_of_the_height_and_the_eye() -> void:
	var rules := FixtureModes.player_rules()
	assert_float(rules.height_of(false)).is_equal(1.8)
	assert_float(rules.height_of(true)).is_equal(1.2)
	assert_float(rules.eye_height_of(false)).is_equal(1.6)
	assert_float(rules.eye_height_of(true)).is_equal(1.0)


func test_the_rest_numbers_are_bounded() -> void:
	# The knockdown rework's KE15, KD9 (b): placeholders, "not a decision", as are the bounds.
	var found := "\n".join(PlayerRules.new().check(null))
	assert_str(found).contains("rest_speed_mps is 0, outside 0.01 to 2")
	assert_str(found).contains("rest_s is 0, outside 0.05 to 5")
	assert_str(found).contains("longest_motion_s is 0, outside 1 to 60")
	var rules := FixtureModes.player_rules()
	rules.rest_speed_mps = 2.5
	rules.rest_s = 5.5
	rules.longest_motion_s = 5.0
	found = "\n".join(rules.check(null))
	assert_str(found).contains("rest_speed_mps is 2.5, outside 0.01 to 2")
	assert_str(found).contains("rest_s is 5.5, outside 0.05 to 5")
	# The longest motion is at least the rest time.
	assert_str(found).contains("longest_motion_s is 5, outside 5.5 to 60")
	rules.rest_speed_mps = 2.0
	rules.rest_s = 5.0
	rules.longest_motion_s = 60.5
	assert_str("\n".join(rules.check(null))).contains("longest_motion_s is 60.5, outside 5 to 60")
	rules.longest_motion_s = 5.0
	assert_array(Array(rules.check(null))).is_empty()


func test_motion_maps_lists_only_the_modes_maps() -> void:
	# KE12 (a): an empty list moves bodies on every map; a listed path that is not one of the mode's
	# maps is refused. KD11's crouch check is gone: the crouch plays everywhere (#991).
	var mode := FixtureModes.with_motion_map(FixtureModes.basic())
	var rules := mode.player_rules
	assert_array(Array(rules.check(mode))).is_empty()
	assert_bool(rules.motion_plays_on(FixtureModes.MOTION_MAP)).is_true()
	assert_bool(rules.motion_plays_on(FixtureModes.MAP)).is_false()
	rules.motion_maps = PackedStringArray()
	assert_bool(rules.motion_plays_on(FixtureModes.MAP)).is_true()
	assert_bool(rules.motion_plays_on("fixture://elsewhere")).is_true()
	assert_array(Array(rules.check(mode))).is_empty()
	rules.motion_maps = PackedStringArray([FixtureModes.MOTION_MAP, "fixture://elsewhere"])
	assert_array(Array(rules.check(mode))).is_equal(
		["motion_maps lists fixture://elsewhere, which is not one of the mode's maps"]
	)
