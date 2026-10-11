extends GdUnitTestSuite
## ZoneViews' pure parts (ARCHITECTURE §4.7; the zone task ADR's ZE8, #650): which station kinds
## are zones in the client's own mode, and the fill as a function of the station (as the model
## folded it from ZoneProgress) and the estimated host tick: extrapolated while the zone counts,
## still while it does not, capped at its needed ticks, full only once the host says it is done.

const NEEDED := 20


func test_a_station_kind_is_a_zone_only_when_a_zone_task_of_the_mode_holds_it() -> void:
	var mode := _mode()
	assert_object(ZoneViews.zone_task(mode, &"zone")).is_same(mode.task_types[1])
	assert_object(ZoneViews.zone_task(mode, &"circle")).is_null()
	assert_object(ZoneViews.zone_task(mode, &"unknown")).is_null()
	assert_object(ZoneViews.zone_task(null, &"zone")).is_null()


func test_a_zone_with_no_progress_yet_is_empty() -> void:
	var zone := ClientModel.Station.new()
	assert_int(ZoneViews.ticks_at(zone, 500)).is_equal(0)
	assert_float(ZoneViews.fill(zone, 500)).is_equal(0.0)


func test_a_counting_zone_runs_on_from_its_events_tick_and_stops_at_needed() -> void:
	var zone := _zone(4, true, 100)
	assert_int(ZoneViews.ticks_at(zone, 100)).is_equal(4)
	assert_int(ZoneViews.ticks_at(zone, 106)).is_equal(10)
	assert_float(ZoneViews.fill(zone, 106)).is_equal_approx(0.5, 1e-6)
	assert_int(ZoneViews.ticks_at(zone, 116)).is_equal(NEEDED)
	assert_int(ZoneViews.ticks_at(zone, 400)).is_equal(NEEDED)
	assert_float(ZoneViews.fill(zone, 400)).is_equal(1.0)
	# Capped, but not done: only the host's ZoneProgress makes it done.
	assert_bool(zone.done).is_false()


func test_a_host_tick_behind_the_event_or_unknown_adds_nothing() -> void:
	var zone := _zone(4, true, 100)
	assert_int(ZoneViews.ticks_at(zone, 97)).is_equal(4)
	assert_int(ZoneViews.ticks_at(zone, -1)).is_equal(4)


func test_a_zone_that_does_not_count_stands_still() -> void:
	var zone := _zone(10, false, 100)
	assert_int(ZoneViews.ticks_at(zone, 100)).is_equal(10)
	assert_int(ZoneViews.ticks_at(zone, 300)).is_equal(10)
	assert_float(ZoneViews.fill(zone, 300)).is_equal_approx(0.5, 1e-6)


func test_a_done_zone_is_full_whatever_the_tick() -> void:
	var zone := _zone(NEEDED, false, 100)
	zone.done = true
	assert_int(ZoneViews.ticks_at(zone, -1)).is_equal(NEEDED)
	assert_float(ZoneViews.fill(zone, 0)).is_equal(1.0)


func test_the_fill_never_runs_backwards_as_the_host_tick_goes_on() -> void:
	var zone := _zone(7, true, 50)
	for tick: int in range(40, 120):
		assert_bool(ZoneViews.fill(zone, tick) <= ZoneViews.fill(zone, tick + 1)).is_true()


## A counting or still zone as the model holds it after a ZoneProgress.
func _zone(ticks: int, counting: bool, at_tick: int) -> ClientModel.Station:
	var zone := ClientModel.Station.new()
	zone.kind = &"zone"
	zone.ticks = ticks
	zone.needed = NEEDED
	zone.counting = counting
	zone.progress_tick = at_tick
	return zone


## A mode with a delivery circle and a zone task, from the fixtures.
static func _mode() -> GameMode:
	var mode := GameMode.new()
	var package := ItemKind.new()
	package.id = &"package"
	mode.task_types.append(FixtureDeliveryModes.delivery(package))
	mode.task_types.append(FixtureZoneModes.zone_task())
	return mode
