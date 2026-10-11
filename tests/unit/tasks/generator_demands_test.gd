extends GdUnitTestSuite
## The Generator's exact demands (the Generator ADR's GE10, GE15; ARCHITECTURE §9.4.4): exactly
## one `generator` marker and exactly `switches` `switch` markers on each map it plays on, whatever
## the setting and the players. The load check (LayoutCheck) and the lobby's fit check (FitCheck:
## LayoutCheck.demands_of, then Demands.shortfalls) refuse any other count with `markers_exact`;
## every merge of demands keeps the exact set; a banned Generator, or a map it does not list, is
## asked for none of its markers. Fixture values only.

const MAP := FixtureModes.MAP
const PLAYERS := 4


func test_it_demands_its_markers_exactly() -> void:
	var mode := FixtureGeneratorModes.basic()
	var demands := Demands.new(mode)
	FixtureGeneratorModes.type_of(mode).add_demands({&"active_switches": 1}, 10, demands)
	assert_dict(demands.markers).is_equal({&"generator": 1, &"switch": 4})
	assert_bool(demands.exact.has(&"generator")).is_true()
	assert_bool(demands.exact.has(&"switch")).is_true()
	assert_dict(demands.colours).is_empty()


func test_five_switch_markers_are_refused_at_load_and_by_the_fit_check() -> void:
	var mode := FixtureGeneratorModes.basic()
	var five := _with_switches(5)
	var refused := "\n".join(LayoutCheck.run(mode, five))
	assert_str(refused).contains("%s has 5 switch marker(s)" % MAP)
	assert_str(refused).contains("needs exactly 4")
	assert_array(HostText.to_dicts(_fit(mode, five[MAP]))).is_equal(
		[
			{
				"id": &"markers_exact",
				"ids": PackedStringArray(["switch"]),
				"numbers": {&"need": 4, &"have": 5}
			}
		]
	)
	var match_refused := Match.new(mode, 7, FlatWorldQuery.new(), five)
	assert_str("\n".join(match_refused.refusals)).contains("needs exactly 4")


func test_three_switch_markers_are_refused_with_markers_exact_too() -> void:
	var mode := FixtureGeneratorModes.basic()
	var three := _with_switches(3)
	assert_str("\n".join(LayoutCheck.run(mode, three))).contains("has 3 switch marker(s)")
	assert_array(HostText.to_dicts(_fit(mode, three[MAP]))).is_equal(
		[
			{
				"id": &"markers_exact",
				"ids": PackedStringArray(["switch"]),
				"numbers": {&"need": 4, &"have": 3}
			}
		]
	)


func test_four_switch_markers_fit() -> void:
	var mode := FixtureGeneratorModes.basic()
	var four := _with_switches(4)
	assert_array(Array(LayoutCheck.run(mode, four))).is_empty()
	assert_array(_fit(mode, four[MAP])).is_empty()


func test_a_banned_generator_demands_nothing() -> void:
	var mode := FixtureGeneratorModes.basic()
	var banned: Dictionary[StringName, PackedStringArray] = {
		&"banned_task_types": PackedStringArray(["generator"])
	}
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), PLAYERS, banned, MAP
	)
	assert_bool(demands.markers.has(&"switch")).is_false()
	assert_bool(demands.markers.has(&"generator")).is_false()
	assert_array(demands.shortfalls(_with_switches(5)[MAP])).is_empty()


func test_a_map_it_does_not_list_is_asked_for_none_of_its_markers() -> void:
	var mode := FixtureGeneratorModes.basic()
	FixtureGeneratorModes.type_of(mode).maps = PackedStringArray(["fixture://house"])
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), PLAYERS, {}, MAP
	)
	assert_bool(demands.markers.has(&"switch")).is_false()
	assert_bool(demands.markers.has(&"generator")).is_false()


func test_a_tick_systems_exact_demand_stays_exact_through_the_merge() -> void:
	var mode := FixtureGeneratorModes.basic()
	mode.find_phase(&"round").tick_systems.append(ExactTicks.new())
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), PLAYERS, {}, MAP
	)
	assert_int(demands.markers[&"beacon"]).is_equal(2)
	assert_bool(demands.exact.has(&"beacon")).is_true()
	var layouts := _with_switches(4)
	for i in 3:
		layouts[MAP].add_marker(&"beacon", Vector3(-10 - i, 0, 0))
	assert_str("\n".join(LayoutCheck.run(mode, layouts))).contains(
		"has 3 beacon marker(s), and a tick system of phase round needs exactly 2"
	)


## A tick system that asks for exactly two `beacon` markers.
class ExactTicks:
	extends TickSystem

	func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
		into.add_markers(&"beacon", 2, true)


## The fixture layouts with the generator marker and `count` switch markers.
func _with_switches(count: int) -> Dictionary[String, LevelLayout]:
	var spots: Array[Vector3] = []
	for i in count:
		spots.append(Vector3(4 * (i + 1), 0, 20))
	return FixtureGeneratorModes.layouts(spots)


## What the lobby's fit check finds on `layout` with the mode's default settings.
func _fit(mode: GameMode, layout: LevelLayout) -> Array[HostText]:
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), PLAYERS, {}, MAP
	)
	return demands.shortfalls(layout)
