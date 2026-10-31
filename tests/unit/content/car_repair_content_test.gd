extends GdUnitTestSuite
## Car repair in `content/` (ARCHITECTURE §9.5.21; the car repair ADR, R6, #810): the task type
## with the engineer's words (RD12) and the placeholders he approved (RD2, "not a decision"), its
## station kinds and their rules (the car's timed hold and the panel's endless one, each with the
## hands free of a two-handed item; the bins' `car_part_take` cooldown of 0.25 s and no busy-hands
## condition, RD17; the picture a display kind with no rule), the three part kinds (one-handed, no
## spawn tag, `max_items` set, no `vanish_seconds`, listed in the mode: CE3, CE18), the shipped base
## mode's `car_parts` setting ("Parts to fit", 1 to 3, default 2), `tasks` at every type a map plays
## (RD13 (d)), Round's `Interact` and `StopRaise` from the living, and the House's fit with car
## repair and the greybox's without it (RD13 (c), G8). Every map is read as the host reads it, in
## its own collision world (HostWorldQuery.for_mode), as `cooking_content_test.gd` reads them. Like
## the mode check, this test loads `content/` on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const GREYBOX := "res://levels/greybox/greybox.tscn"
const HOUSE := "res://levels/house/house.tscn"
## The part kinds by colour, in the bins' order: each bin gives the part of its plate's colour.
const PARTS := {
	&"car_part_green": "Green part",
	&"car_part_blue": "Blue part",
	&"car_part_yellow": "Yellow part",
}


func test_car_repair_has_the_engineers_words_and_numbers() -> void:
	var repair := _repair(_mode())
	assert_object(repair).is_not_null()
	if repair == null:
		return
	assert_str(repair.id).is_equal("car_repair")
	# RD12's drafts, approved as drafted.
	assert_str(repair.display_name).is_equal("Repair the car")
	assert_str(repair.description).is_equal(
		(
			"Take the part shown on the garage wall from the shelf in storage, then fit it under"
			+ " the car while someone holds the lift."
		)
	)
	assert_array(Array(repair.maps)).is_equal([HOUSE])
	assert_str(repair.subtasks_setting).is_equal("car_parts")
	# RD2's placeholders: a 2 s rise, the footprint's half-width 1.0 m and clearance 1.4 m, the
	# car's cylinder 0.9 m and 1.4 m (within the footprint), the panel's 1.5 m and 2 m, the bins'
	# 2 m and 2 m.
	assert_float(repair.rise_seconds).is_equal(2.0)
	assert_float(repair.half_width_m).is_equal(1.0)
	assert_float(repair.clearance_m).is_equal(1.4)
	assert_array([repair.car.radius_m, repair.car.height_m]).is_equal([0.9, 1.4])
	assert_array([repair.lift_panel.radius_m, repair.lift_panel.height_m]).is_equal([1.5, 2.0])
	for bin: StationKind in repair.bins:
		assert_array([bin.radius_m, bin.height_m]).override_failure_message(bin.id).is_equal(
			[2.0, 2.0]
		)
	assert_array(_ids(repair.station_kinds())).is_equal(
		[&"car", &"lift_panel", &"part_bin_1", &"part_bin_2", &"part_bin_3", &"part_picture"]
	)
	for kind: StationKind in repair.station_kinds():
		assert_str(kind.spawn_tag).override_failure_message(kind.id).is_equal(kind.id)


func test_the_car_and_the_panel_hold_the_station() -> void:
	var repair := _repair(_mode())
	var held := ["HandNotTwoHanded", "AtStation", "StationInSight", "ChannelFree", "StationUsable"]
	for kind: StationKind in [repair.car, repair.lift_panel]:
		assert_bool(kind.display).override_failure_message(kind.id).is_false()
		assert_int(kind.actions.size()).override_failure_message(kind.id).is_equal(1)
		var rule := kind.actions[0]
		assert_str(rule.trigger).is_equal("Interact")
		assert_array(_condition_names(rule)).override_failure_message(kind.id).is_equal(held)
		assert_int(rule.effects.size()).override_failure_message(kind.id).is_equal(1)
		assert_object(rule.effects[0]).override_failure_message(kind.id).is_instanceof(HoldStation)
	# The fit: RD2's 5 s. The lift: held until let go, a hit does not stop it (RE6).
	var fit := repair.car.actions[0].effects[0] as HoldStation
	assert_float(fit.seconds).is_equal(5.0)
	assert_bool(fit.endless).is_false()
	var lift := repair.lift_panel.actions[0].effects[0] as HoldStation
	assert_bool(lift.endless).is_true()
	assert_bool(lift.hit_stops).is_false()


func test_each_bin_gives_its_part_behind_the_take_cooldown() -> void:
	var repair := _repair(_mode())
	assert_int(repair.bins.size()).is_equal(3)
	for i: int in repair.bins.size():
		var bin := repair.bins[i]
		assert_bool(bin.display).override_failure_message(bin.id).is_false()
		assert_int(bin.actions.size()).override_failure_message(bin.id).is_equal(1)
		var rule := bin.actions[0]
		assert_str(rule.trigger).is_equal("Interact")
		# No busy-hands condition (RD17's belt rule): a full hand puts its item down for the part.
		assert_array(_condition_names(rule)).override_failure_message(bin.id).is_equal(
			["AtStation", "StationInSight", "Cooldown"]
		)
		var cooldown := rule.conditions[2] as Cooldown
		assert_str(cooldown.key).override_failure_message(bin.id).is_equal("car_part_take")
		assert_float(cooldown.seconds).override_failure_message(bin.id).is_equal(0.25)
		assert_int(rule.effects.size()).override_failure_message(bin.id).is_equal(1)
		var give := rule.effects[0] as GiveItem
		assert_object(give).override_failure_message(bin.id).is_not_null()
		if give != null:
			assert_object(give.kind).override_failure_message(bin.id).is_same(repair.parts[i])
			assert_object(repair.bin_of(repair.parts[i])).is_same(bin)


func test_the_picture_is_a_display_with_no_rule() -> void:
	var repair := _repair(_mode())
	assert_bool(repair.picture.display).is_true()
	assert_array(repair.picture.actions).is_empty()


func test_the_parts_are_one_handed_untagged_capped_and_listed() -> void:
	var mode := _mode()
	var repair := _repair(mode)
	assert_dict(_names(repair.parts)).is_equal(PARTS)
	assert_array(_ids(repair.parts)).is_equal(PARTS.keys())
	var listed := _ids(mode.item_kinds)
	# CE3's bound (RE14): twice the most players plus the most parts plus one, so the hands and the
	# car can never hold every part of a kind.
	var bound := 2 * mode.max_players + mode.find_setting(&"car_parts").max_value + 1
	for kind: ItemKind in repair.parts:
		assert_int(kind.hands).override_failure_message(kind.id).is_equal(1)
		assert_str(kind.spawn_tag).override_failure_message(kind.id).is_empty()
		assert_int(kind.vanish_seconds).override_failure_message(kind.id).is_equal(0)
		assert_int(kind.max_items).override_failure_message(kind.id).is_equal(32)
		assert_int(kind.max_items).override_failure_message(kind.id).is_greater_equal(bound)
		assert_array(kind.target_actions).override_failure_message(kind.id).is_empty()
		assert_bool(listed.has(kind.id)).override_failure_message(String(kind.id)).is_true()


func test_the_car_parts_setting_and_every_type_in_every_match() -> void:
	var mode := _mode()
	var parts := mode.find_setting(&"car_parts")
	assert_object(parts).is_not_null()
	if parts == null:
		return
	assert_bool(parts.is_number()).is_true()
	assert_array([parts.default_value, parts.min_value, parts.max_value]).is_equal([2, 1, 3])
	assert_str(parts.display_name).is_equal("Parts to fit")
	# `tasks` (RD13 (d), GD7 (i)): every type that plays on the map, every match: the House's five
	# (Delivery, the Generator, the photo task, Cooking and car repair); the greybox deals its
	# Delivery by colours alone and never car repair.
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
	var repair := _repair(mode)
	assert_bool(DealTasks.pool_of(mode, PackedStringArray(), HOUSE).has(repair)).is_true()
	assert_bool(DealTasks.pool_of(mode, PackedStringArray(), GREYBOX).has(repair)).is_false()
	assert_int(DealTasks.pool_of(mode, PackedStringArray(), GREYBOX).size()).is_equal(1)


func test_round_accepts_interact_and_stop_raise_from_the_living() -> void:
	var round_phase := _mode().find_phase(&"round")
	for intent: StringName in [Intents.INTERACT, Intents.STOP_RAISE]:
		var froms: Array[int] = []
		for accept: AcceptSpec in round_phase.accepts:
			if accept.intent == intent:
				froms.append(accept.from)
		assert_array(froms).override_failure_message(intent).is_equal([AcceptSpec.From.LIVING])


func test_the_house_fits_car_repair_and_the_greybox_is_asked_for_none() -> void:
	var mode := _mode()
	var repair := _repair(mode)
	var layouts := _layouts(mode)
	var settings := mode.default_settings()
	settings[&"car_parts"] = mode.find_setting(&"car_parts").max_value
	var tags: Array[StringName] = [repair.car_end_tag]
	for kind: StationKind in repair.station_kinds():
		tags.append(kind.spawn_tag)
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
				# RE14: exactly one marker of each.
				assert_int(asked).override_failure_message(String(tag)).is_equal(1)
				assert_int(layouts[path].count(tag)).override_failure_message(String(tag)).is_equal(
					1
				)
			else:
				assert_int(asked).override_failure_message("%s %s" % [path, tag]).is_equal(0)
				assert_int(layouts[path].count(tag)).override_failure_message(String(tag)).is_equal(
					0
				)
	assert_array(repair.layout_problems(layouts[HOUSE])).is_empty()


func _mode() -> GameMode:
	return load(BASE_MODE) as GameMode


func _repair(mode: GameMode) -> CarRepair:
	for type: TaskType in mode.task_types:
		if type is CarRepair:
			return type as CarRepair
	return null


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


## The layouts of the mode's levels as the host reads them, each in its own collision world
## (HostWorldQuery.for_mode), as cooking_content_test.gd reads them.
func _layouts(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts
