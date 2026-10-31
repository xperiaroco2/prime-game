extends GdUnitTestSuite
## The Generator in `content/` (ARCHITECTURE §9.5.19; the Generator ADR, G5, #800): Charge the
## generator with the engineer's name, description and numbers (GD1, GD6's placeholder radii), in
## the shipped base mode on House alone (GD7, GE15), its `switches` setting (2 to 4, default 3),
## `tasks` at every type a map plays, Round accepting `Interact` from the living, the House's fit
## with the Generator and the greybox's without it, GD12's spacing of the switches and the
## generator scene's panel holding one bar per switch. Every map is read as the host reads it, in
## its own collision world (HostWorldQuery.for_mode), as `zone_content_test.gd` reads House. Like
## the mode check, this test loads `content/` on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const GREYBOX := "res://levels/greybox/greybox.tscn"
const HOUSE := "res://levels/house/house.tscn"
const GENERATOR_SCENE := "res://levels/stations/generator.tscn"
## The world sounds' hearing range (E40's amendment of E33): two players at different switches
## stand at least this far apart (GD12).
const HEARING_M := 12.0


func test_the_generator_has_the_engineers_values() -> void:
	var generator := _generator(_mode())
	assert_object(generator).is_not_null()
	if generator == null:
		return
	assert_str(generator.id).is_equal("generator")
	assert_str(generator.display_name).is_equal("Charge the generator")
	assert_str(generator.description).is_equal(
		"Switch on every active switch, then press the generator's button to charge it."
	)
	assert_float(generator.seconds).is_equal(60.0)
	assert_int(generator.switches).is_equal(4)
	assert_array(Array(generator.maps)).is_equal([HOUSE])
	assert_str(generator.subtasks_setting).is_equal("switches")
	for kind: StationKind in [generator.generator, generator.switch]:
		assert_float(kind.radius_m).override_failure_message(kind.id).is_equal(2.0)
		assert_float(kind.height_m).override_failure_message(kind.id).is_equal(2.0)
	assert_str(generator.generator.spawn_tag).is_equal("generator")
	assert_str(generator.switch.spawn_tag).is_equal("switch")


func test_each_station_kind_is_used_by_its_interact_rule() -> void:
	var generator := _generator(_mode())
	for kind: StationKind in [generator.generator, generator.switch]:
		assert_int(kind.actions.size()).override_failure_message(kind.id).is_equal(1)
		var rule := kind.actions[0]
		assert_str(rule.trigger).is_equal("Interact")
		var conditions: Array[String] = []
		for condition: Condition in rule.conditions:
			conditions.append((condition.get_script() as Script).get_global_name())
		assert_array(conditions).override_failure_message(kind.id).is_equal(
			["HandNotTwoHanded", "AtStation", "StationInSight", "StationUsable"]
		)
		assert_int(rule.effects.size()).is_equal(1)
		assert_object(rule.effects[0]).is_instanceof(UseStation)


func test_the_switches_setting_and_every_type_in_every_match() -> void:
	var mode := _mode()
	var switches := mode.find_setting(&"switches")
	assert_object(switches).is_not_null()
	if switches == null:
		return
	assert_bool(switches.is_number()).is_true()
	assert_array([switches.default_value, switches.min_value, switches.max_value]).is_equal(
		[3, 2, 4]
	)
	# The label is GD1's placeholder, "not a decision": the engineer approves it in the PR.
	assert_str(switches.display_name).is_not_empty()
	# `tasks` (GD7 (i)): every type that plays on the map, every match, so its maximum is the most
	# types one map plays: the House's five (Delivery, the Generator, the photo task,
	# #784, Cooking, #775, and car repair, #810); the greybox deals its Delivery by colours alone
	# (DealTasks deals a smaller pool whole).
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
	assert_int(DealTasks.pool_of(mode, PackedStringArray(), GREYBOX).size()).is_equal(1)
	assert_bool(mode.task_types.has(_generator(mode))).is_true()


func test_round_accepts_interact_from_the_living() -> void:
	var froms: Array[int] = []
	for accept: AcceptSpec in _mode().find_phase(&"round").accepts:
		if accept.intent == &"Interact":
			froms.append(accept.from)
	assert_array(froms).is_equal([AcceptSpec.From.LIVING])


func test_the_house_fits_the_generator_and_the_greybox_is_asked_for_none() -> void:
	var mode := _mode()
	var generator := _generator(mode)
	var layouts := _layouts(mode)
	var settings := mode.default_settings()
	settings[&"switches"] = mode.find_setting(&"switches").max_value
	for path: String in mode.maps:
		var map := layouts[path]
		var demands := LayoutCheck.demands_of(
			mode, PhaseSpec.Level.MAP, settings, mode.max_players, {}, path
		)
		assert_array(Array(demands.shortfalls(map))).override_failure_message(path).is_empty()
		var on_house := path == HOUSE
		var generators := demands.markers.get(generator.generator.spawn_tag, 0) as int
		var switches := demands.markers.get(generator.switch.spawn_tag, 0) as int
		assert_int(generators).override_failure_message(path).is_equal(1 if on_house else 0)
		assert_int(switches).override_failure_message(path).is_equal(
			generator.switches if on_house else 0
		)
	assert_int(layouts[HOUSE].count(generator.generator.spawn_tag)).is_equal(1)
	assert_int(layouts[HOUSE].count(generator.switch.spawn_tag)).is_equal(generator.switches)
	assert_int(layouts[GREYBOX].count(generator.generator.spawn_tag)).is_equal(0)
	assert_int(layouts[GREYBOX].count(generator.switch.spawn_tag)).is_equal(0)


func test_switches_stand_far_enough_apart_on_every_map_that_lists_the_generator() -> void:
	var mode := _mode()
	var generator := _generator(mode)
	var layouts := _layouts(mode)
	assert_bool(generator.maps.is_empty()).is_false()
	for path: String in generator.maps:
		var map := layouts[path]
		assert_int(map.count(generator.switch.spawn_tag)).override_failure_message(path).is_greater(
			1
		)
		assert_array(Array(switch_faults(path, map, generator.switch))).is_empty()


func test_the_spacing_refuses_switches_13_m_apart_and_accepts_16_m_at_radius_2() -> void:
	var switch := StationKind.new()
	switch.spawn_tag = &"switch"
	switch.radius_m = 2.0
	var near := LevelLayout.new()
	near.add_marker(&"switch", Vector3.ZERO)
	near.add_marker(&"switch", Vector3(13, 0, 0))
	assert_array(Array(switch_faults("near", near, switch))).has_size(1)
	var far := LevelLayout.new()
	far.add_marker(&"switch", Vector3.ZERO)
	far.add_marker(&"switch", Vector3(0, 0, 16))
	assert_array(Array(switch_faults("far", far, switch))).is_empty()
	# A storey above does not help: the distance is measured across the floor (the use cylinders
	# stand on it), so a switch 13 m along and 6 m up is still refused.
	var stacked := LevelLayout.new()
	stacked.add_marker(&"switch", Vector3.ZERO)
	stacked.add_marker(&"switch", Vector3(13, 6, 0))
	assert_array(Array(switch_faults("stacked", stacked, switch))).has_size(1)


func test_the_generator_panel_holds_one_bar_per_switch() -> void:
	var generator := _generator(_mode())
	var scene := load(GENERATOR_SCENE) as PackedScene
	assert_object(scene).is_not_null()
	var station: Node3D = auto_free(scene.instantiate() as Node3D)
	var bars := station.get_node_or_null("Bars")
	assert_object(bars).is_not_null()
	var pattern := RegEx.create_from_string("^Bar\\d+$")
	var count := 0
	for child: Node in bars.get_children():
		if pattern.search(String(child.name)) != null:
			count += 1
	assert_int(count).is_equal(generator.switches)


## Every two `kind` markers on `layout` closer across the floor than the hearing range plus both
## use cylinders' radii (GD12: 16 m at GD6's 2 m), so two players anywhere in the two cylinders,
## and each switch's device at its cylinder's edge, stand at least 12 m apart. Measured on the
## horizontal plane: the cylinders are upright, and a storey between two switches would let a 3D
## distance pass two players closer than 12 m.
static func switch_faults(
	path: String, layout: LevelLayout, kind: StationKind
) -> PackedStringArray:
	var found := PackedStringArray()
	var at_least := HEARING_M + 2.0 * kind.radius_m
	var positions := layout.positions(kind.spawn_tag)
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			var a := positions[i]
			var b := positions[j]
			var apart := Vector2(a.x - b.x, a.z - b.z).length()
			if apart < at_least:
				found.append(
					(
						"%s: switches at %s and %s stand %.1f m apart, fewer than %.1f m"
						% [path, a, b, apart, at_least]
					)
				)
	return found


func _mode() -> GameMode:
	return load(BASE_MODE) as GameMode


func _generator(mode: GameMode) -> Generator:
	for type: TaskType in mode.task_types:
		if type is Generator:
			return type as Generator
	return null


## The layouts of the mode's levels as the host reads them, each in its own collision world
## (HostWorldQuery.for_mode), as zone_content_test.gd reads them: the scenarios' flat fake would
## read House's storeys as one floor (#681).
func _layouts(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts
