extends GdUnitTestSuite
## ZoneProgress (ARCHITECTURE §4.2; ZE4 and ZE5 of the zone task ADR): to everyone alike, only when
## a zone's counting changed since its last one, at most once per zone per WINDOW_TICKS (a change
## inside the window goes out at its end with that tick's state), done in its own tick and before
## the task's TaskState and TaskProgress, zones in station-id order. It names no player. Driven by
## MoveClaims on a seeded match whose deal ran (FixtureZoneModes: zones A and B, 20 ticks each).

const P1 := 1
const P2 := 2
const P3 := 3
const A := Vector3(0, 0, 20)
const B := Vector3(3, 0, 20)
const SOUTH := Vector3(0, 0, -1)
## Just inside zone A's edge, and one walking step (0.2 m) further, just outside it.
const IN := A + SOUTH * 1.4
const OUT := A + SOUTH * 1.6


func test_a_start_and_a_stop_each_send_one_event_to_everyone_alike() -> void:
	var game := _round([P1, P2, P3])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 1)
	var started := game.ticked_through()
	FixtureZoneModes.hold(game, [P1], 7)
	var a := _zone_id(game, 0)
	assert_array(FixtureZoneModes.progress(game, P1)).is_equal(
		[FixtureZoneModes.sent(a, 1, true, started)]
	)
	FixtureZoneModes.walk(game, P1, A + SOUTH * 1.5)
	var ticks := FixtureZoneModes.ticks_of(game, 0)
	FixtureZoneModes.walk(game, P1, OUT)
	var stopped := game.ticked_through()
	FixtureZoneModes.hold(game, [P1], 10)
	var expected: Array[Dictionary] = [
		FixtureZoneModes.sent(a, 1, true, started), FixtureZoneModes.sent(a, ticks, false, stopped)
	]
	for peer: int in [P1, P2, P3]:
		assert_array(FixtureZoneModes.progress(game, peer)).is_equal(expected)


func test_it_names_no_player() -> void:
	var event := ZoneProgressEvent.new(4, 3, 20, true, 99)
	assert_array(event.to_dict().keys()).contains_exactly(
		["station", "ticks", "needed", "counting", "tick"]
	)
	assert_int(event.audience().kind).is_equal(Audience.Kind.EVERYONE)


func test_a_stop_inside_the_window_goes_out_at_its_end_with_that_ticks_state() -> void:
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, IN)
	FixtureZoneModes.hold(game, [P1], 2)
	var started := game.ticked_through() - 1
	FixtureMoves.step(game, P1, SOUTH * 0.2)
	FixtureZoneModes.hold(game, [P1], 2)
	var a := _zone_id(game, 0)
	assert_array(FixtureZoneModes.progress(game, P1)).is_equal(
		[FixtureZoneModes.sent(a, 1, true, started)]
	)
	FixtureZoneModes.hold(game, [P1], 1)
	assert_int(game.ticked_through()).is_equal(started + ZoneTask.WINDOW_TICKS)
	(
		assert_array(FixtureZoneModes.progress(game, P1))
		. is_equal(
			[
				FixtureZoneModes.sent(a, 1, true, started),
				FixtureZoneModes.sent(a, 2, false, started + ZoneTask.WINDOW_TICKS),
			]
		)
	)


func test_a_stop_and_a_restart_inside_the_window_still_send_the_true_ticks_at_its_end() -> void:
	# Counting again at the window's end, as announced, but one tick behind what a client
	# extrapolated from the start: it gets the true ticks.
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, IN)
	FixtureZoneModes.hold(game, [P1], 1)
	var started := game.ticked_through()
	FixtureMoves.step(game, P1, SOUTH * 0.2)
	FixtureMoves.step(game, P1, -SOUTH * 0.2)
	FixtureZoneModes.hold(game, [P1], 3)
	var a := _zone_id(game, 0)
	assert_int(game.ticked_through()).is_equal(started + ZoneTask.WINDOW_TICKS)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(ZoneTask.WINDOW_TICKS)
	(
		assert_array(FixtureZoneModes.progress(game, P1))
		. is_equal(
			[
				FixtureZoneModes.sent(a, 1, true, started),
				FixtureZoneModes.sent(
					a, ZoneTask.WINDOW_TICKS, true, started + ZoneTask.WINDOW_TICKS
				),
			]
		)
	)
	FixtureZoneModes.hold(game, [P1], 6)
	assert_int(FixtureZoneModes.progress(game, P1).size()).is_equal(2)


func test_crossing_the_edge_every_tick_for_100_ticks_sends_at_most_one_event_per_window() -> void:
	# A zone of 10 s (200 ticks): 50 ticks inside do not finish it.
	var game := FixtureZoneModes.in_round(FixtureZoneModes.basic(2, 10.0), [P1, P2])
	FixtureZoneModes.put(game, P1, IN)
	var sent_at: Array[int] = []
	for i in 100:
		FixtureMoves.step(game, P1, SOUTH * 0.2 if i % 2 == 0 else -SOUTH * 0.2)
	for event: Dictionary in FixtureZoneModes.progress(game, P2):
		sent_at.append(event["tick"] as int)
	assert_int(sent_at.size()).is_greater_equal(1)
	assert_int(sent_at.size()).is_less_equal(100 / ZoneTask.WINDOW_TICKS + 1)
	for i in range(1, sent_at.size()):
		assert_int(sent_at[i] - sent_at[i - 1]).is_greater_equal(ZoneTask.WINDOW_TICKS)
	assert_int(FixtureZoneModes.ticks_of(game, 0)).is_equal(50)


func test_done_goes_out_in_its_own_tick_inside_a_window_before_the_task_events() -> void:
	var game := _round([P1, P2])
	FixtureZoneModes.put(game, P1, IN)
	FixtureZoneModes.hold(game, [P1], 1)
	var started := game.ticked_through()
	FixtureZoneModes.hold(game, [P1], 15)
	FixtureMoves.step(game, P1, SOUTH * 0.2)
	var stopped := game.ticked_through()
	FixtureMoves.step(game, P1, -SOUTH * 0.2)
	FixtureZoneModes.hold(game, [P1], 2)
	var view := game.view_of(P2)
	var seen := view.event_names().size()
	FixtureZoneModes.hold(game, [P1], 1)
	var done := game.ticked_through()
	assert_int(done - stopped).is_less(ZoneTask.WINDOW_TICKS)
	var a := _zone_id(game, 0)
	(
		assert_array(FixtureZoneModes.progress(game, P2))
		. is_equal(
			[
				FixtureZoneModes.sent(a, 1, true, started),
				FixtureZoneModes.sent(a, 16, false, stopped),
				FixtureZoneModes.sent(a, FixtureZoneModes.NEEDED, false, done),
			]
		)
	)
	assert_array(_task_events(game.view_of(P2).event_names().slice(seen))).is_equal(
		[&"ZoneProgress", &"TaskState", &"TaskProgress"]
	)


func test_two_zones_done_in_one_tick_go_out_in_station_id_order_each_with_its_task_events() -> void:
	# P2 works zone A and P1 zone B: zones go in station-id order, whoever stands in them.
	var game := _round([P1, P2])
	FixtureZoneModes.put(game, P1, B)
	FixtureZoneModes.put(game, P2, A)
	FixtureZoneModes.hold(game, [P1, P2], 1)
	var a := _zone_id(game, 0)
	var b := _zone_id(game, 1)
	assert_int(a).is_less(b)
	var started := game.ticked_through()
	assert_array(FixtureZoneModes.progress(game, P1)).is_equal(
		[FixtureZoneModes.sent(a, 1, true, started), FixtureZoneModes.sent(b, 1, true, started)]
	)
	FixtureZoneModes.hold(game, [P1, P2], FixtureZoneModes.NEEDED - 2)
	var seen := game.view_of(P1).event_names().size()
	FixtureZoneModes.hold(game, [P1, P2], 1)
	var done := game.ticked_through()
	(
		assert_array(_task_events(game.view_of(P1).event_names().slice(seen)))
		. is_equal(
			[
				&"ZoneProgress",
				&"TaskState",
				&"TaskProgress",
				&"ZoneProgress",
				&"TaskState",
				&"TaskProgress",
			]
		)
	)
	(
		assert_array(FixtureZoneModes.progress(game, P1).slice(2))
		. is_equal(
			[
				FixtureZoneModes.sent(a, FixtureZoneModes.NEEDED, false, done),
				FixtureZoneModes.sent(b, FixtureZoneModes.NEEDED, false, done),
			]
		)
	)
	var progress := game.view_of(P1).events_named(&"TaskProgress")
	assert_dict(progress[progress.size() - 2].to_dict()).is_equal({"done": 1, "total": 2})
	assert_dict(progress[progress.size() - 1].to_dict()).is_equal({"done": 2, "total": 2})


func test_several_players_in_one_zone_send_one_event() -> void:
	var game := _round([P1, P2, P3])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.put(game, P2, A + SOUTH)
	FixtureZoneModes.put(game, P3, A - SOUTH)
	FixtureZoneModes.hold(game, [P1, P2, P3], 6)
	assert_int(FixtureZoneModes.progress(game, P1).size()).is_equal(1)


func test_a_produced_event_round_trips_on_the_wire() -> void:
	var game := _round([P1])
	FixtureZoneModes.put(game, P1, A)
	FixtureZoneModes.hold(game, [P1], 1)
	var event := game.view_of(P1).events_named(&"ZoneProgress")[0]
	var schema := WireSchema.game(true)
	var message := WireMessage.new(event.event_name(), event.to_dict())
	var kind := schema.kind_of(message.name)
	var decoded := schema.decode(kind, schema.encode(message))
	assert_object(decoded).is_not_null()
	assert_dict(decoded.fields).is_equal(event.to_dict())


func _round(peers: Array[int]) -> Match:
	return FixtureZoneModes.in_round(FixtureZoneModes.basic(2), peers)


func _zone_id(game: Match, index: int) -> int:
	return FixtureZoneModes.state_of(game).stations[index]


## The zone and task events among `names`, in order.
func _task_events(names: Array[StringName]) -> Array[StringName]:
	var found: Array[StringName] = []
	for name: StringName in names:
		if name in [&"ZoneProgress", &"TaskState", &"TaskProgress"]:
			found.append(name)
	return found
