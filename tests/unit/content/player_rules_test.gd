extends GdUnitTestSuite
## PlayerRules (ARCHITECTURE §9.5): neutral class defaults that fail the mode check, so a mode
## writes every number in its data; the bounds, the crawl speed's and the knockdown time's included.


func test_the_neutral_defaults_fail_the_check_so_a_mode_writes_its_numbers() -> void:
	var found := "\n".join(PlayerRules.new().check(null))
	assert_str(found).contains("health is 0, outside 1 to 1000")
	assert_str(found).contains("stamina is 0, outside 1 to 1000")
	assert_str(found).contains("walk_speed_mps is 0, outside 0.5 to 20")
	assert_str(found).contains("crawl_speed_mps is 0, outside 0.1 to 0")
	assert_str(found).contains("knockdown_s is 0, outside 1 to 120")
	assert_str(found).contains("capsule_radius_m is 0, outside 0.1 to 1")


func test_the_mvp_numbers_pass() -> void:
	assert_array(Array(FixtureModes.player_rules().check(null))).is_empty()


func test_the_crawl_speed_is_bounded_from_a_tenth_to_the_walk_speed() -> void:
	var rules := FixtureModes.player_rules()
	rules.crawl_speed_mps = 0.09
	assert_str("\n".join(rules.check(null))).contains("crawl_speed_mps is 0.09, outside 0.1 to 4.5")
	rules.crawl_speed_mps = 4.6
	assert_str("\n".join(rules.check(null))).contains("crawl_speed_mps is 4.6, outside 0.1 to 4.5")
	rules.crawl_speed_mps = 4.5
	assert_array(Array(rules.check(null))).is_empty()


func test_the_knockdown_time_is_bounded_from_1_to_120_seconds() -> void:
	var rules := FixtureModes.player_rules()
	rules.knockdown_s = 0.5
	assert_str("\n".join(rules.check(null))).contains("knockdown_s is 0.5, outside 1 to 120")
	rules.knockdown_s = 121.0
	assert_str("\n".join(rules.check(null))).contains("knockdown_s is 121, outside 1 to 120")
	rules.knockdown_s = 1.0
	assert_array(Array(rules.check(null))).is_empty()
