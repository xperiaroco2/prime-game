extends GdUnitTestSuite
## CircleViews draws no greybox cylinder over the stations the base mode's own phases place (#1703:
## the lobby's tap, pinball, mirror and booth, StationTicks; no task type holds them): their look is
## the level's art and the aim chip names them. Delivery's circle still gets its cylinder, and a
## kind the mode does not name at all still gets the fallback.

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_lobby_stations_get_no_cylinder() -> void:
	var mode := load(BASE_MODE) as GameMode
	var placed: Array[StringName] = []
	for kind: StationKind in Stations.kinds_in(mode):
		if Stations.owner_of(mode, kind) == null:
			placed.append(kind.id)
	assert_array(placed).contains([&"tap", &"pinball", &"mirror"])
	for id: StringName in placed:
		assert_bool(CircleViews.draws(mode, id)).override_failure_message(String(id)).is_false()


func test_a_kind_the_mode_does_not_name_keeps_the_fallback() -> void:
	var mode := load(BASE_MODE) as GameMode
	assert_bool(CircleViews.draws(mode, &"elsewhere")).is_true()
