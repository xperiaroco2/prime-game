extends GdUnitTestSuite
## TaskType.station_kinds() (the delivery-by-meaning ADR's DE4, #827): by default today's
## reflection over a type's StationKind properties; an override's kinds are what Stations,
## CircleViews and the other readers find.


func test_the_default_is_the_reflection_over_the_station_kind_properties() -> void:
	var type := FixtureStationType.new()
	type.panel = FixtureKindsType.kind(&"panel", &"panel")
	assert_array(type.station_kinds()).is_equal(_reflected(type))
	assert_array(type.station_kinds()).is_equal([type.panel])
	var delivery := Delivery.new()
	delivery.circle = FixtureKindsType.kind(&"circle", &"circle")
	assert_array(delivery.station_kinds()).is_equal(_reflected(delivery))


func test_a_type_with_no_kind_set_finds_none() -> void:
	assert_array(FixtureStationType.new().station_kinds()).is_empty()
	assert_array(TaskType.new().station_kinds()).is_empty()


func test_an_override_s_kinds_are_the_ones_stations_and_circle_views_find() -> void:
	var kind_a := FixtureKindsType.kind(&"kind_a", &"tag_a")
	var kind_b := FixtureKindsType.kind(&"kind_b", &"tag_b")
	var type := FixtureKindsType.of(&"kinds", [kind_a, kind_b])
	var mode := GameMode.new()
	mode.task_types = [type]
	assert_array(Stations.kinds_of(type)).is_equal([kind_a, kind_b])
	assert_array(Stations.kinds_in(mode)).is_equal([kind_a, kind_b])
	assert_object(Stations.owner_of(mode, kind_b)).is_same(type)
	assert_object(CircleViews.station_kind(mode, &"kind_b")).is_same(kind_b)
	assert_object(CircleViews.station_kind(mode, &"nothing")).is_null()


## What the finders did before the one finder: every stored property holding a StationKind.
func _reflected(type: TaskType) -> Array[StationKind]:
	var found: Array[StationKind] = []
	for property: Dictionary in type.get_property_list():
		if ((property["usage"] as int) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var value: Variant = type.get(property["name"] as String)
		if value is StationKind:
			found.append(value as StationKind)
	return found
