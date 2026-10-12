extends GdUnitTestSuite
## Cooking's demands (the cooking ADR's CE14, G8's per-map demands; ARCHITECTURE §9.4.4): exactly
## one marker each for the order board, the herb board and the grill, exactly as many `herb_bed`
## markers as herbs, at least N `place` markers (N the setting) and at least one marker per box
## kind's tag, whatever the players; no colours. The load check (LayoutCheck) and the lobby's fit
## check refuse a second grill and a fourth bed; a map Cooking does not list, or a banned Cooking,
## is asked for none of its markers. Fixture values only.

const MAP := FixtureModes.MAP
const PLAYERS := 4


func test_it_demands_its_markers() -> void:
	var mode := FixtureCookingModes.basic()
	var demands := Demands.new(mode)
	FixtureCookingModes.type_of(mode).add_demands({&"burgers": 2}, 10, demands)
	var expected := {&"order_board": 1, &"herb_board": 1, &"grill": 1, &"herb_bed": 3, &"place": 2}
	for box_id: StringName in FixtureCookingModes.BOXES:
		expected[box_id] = 1
	assert_dict(demands.markers).is_equal(expected)
	for tag: StringName in [&"order_board", &"herb_board", &"grill", &"herb_bed"]:
		assert_bool(demands.exact.has(tag)).override_failure_message(tag).is_true()
	assert_bool(demands.exact.has(&"place")).is_false()
	assert_bool(demands.exact.has(&"box_bun_a")).is_false()
	assert_dict(demands.colours).is_empty()


func test_zero_burgers_still_demand_the_fixed_stations_and_no_place() -> void:
	var mode := FixtureCookingModes.basic(0)
	var demands := Demands.new(mode)
	FixtureCookingModes.type_of(mode).add_demands({&"burgers": 0}, 10, demands)
	assert_int(demands.markers[&"grill"]).is_equal(1)
	assert_int(demands.markers[&"herb_bed"]).is_equal(3)
	assert_int(demands.markers.get(&"place", 0)).is_equal(0)


func test_the_fixture_map_fits() -> void:
	var mode := FixtureCookingModes.basic(FixtureCookingModes.MOST_BURGERS)
	assert_array(Array(LayoutCheck.run(mode, FixtureCookingModes.layouts()))).is_empty()
	assert_array(_fit(mode, FixtureCookingModes.layouts()[MAP])).is_empty()


func test_a_second_grill_and_a_fourth_bed_are_refused() -> void:
	var mode := FixtureCookingModes.basic()
	var beds: Array[Vector3] = []
	beds.append_array(FixtureCookingModes.BED_SPOTS)
	beds.append(Vector3(12, 0, 20))
	var layouts := FixtureCookingModes.layouts(beds)
	layouts[MAP].add_marker(&"grill", Vector3(14, 0, 20))
	var refused := "\n".join(LayoutCheck.run(mode, layouts))
	assert_str(refused).contains("%s has 2 grill marker(s)" % MAP)
	assert_str(refused).contains("%s has 4 herb_bed marker(s)" % MAP)
	var found := HostText.to_dicts(_fit(mode, layouts[MAP]))
	var ids: Array = []
	for text: Dictionary in found:
		ids.append(text["id"])
	assert_array(ids).contains([&"markers_exact"])


func test_too_few_places_and_a_missing_box_marker_are_refused_by_the_fit_check() -> void:
	var mode := FixtureCookingModes.basic(FixtureCookingModes.MOST_BURGERS)
	var layouts := FixtureCookingModes.layouts(
		FixtureCookingModes.BED_SPOTS, FixtureCookingModes.PLACE_SPOTS.slice(0, 2)
	)
	var subjects: Array = []
	for text: Dictionary in HostText.to_dicts(_fit(mode, layouts[MAP])):
		subjects.append_array(Array(text["ids"] as PackedStringArray))
	assert_array(subjects).contains(["place"])


func test_a_map_it_does_not_list_is_asked_for_none_of_its_markers() -> void:
	var mode := FixtureCookingModes.basic()
	FixtureCookingModes.type_of(mode).maps = PackedStringArray(["fixture://house"])
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), PLAYERS, {}, MAP
	)
	for tag: StringName in [&"order_board", &"grill", &"herb_bed", &"place", &"box_raw_a"]:
		assert_bool(demands.markers.has(tag)).override_failure_message(tag).is_false()


func test_a_banned_cooking_demands_nothing() -> void:
	var mode := FixtureCookingModes.basic()
	var banned: Dictionary[StringName, PackedStringArray] = {
		&"banned_task_types": PackedStringArray(["cooking"])
	}
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), PLAYERS, banned, MAP
	)
	assert_bool(demands.markers.has(&"grill")).is_false()
	assert_bool(demands.markers.has(&"herb_bed")).is_false()


## What the lobby's fit check finds on `layout` with the mode's default settings.
func _fit(mode: GameMode, layout: LevelLayout) -> Array[HostText]:
	var demands := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), PLAYERS, {}, MAP
	)
	return demands.shortfalls(layout)
