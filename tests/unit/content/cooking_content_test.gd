extends GdUnitTestSuite
## Cooking in `content/` (ARCHITECTURE §9.5.20; the cooking ADR, C6, #775): the task type with
## the engineer's words (§5.1) and numbers, its five station kinds and their rules (the herb board
## `display`, CE6; the order board's serve, #1101; CD16's 2 m; CE17's `Cooldown` on the beds and
## the boxes; no busy-hands condition on the grill, the beds and the order board, CD3 (b);
## `HandNotTwoHanded` on the place), the 22 item kinds (CE18: all listed in the mode, only the boxes
## tagged, the placeholder `vanish_seconds` and `max_items`; the burger of #1101),
## the shipped base mode's `burgers` setting (0 to 3, default 1, CD1), `tasks` at every type a map
## plays, Round's `VanishTicks` and `Interact` from the living, and the House's fit with Cooking
## and the greybox's without it (CD15, G8). Every map is read as the host reads it, in its own
## collision world (HostWorldQuery.for_mode), as `generator_content_test.gd` reads them. Like the
## mode check, this test loads `content/` on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const GREYBOX := "res://levels/greybox/greybox.tscn"
const HOUSE := "res://levels/house/house.tscn"
## §5.1's item names, the kinds in the task's lists' order (CD2, as drafted).
const BUNS := {
	&"bun_white": "White bun",
	&"bun_sesame": "Sesame bun",
	&"bun_dark": "Dark bun",
}
const RAW_PATTIES := {
	&"patty_light_raw": "Raw light patty",
	&"patty_red_raw": "Raw red patty",
	&"patty_deep_red_raw": "Raw deep red patty",
}
const FRIED_PATTIES := {
	&"patty_light": "Light patty",
	&"patty_red": "Red patty",
	&"patty_deep_red": "Deep red patty",
}
const HERBS := {
	&"basil": "Basil",
	&"dill": "Dill",
	&"rosemary": "Rosemary",
	&"chives": "Chives",
	&"mint": "Mint",
}
## Each box with the kind it gives; its spawn tag is its id (the House's box markers, C5).
const BOXES := {
	&"box_bun_white": [&"bun_white", "Box of white buns"],
	&"box_bun_sesame": [&"bun_sesame", "Box of sesame buns"],
	&"box_bun_dark": [&"bun_dark", "Box of dark buns"],
	&"box_patty_light": [&"patty_light_raw", "Box of light patties"],
	&"box_patty_red": [&"patty_red_raw", "Box of red patties"],
	&"box_patty_deep_red": [&"patty_deep_red_raw", "Box of deep red patties"],
}


func test_cooking_has_the_engineers_values() -> void:
	var cooking := _cooking(_mode())
	assert_object(cooking).is_not_null()
	if cooking == null:
		return
	assert_str(cooking.id).is_equal("cooking")
	assert_str(cooking.display_name).is_equal("Cooking")
	assert_str(cooking.description).is_equal(
		(
			"Make every order on the kitchen board: put its bun, a fried patty and the herb from"
			+ " the greenhouse board on its plate, then carry the burger to the board and serve it."
		)
	)
	assert_float(cooking.fry_seconds).is_equal(10.0)
	assert_float(cooking.burn_seconds).is_equal(5.0)
	assert_array(Array(cooking.maps)).is_equal([HOUSE])
	assert_str(cooking.subtasks_setting).is_equal("burgers")
	for kind: StationKind in _kinds(cooking):
		assert_str(kind.spawn_tag).override_failure_message(kind.id).is_equal(kind.id)
		assert_float(kind.radius_m).override_failure_message(kind.id).is_equal(2.0)
		assert_float(kind.height_m).override_failure_message(kind.id).is_equal(2.0)
	assert_array(_ids(_kinds(cooking))).is_equal(
		[&"order_board", &"herb_board", &"grill", &"herb_bed", &"place"]
	)


func test_the_herb_board_is_a_display_with_no_rule() -> void:
	# The order board was a display too until #1101 made it where a burger is served.
	var cooking := _cooking(_mode())
	assert_bool(cooking.herb_board.display).is_true()
	assert_array(cooking.herb_board.actions).is_empty()
	for kind: StationKind in [cooking.order_board, cooking.grill, cooking.herb_bed, cooking.place]:
		assert_bool(kind.display).override_failure_message(kind.id).is_false()


func test_each_used_station_kind_has_its_interact_rule() -> void:
	var cooking := _cooking(_mode())
	var expected := {
		&"grill": ["AtStation", "StationInSight", "StationUsable"],
		&"herb_bed": ["AtStation", "StationInSight", "StationUsable", "Cooldown"],
		&"place": ["HandNotTwoHanded", "AtStation", "StationInSight", "StationUsable"],
		&"order_board": ["AtStation", "StationInSight", "StationUsable"],
	}
	for kind: StationKind in [cooking.grill, cooking.herb_bed, cooking.place, cooking.order_board]:
		assert_int(kind.actions.size()).override_failure_message(kind.id).is_equal(1)
		var rule := kind.actions[0]
		assert_str(rule.trigger).is_equal("Interact")
		assert_array(_condition_names(rule)).override_failure_message(kind.id).is_equal(
			expected[kind.id]
		)
		assert_int(rule.effects.size()).is_equal(1)
		assert_object(rule.effects[0]).is_instanceof(UseStation)
	_assert_take_cooldown(cooking.herb_bed.actions[0], "herb_bed")


func test_the_22_item_kinds_have_their_names_and_numbers() -> void:
	var cooking := _cooking(_mode())
	assert_dict(_names(cooking.buns)).is_equal(BUNS)
	assert_dict(_names(cooking.raw_patties)).is_equal(RAW_PATTIES)
	assert_dict(_names(cooking.fried_patties)).is_equal(FRIED_PATTIES)
	assert_dict(_names(cooking.herbs)).is_equal(HERBS)
	assert_str(cooking.burnt.id).is_equal("patty_burnt")
	assert_str(cooking.burnt.display_name).is_equal("Burnt patty")
	assert_array(_ids(cooking.buns)).is_equal(BUNS.keys())
	assert_array(_ids(cooking.raw_patties)).is_equal(RAW_PATTIES.keys())
	assert_array(_ids(cooking.fried_patties)).is_equal(FRIED_PATTIES.keys())
	assert_array(_ids(cooking.herbs)).is_equal(HERBS.keys())
	# The 15 ingredients: one-handed, untagged, vanish after 60 s when left lying; the 11 a take
	# gives capped at 128 (placeholders, "not a decision", CD6 (c), CE3).
	var ingredients := cooking.ingredients()
	assert_int(ingredients.size()).is_equal(15)
	var given := _ids(cooking.given_kinds())
	assert_int(given.size()).is_equal(11)
	for kind: ItemKind in ingredients:
		assert_int(kind.hands).override_failure_message(kind.id).is_equal(1)
		assert_str(kind.spawn_tag).override_failure_message(kind.id).is_empty()
		assert_int(kind.vanish_seconds).override_failure_message(kind.id).is_equal(60)
		assert_int(kind.max_items).override_failure_message(kind.id).is_equal(
			128 if given.has(kind.id) else 0
		)
		assert_array(kind.target_actions).override_failure_message(kind.id).is_empty()
	# The plated burger (#1101): one-handed, untagged, uncapped, vanishes after 60 s when left lying
	# (placeholders, "not a decision").
	var burger := cooking.burger
	assert_str(burger.id).is_equal("burger")
	assert_str(burger.display_name).is_equal("Burger")
	assert_array([burger.hands, burger.vanish_seconds, burger.max_items]).is_equal([1, 60, 0])
	assert_str(burger.spawn_tag).is_empty()
	assert_array(burger.target_actions).is_empty()


func test_each_box_is_two_handed_tagged_and_gives_its_kind() -> void:
	var cooking := _cooking(_mode())
	assert_array(_ids(cooking.boxes)).is_equal(BOXES.keys())
	for box: ItemKind in cooking.boxes:
		var expected: Array = BOXES[box.id]
		assert_str(box.display_name).is_equal(expected[1])
		assert_int(box.hands).override_failure_message(box.id).is_equal(2)
		assert_str(box.spawn_tag).override_failure_message(box.id).is_equal(box.id)
		assert_int(box.vanish_seconds).override_failure_message(box.id).is_equal(0)
		assert_int(box.target_actions.size()).override_failure_message(box.id).is_equal(1)
		var rule := box.target_actions[0]
		assert_str(rule.trigger).is_equal("Interact")
		assert_array(_condition_names(rule)).override_failure_message(box.id).is_equal(
			["ItemOnGround", "InReach", "InSight", "Cooldown"]
		)
		_assert_take_cooldown(rule, box.id)
		assert_int(rule.effects.size()).is_equal(1)
		var give := rule.effects[0] as GiveItem
		assert_object(give).override_failure_message(box.id).is_not_null()
		if give != null:
			assert_str(give.kind.id).override_failure_message(box.id).is_equal(expected[0])


func test_the_mode_lists_all_22_kinds() -> void:
	var mode := _mode()
	var cooking := _cooking(mode)
	var listed := _ids(mode.item_kinds)
	var all: Array[ItemKind] = cooking.kinds()
	all.append_array(cooking.boxes)
	assert_int(all.size()).is_equal(22)
	for kind: ItemKind in all:
		assert_bool(listed.has(kind.id)).override_failure_message(String(kind.id)).is_true()


func test_the_burgers_setting_and_every_type_in_every_match() -> void:
	var mode := _mode()
	var burgers := mode.find_setting(&"burgers")
	assert_object(burgers).is_not_null()
	if burgers == null:
		return
	assert_bool(burgers.is_number()).is_true()
	assert_array([burgers.default_value, burgers.min_value, burgers.max_value]).is_equal([1, 0, 3])
	assert_str(burgers.display_name).is_equal("Burgers (Cooking)")
	# `tasks` (GD7 (i)): every type that plays on the map, every match, so its maximum is the most
	# types one map plays: the House's five (Delivery, the Generator, the photo task,
	# Cooking and car repair, #810); the greybox deals its Delivery by colours alone.
	var tasks := mode.find_setting(&"tasks")
	var most := 0
	for path: String in mode.maps:
		most = maxi(most, DealTasks.pool_of(mode, PackedStringArray(), path).size())
	assert_int(most).is_equal(5)
	assert_int(tasks.max_value).is_equal(most)
	# Its default deals every type of the default map: the estate's one ship's engine, the M8
	# slice's (#1496); the House's matches set `tasks` to its five.
	assert_int(tasks.default_value).is_equal(
		DealTasks.pool_of(mode, PackedStringArray(), mode.default_map()).size()
	)
	assert_bool(DealTasks.pool_of(mode, PackedStringArray(), HOUSE).has(_cooking(mode))).is_true()
	assert_int(DealTasks.pool_of(mode, PackedStringArray(), GREYBOX).size()).is_equal(1)


func test_round_runs_vanish_ticks_and_accepts_interact_from_the_living() -> void:
	var round_phase := _mode().find_phase(&"round")
	var vanish := 0
	for system: TickSystem in round_phase.tick_systems:
		if system is VanishTicks:
			vanish += 1
	assert_int(vanish).is_equal(1)
	var froms: Array[int] = []
	for accept: AcceptSpec in round_phase.accepts:
		if accept.intent == &"Interact":
			froms.append(accept.from)
	assert_array(froms).is_equal([AcceptSpec.From.LIVING])


func test_the_house_fits_cooking_and_the_greybox_is_asked_for_none() -> void:
	var mode := _mode()
	var cooking := _cooking(mode)
	var layouts := _layouts(mode)
	var settings := mode.default_settings()
	settings[&"burgers"] = mode.find_setting(&"burgers").max_value
	var tags: Array[StringName] = []
	for kind: StationKind in _kinds(cooking):
		tags.append(kind.spawn_tag)
	for box: ItemKind in cooking.boxes:
		tags.append(box.spawn_tag)
	for path: String in mode.maps:
		var demands := LayoutCheck.demands_of(
			mode, PhaseSpec.Level.MAP, settings, mode.max_players, {}, path
		)
		(
			assert_array(Array(demands.shortfalls(layouts[path])))
			. override_failure_message(path)
			. is_empty()
		)
		for tag: StringName in tags:
			var asked := demands.markers.get(tag, 0) as int
			if path == HOUSE:
				assert_int(asked).override_failure_message(String(tag)).is_greater(0)
			else:
				assert_int(asked).override_failure_message("%s %s" % [path, tag]).is_equal(0)
				assert_int(layouts[path].count(tag)).override_failure_message(String(tag)).is_equal(
					0
				)
	var house := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, settings, mode.max_players, {}, HOUSE
	)
	assert_int(house.markers.get(cooking.place.spawn_tag, 0) as int).is_equal(3)
	assert_int(house.markers.get(cooking.herb_bed.spawn_tag, 0) as int).is_equal(5)


func _mode() -> GameMode:
	return load(BASE_MODE) as GameMode


func _cooking(mode: GameMode) -> Cooking:
	for type: TaskType in mode.task_types:
		if type is Cooking:
			return type as Cooking
	return null


func _kinds(cooking: Cooking) -> Array[StationKind]:
	return [cooking.order_board, cooking.herb_board, cooking.grill, cooking.herb_bed, cooking.place]


func _ids(things: Array) -> Array[StringName]:
	var found: Array[StringName] = []
	for thing: Variant in things:
		found.append(thing.id)
	return found


func _names(kinds: Array[ItemKind]) -> Dictionary:
	var found := {}
	for kind: ItemKind in kinds:
		found[kind.id] = kind.display_name
	return found


func _condition_names(rule: Rule) -> Array[String]:
	var names: Array[String] = []
	for condition: Condition in rule.conditions:
		names.append((condition.get_script() as Script).get_global_name())
	return names


## CE17: the beds' and the boxes' takes share one `Cooldown` key at 0.25 s.
func _assert_take_cooldown(rule: Rule, holder: String) -> void:
	var cooldown: Cooldown = null
	for condition: Condition in rule.conditions:
		if condition is Cooldown:
			cooldown = condition as Cooldown
	assert_object(cooldown).override_failure_message(holder).is_not_null()
	if cooldown == null:
		return
	assert_str(cooldown.key).override_failure_message(holder).is_equal("cooking_take")
	assert_float(cooldown.seconds).override_failure_message(holder).is_equal(0.25)


## The layouts of the mode's levels as the host reads them, each in its own collision world
## (HostWorldQuery.for_mode), as generator_content_test.gd reads them.
func _layouts(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts
