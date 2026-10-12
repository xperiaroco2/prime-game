extends GdUnitTestSuite
## Cooking's checks and declarations (the cooking ADR's CE6, CE7, CE14, CE18; ARCHITECTURE §5,
## §9.5): ModeCheck refuses a Cooking without its parts, with a board that is no display kind or a
## used kind without its use, with lists that do not fit together, a kind the mode does not list,
## a box that gives no bun or raw patty, a kind no box gives, seconds out of bounds, an uncapped
## or too low cap, an ingredient that never vanishes; emits() names every event the deal sends; and
## both leak lists name every event emits() returns. Fixture values only.

const P1 := 1
const P2 := 2


func test_the_fixture_modes_pass_the_mode_check() -> void:
	assert_array(Array(ModeCheck.run(FixtureCookingModes.basic()).errors)).is_empty()
	assert_array(Array(ModeCheck.run(FixtureCookingModes.winning()).errors)).is_empty()


func test_the_mode_check_refuses_a_cooking_without_its_parts() -> void:
	var mode := FixtureCookingModes.basic()
	var type := FixtureCookingModes.type_of(mode)
	type.order_board = null
	type.herb_board = null
	type.grill = null
	type.herb_bed = null
	type.place = null
	type.buns = []
	type.raw_patties = []
	type.herbs = []
	type.boxes = []
	type.burnt = null
	type.subtasks_setting = &""
	type.code_rng = &""
	var errors := _errors(mode)
	for property: String in ["order_board", "herb_board", "grill", "herb_bed", "place"]:
		assert_str(errors).contains("Cooking cooking has no %s station kind" % property)
	for list_name: String in ["buns", "raw_patties", "herbs", "boxes"]:
		assert_str(errors).contains("Cooking cooking has no %s" % list_name)
	assert_str(errors).contains("Cooking cooking has 2 fried_patties for 0 raw_patties")
	assert_str(errors).contains("Cooking cooking has no burnt item kind")
	assert_str(errors).contains("Cooking cooking has no subtasks_setting")
	assert_str(errors).contains("Cooking cooking has an empty RNG purpose")


func test_the_boards_are_display_kinds_and_the_others_end_in_their_use() -> void:
	var mode := FixtureCookingModes.basic()
	var type := FixtureCookingModes.type_of(mode)
	type.herb_board.display = false
	type.grill.display = true
	type.grill.actions = []
	type.place.actions[0].effects.append(TakeIntoHand.new())
	type.herb_bed.actions = []
	var errors := _errors(mode)
	assert_str(errors).contains("station kind herb_board is not a display kind")
	assert_str(errors).contains("station kind grill is a display kind, never used")
	assert_str(errors).contains("station kind place has no Interact rule ending in UseStation")
	assert_str(errors).contains("station kind herb_bed has no Interact rule ending in UseStation")
	assert_str(errors).not_contains("order_board is not")


func test_every_kind_is_named_once_and_held_in_the_right_hands() -> void:
	var mode := FixtureCookingModes.basic()
	var type := FixtureCookingModes.type_of(mode)
	type.herbs.append(type.buns[0])
	type.buns[1].hands = 2
	type.boxes[0].hands = 1
	var errors := _errors(mode)
	assert_str(errors).contains("Cooking cooking names item kind bun_a twice")
	assert_str(errors).contains("Cooking cooking: ingredient kind bun_b is two-handed")
	assert_str(errors).contains("Cooking cooking: box kind box_bun_a is not two-handed")


func test_a_kind_the_mode_does_not_list_is_refused() -> void:
	var mode := FixtureCookingModes.basic()
	var type := FixtureCookingModes.type_of(mode)
	mode.item_kinds.erase(type.burnt)
	mode.item_kinds.erase(type.boxes[1])
	var errors := _errors(mode)
	assert_str(errors).contains("names item kind burnt, which the mode does not declare")
	assert_str(errors).contains("names item kind box_bun_b, which the mode does not declare")


func test_each_box_gives_one_bun_or_raw_patty_on_a_tag_of_its_own() -> void:
	var mode := FixtureCookingModes.basic()
	var type := FixtureCookingModes.type_of(mode)
	# box_raw_b gives a fried patty: raw_b comes from no box.
	type.boxes[3].target_actions = [FixtureGiveModes.take_rule(type.fried_patties[1])]
	type.boxes[0].spawn_tag = &"grill"
	type.boxes[1].spawn_tag = &""
	type.boxes[2].vanish_seconds = 30
	var errors := _errors(mode)
	assert_str(errors).contains(
		"box kind box_raw_b does not give exactly one bun or raw patty kind"
	)
	assert_str(errors).contains("Cooking cooking: no box gives item kind raw_b")
	assert_str(errors).contains("box kind box_bun_a shares the spawn tag grill")
	assert_str(errors).contains("box kind box_bun_b has no spawn_tag to place it on")
	assert_str(errors).contains("box kind box_raw_a must not vanish")


func test_at_most_255_herbs() -> void:
	var type := FixtureCookingModes.cooking_type()
	for i in Cooking.MAX_HERBS - type.herbs.size():
		type.herbs.append(FixtureCookingModes.ingredient(StringName("h%d" % i), true))
	assert_str("\n".join(type.check(null))).not_contains("herbs, more than")
	type.herbs.append(FixtureCookingModes.ingredient(&"one_more", true))
	assert_str("\n".join(type.check(null))).contains("Cooking cooking has 256 herbs, more than 255")


func test_the_seconds_are_within_bounds_burn_counted_from_fried_and_default_outside() -> void:
	assert_float(Cooking.new().fry_seconds).is_equal(0.0)
	assert_float(Cooking.new().burn_seconds).is_equal(0.0)
	var cases := {[0.0, 2.0]: "fry_seconds", [601.0, 602.0]: "fry_seconds", [1.0, 601.0]: "burn"}
	for pair: Array in cases:
		var mode := FixtureCookingModes.basic()
		FixtureCookingModes.type_of(mode).fry_seconds = pair[0]
		FixtureCookingModes.type_of(mode).burn_seconds = pair[1]
		assert_str(_errors(mode)).override_failure_message(str(pair)).contains(
			"Cooking cooking %s" % cases[pair]
		)
	for pair: Array in [[0.05, 600.0], [600.0, 0.05], [2.0, 1.0]]:
		var mode := FixtureCookingModes.basic()
		FixtureCookingModes.type_of(mode).fry_seconds = pair[0]
		FixtureCookingModes.type_of(mode).burn_seconds = pair[1]
		var errors := Array(ModeCheck.run(mode).errors)
		assert_array(errors).override_failure_message(str(pair)).is_empty()
	var type := FixtureCookingModes.cooking_type()
	assert_int(type.fried_ticks()).is_equal(20)
	assert_int(type.burnt_ticks()).is_equal(60)
	# The ADR's row 14: 10 s to fry, then 5 s to burn: fried at 200 ticks, burnt at 300 (§2.4).
	type.fry_seconds = 10.0
	type.burn_seconds = 5.0
	assert_int(type.fried_ticks()).is_equal(200)
	assert_int(type.burnt_ticks()).is_equal(300)


func test_the_subtasks_setting_starts_at_0_at_least() -> void:
	var mode := FixtureCookingModes.basic()
	mode.find_setting(&"burgers").min_value = -1
	assert_str(_errors(mode)).contains("Cooking cooking: setting burgers goes below 0")


func test_every_given_kind_is_capped_above_what_hands_and_places_hold() -> void:
	var mode := FixtureCookingModes.basic()
	var type := FixtureCookingModes.type_of(mode)
	var least := 2 * mode.max_players + FixtureCookingModes.MOST_BURGERS + 1
	type.herbs[0].max_items = least
	assert_str(_errors(mode)).not_contains("herb_a has max_items")
	type.herbs[0].max_items = least - 1
	type.buns[0].max_items = 0
	var errors := _errors(mode)
	assert_str(errors).contains("given kind herb_a has max_items %d, below %d" % [least - 1, least])
	assert_str(errors).contains("given kind bun_a has max_items 0, below %d" % least)


func test_every_ingredient_vanishes_when_left_lying() -> void:
	var mode := FixtureCookingModes.basic()
	var type := FixtureCookingModes.type_of(mode)
	type.burnt.vanish_seconds = 0
	type.fried_patties[0].vanish_seconds = 0
	var errors := _errors(mode)
	assert_str(errors).contains("ingredient kind burnt sets no vanish_seconds")
	assert_str(errors).contains("ingredient kind fried_a sets no vanish_seconds")


func test_emits_names_every_event_the_deal_sends() -> void:
	var game := FixtureCookingModes.in_round(FixtureCookingModes.basic(3), [P1, P2])
	var declared := _names(FixtureCookingModes.type_of(game.mode).emits())
	var seen: Array[StringName] = []
	for emitted: EmittedEvent in game.emitted():
		var event_name := emitted.event.event_name()
		if event_name in [&"OrderPosted", &"HerbsDealt", &"StationPlaced"]:
			if not seen.has(event_name):
				seen.append(event_name)
	assert_array(seen).contains_exactly_in_any_order(
		[&"StationPlaced", &"OrderPosted", &"HerbsDealt"]
	)
	for event_name: StringName in seen:
		assert_bool(declared.has(event_name)).override_failure_message(event_name).is_true()
	assert_bool(declared.has(&"ItemSpawned")).is_true()


func test_both_leak_lists_name_every_event_cooking_emits() -> void:
	for event_name: StringName in _names(Cooking.new().emits()):
		(
			assert_bool(LeakCheck.TASK_EVENTS.has(event_name))
			. override_failure_message(event_name)
			. is_true()
		)
		(
			assert_bool(ScenarioInvariants.TASK_EVENTS.has(event_name))
			. override_failure_message(event_name)
			. is_true()
		)


func test_the_ingredients_and_the_given_kinds_follow_the_lists() -> void:
	var type := FixtureCookingModes.cooking_type()
	var ids: Array[StringName] = []
	for kind: ItemKind in type.ingredients():
		ids.append(kind.id)
	(
		assert_array(ids)
		. is_equal(
			[
				&"bun_a",
				&"bun_b",
				&"raw_a",
				&"raw_b",
				&"fried_a",
				&"fried_b",
				&"burnt",
				&"herb_a",
				&"herb_b",
				&"herb_c",
			]
		)
	)
	assert_int(type.given_kinds().size()).is_equal(7)
	assert_object(type.fried_of(type.raw_patties[1])).is_same(type.fried_patties[1])
	assert_object(type.fried_of(type.buns[0])).is_null()


func _errors(mode: GameMode) -> String:
	return "\n".join(ModeCheck.run(mode).errors)


## The event names of `scripts` (each class's global name without its `Event`).
func _names(scripts: Array[Script]) -> Array[StringName]:
	var found: Array[StringName] = []
	for script: Script in scripts:
		found.append(StringName(String(script.get_global_name()).trim_suffix("Event")))
	return found
