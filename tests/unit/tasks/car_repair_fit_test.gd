extends GdUnitTestSuite
## The car repair's fit (the car repair ADR's §2.4, §4, §7's R4 list, RD8 (a), RD10 (d), RE2,
## RE12; #808): the car's refusals in order, a stop losing the fit's progress, a fitter who stops
## claiming, a holder who stops claiming, the completion locking the part, the next PartNeeded,
## the last part completing the task, and the fit and the drop in one tick in both actor orders and
## with the drop in the command step.

const P1 := 1
const P2 := 2
const P3 := 3
const P4 := 4
## The fixture's FIT_SECONDS (1 s) in host ticks.
const FIT_TICKS := 20
const AWAY := Vector3(10, 0, 20)
const FIT_EVENTS: Array[StringName] = [
	&"FitChanged", &"PartFitted", &"TaskState", &"TaskProgress", &"PartNeeded", &"Died"
]


func test_a_fit_starts_for_everyone_and_completes_after_its_seconds() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game)
	var part := _take(game, P2)
	_start_fit(game, P2)
	var started := game.ticked_through()
	for peer: int in [P1, P2, P3]:
		assert_array(_fits(game, peer)).is_equal(
			[{"station": task_state.car, "fitter": P2, "tick": started}]
		)
	_keep_fitting(game, P2, FIT_TICKS - 2)
	assert_array(game.view_of(P3).events_named(&"PartFitted")).is_empty()
	assert_int(task_state.fitted).is_equal(0)
	_keep_fitting(game, P2, 1)
	assert_int(task_state.fitted).is_equal(1)
	# The part left the hand, locked at the car's use spot, as a delivered package.
	var car_at := game.state.stations[task_state.car].position
	assert_int(game.state.players[P2].held_item).is_equal(-1)
	assert_int(part.where).is_equal(ItemState.Where.LOCKED)
	assert_int(part.holder).is_equal(0)
	assert_vector(part.position).is_equal(car_at)
	for peer: int in [P1, P2, P3]:
		var fitted := FixtureCarRepairModes.described(game, peer, [&"PartFitted"])
		assert_array(fitted).is_equal(
			[{"event": &"PartFitted", "station": task_state.car, "item": part.id}]
		)
	# The deal's PartNeeded and DealTasks' announcement; then PartFitted, the subtask's TaskState
	# and TaskProgress, then the next part: no FitChanged on a completion.
	var order := FixtureCarRepairModes.stream(game, P3, FIT_EVENTS)
	var expected: Array[StringName] = [
		&"PartNeeded",
		&"TaskState",
		&"TaskProgress",
		&"FitChanged",
		&"PartFitted",
		&"TaskState",
		&"TaskProgress",
		&"PartNeeded",
	]
	assert_array(order).is_equal(expected)
	var needed := FixtureCarRepairModes.described(game, P3, [&"PartNeeded"])
	assert_str(str(needed[1]["kind"])).is_equal(String(task_state.needed[1]))
	assert_int(needed[1]["station"]).is_equal(task_state.picture)
	var progress := game.view_of(P3).events_named(&"TaskProgress")
	assert_int((progress[progress.size() - 1] as TaskProgressEvent).done).is_equal(1)
	# The hold goes on, and the car stays up.
	assert_object(Channels.of_actor(game.state, P1)).is_not_null()
	assert_array(_ups(game)).is_equal([true])
	assert_object(Channels.on_station(game.state, task_state.car)).is_null()


func test_the_fits_refusals_in_order() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	var car_spot := game.state.stations[task_state.car].position + FixtureCarRepairModes.SHORT
	# The car down: `unavailable` before what the hand holds.
	FixtureCarRepairModes.use(game, P2, task_state.car, 1)
	FixtureModes.run_ticks(game, 1)
	_raise(game)
	# Empty hands at the up car: `empty_hand`.
	FixtureCarRepairModes.use(game, P2, task_state.car, 2)
	FixtureModes.run_ticks(game, 1)
	# A part that is not the one needed now: `wrong_item` (RD8 (a)).
	_take(game, P2, _other_part(game))
	FixtureCarRepairModes.use(game, P2, task_state.car, 3)
	FixtureModes.run_ticks(game, 1)
	# Any other item: `wrong_item`; from outside the car's cylinder: `out_of_reach` first.
	var game_knife := FixtureCombatModes.arm(game, P3, car_spot)
	FixtureModes.run_ticks(game, 1)
	assert_int(game.state.players[P3].held_item).is_equal(game_knife.id)
	FixtureCarRepairModes.use(game, P3, task_state.car, 4)
	FixtureModes.run_ticks(game, 1)
	FixtureItemModes.stand(game, P3, AWAY)
	FixtureStationModes.interact(game, P3, task_state.car, 5)
	FixtureModes.run_ticks(game, 1)
	# A package in the hands: `two_handed` before anything else, even from afar.
	var package := FixtureItemModes.lay(game, &"package", AWAY)
	FixtureItemModes.stand(game, P4, AWAY)
	FixtureItemModes.pick_up(game, P4, package)
	FixtureModes.run_ticks(game, 1)
	FixtureStationModes.interact(game, P4, task_state.car, 6)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal(
		[&"unavailable", &"empty_hand", &"wrong_item"]
	)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"wrong_item", &"out_of_reach"])
	assert_array(FixtureModes.rejections(game, P4)).is_equal([&"two_handed"])
	assert_array(game.view_of(P1).events_named(&"FitChanged")).is_empty()


func test_a_second_fitter_is_busy_and_a_done_task_is_unavailable() -> void:
	var game := _round(1)
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game)
	_take(game, P2)
	_take(game, P3)
	_start_fit(game, P2)
	# P3 holds the right part too, but someone fits already.
	FixtureMoves.claim(game, P3, game.state.players[P3].position)
	FixtureCarRepairModes.use(game, P3, task_state.car, 7)
	_keep_fitting(game, P2, 1)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"busy"])
	_keep_fitting(game, P2, FIT_TICKS - 2)
	assert_bool(task_state.is_done()).is_true()
	# The last part fitted: the task is done, and the car takes no fit (RD11 (a) for the car too).
	FixtureCarRepairModes.use(game, P3, task_state.car, 8)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P3)).is_equal([&"busy", &"unavailable"])


func test_a_stop_loses_the_fits_progress() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game)
	_take(game, P2)
	_start_fit(game, P2)
	_keep_fitting(game, P2, FIT_TICKS - 5)
	# Out of the car's cylinder: the re-check fails, FitChanged(car, 0, tick).
	FixtureItemModes.stand(game, P2, FixtureCarRepairModes.under(0.0, 1.1))
	_keep_fitting(game, P2, 1)
	var stopped := game.ticked_through()
	assert_dict(_fits(game, P3).back()).is_equal(
		{"station": task_state.car, "fitter": 0, "tick": stopped}
	)
	assert_object(Channels.on_station(game.state, task_state.car)).is_null()
	# A new fit starts from nothing: it needs its whole seconds again (RD10 (d)).
	_start_fit(game, P2)
	_keep_fitting(game, P2, FIT_TICKS - 2)
	assert_int(task_state.fitted).is_equal(0)
	_keep_fitting(game, P2, 1)
	assert_int(task_state.fitted).is_equal(1)


func test_a_hit_stops_the_fit_and_so_does_the_car_going_down() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game)
	_take(game, P2)
	_start_fit(game, P2)
	_keep_fitting(game, P2, 3)
	# A hit that does not knock down: the fit stops (RD10 (c)), the hold goes on.
	var fitter_at := game.state.players[P2].position
	FixtureCombatModes.arm(game, P3, fitter_at - Vector3(0, 0, 1))
	FixtureModes.run_ticks(game, 1)
	FixtureCombatModes.use(game, P3, Vector3(0, 0, 1))
	_keep_fitting(game, P2, 1)
	assert_int(game.view_of(P2).events_named(&"Damaged").size()).is_equal(1)
	assert_int(_fits(game, P1).back()["fitter"]).is_equal(0)
	assert_array(_ups(game)).is_equal([true])
	# The fitter's part in hand still, a new fit; then the holder walks off: the fitter dies first.
	_start_fit(game, P2)
	FixtureItemModes.stand(game, P1, AWAY)
	_keep_fitting(game, P2, 1)
	assert_array(_ups(game)).is_equal([true, false])
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	assert_int(task_state.fitted).is_equal(0)


func test_a_fitter_who_stops_claiming_stops_after_the_push_allowance() -> void:
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game)
	_take(game, P2)
	_start_fit(game, P2)
	_keep_fitting(game, P2, 3)
	var last_claim := game.ticked_through()
	# It keeps standing at the car, but sends no claim: the fit runs out of claims (RE2, ZE10).
	FixtureModes.run_ticks(game, AtStation.STALE_TICKS)
	assert_array(_fits(game, P3)).has_size(1)
	FixtureModes.run_ticks(game, 1)
	(
		assert_array(_fits(game, P3))
		. is_equal(
			[
				{"station": task_state.car, "fitter": P2, "tick": last_claim - 3},
				{
					"station": task_state.car,
					"fitter": 0,
					"tick": last_claim + AtStation.STALE_TICKS + 1
				},
			]
		)
	)
	assert_int(task_state.fitted).is_equal(0)
	assert_int(game.state.players[P2].held_item).is_not_equal(-1)


func test_a_holder_who_stops_claiming_keeps_the_car_up() -> void:
	var game := _round()
	# The holder never claims after the hold began: the endless hold is exempt from the claim age.
	FixtureCarRepairModes.hold(game, P1)
	FixtureMoves.claim(game, P1, game.state.players[P1].position)
	FixtureModes.run_ticks(game, 1)
	FixtureModes.run_ticks(game, AtStation.STALE_TICKS * 10)
	assert_array(_ups(game)).is_equal([true])
	assert_object(Channels.of_actor(game.state, P1)).is_not_null()


func test_the_last_part_completes_the_task_and_names_no_part() -> void:
	var game := _round(1)
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game)
	_take(game, P2)
	_start_fit(game, P2)
	_keep_fitting(game, P2, FIT_TICKS - 1)
	assert_bool(task_state.is_done()).is_true()
	var states := game.view_of(P3).events_named(&"TaskState")
	var last := states[states.size() - 1] as TaskStateEvent
	assert_int(last.done).is_equal(1)
	assert_int(last.total).is_equal(1)
	var needed := FixtureCarRepairModes.described(game, P3, [&"PartNeeded"])
	assert_array(needed).has_size(2)
	assert_str(str(needed[1]["kind"])).is_empty()
	# The hold goes on after the last part; its drop kills as always.
	assert_array(_ups(game)).is_equal([true])
	FixtureCombatModes.stop_raise(game, P1, 9)
	FixtureModes.run_ticks(game, 1)
	assert_array(_ups(game)).is_equal([true, false])
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)


func test_the_fit_and_the_drop_in_one_tick_the_fitter_first() -> void:
	# The fitter's id is the lower: its channel steps first, so it fits, then the drop kills it.
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game, P2)
	_take(game, P1)
	_start_fit(game, P1)
	_keep_fitting(game, P1, FIT_TICKS - 2)
	FixtureItemModes.stand(game, P2, AWAY)
	_keep_fitting(game, P1, 1)
	assert_int(task_state.fitted).is_equal(1)
	assert_int(game.state.players[P1].life).is_equal(PlayerState.Life.DEAD)
	assert_array(_tail(game)).is_equal(
		[&"PartFitted", &"TaskState", &"TaskProgress", &"PartNeeded", &"LiftChanged", &"Died"]
	)


func test_the_fit_and_the_drop_in_one_tick_the_holder_first() -> void:
	# The holder's id is the lower: its stop drops the car first, and the fitter dies unfitted.
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game, P1)
	_take(game, P2)
	_start_fit(game, P2)
	_keep_fitting(game, P2, FIT_TICKS - 2)
	FixtureItemModes.stand(game, P1, AWAY)
	_keep_fitting(game, P2, 1)
	assert_int(task_state.fitted).is_equal(0)
	assert_int(game.state.players[P2].life).is_equal(PlayerState.Life.DEAD)
	assert_array(_tail(game)).is_equal([&"LiftChanged", &"FitChanged", &"Died"])
	assert_array(game.view_of(P3).events_named(&"PartFitted")).is_empty()


func test_a_drop_in_the_command_step_kills_the_fitter_before_its_fit_completes() -> void:
	# The fitter's id is the lower, but StopRaise runs in the command step, before ChannelTicks.
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game, P2)
	_take(game, P1)
	_start_fit(game, P1)
	_keep_fitting(game, P1, FIT_TICKS - 2)
	FixtureCombatModes.stop_raise(game, P2, 9)
	_keep_fitting(game, P1, 1)
	assert_int(task_state.fitted).is_equal(0)
	assert_int(game.state.players[P1].life).is_equal(PlayerState.Life.DEAD)
	assert_array(_tail(game)).is_equal([&"LiftChanged", &"FitChanged", &"Died"])


func test_swapping_two_roles_changes_no_fit_event_and_no_refusal() -> void:
	var first := _played({P1: &"crew", P2: &"dissident"})
	var second := _played({P1: &"dissident", P2: &"crew"})
	assert_str(first.state.player(P2).role).is_equal("dissident")
	for peer: int in [P1, P2, P3]:
		var stream := FixtureCarRepairModes.described(first, peer, FIT_EVENTS)
		assert_array(FixtureCarRepairModes.described(second, peer, FIT_EVENTS)).is_equal(stream)
		assert_array(FixtureModes.rejections(second, peer)).is_equal(
			FixtureModes.rejections(first, peer)
		)
	assert_array(FixtureCarRepairModes.stream(first, P3, FIT_EVENTS)).contains(
		[&"FitChanged", &"PartFitted"]
	)
	assert_array(FixtureModes.rejections(first, P2)).is_equal([&"empty_hand", &"wrong_item"])


func test_the_bins_take_a_package_carriers_part_onto_the_belt() -> void:
	# RD17's belt rule: no busy-hands condition at a bin; the package stays in the hands.
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	var bin_at := game.state.stations[task_state.bins[0]].position + FixtureCarRepairModes.SHORT
	var package := FixtureItemModes.lay(game, &"package", bin_at)
	FixtureItemModes.stand(game, P2, bin_at)
	FixtureItemModes.pick_up(game, P2, package)
	FixtureModes.run_ticks(game, 1)
	FixtureCarRepairModes.use(game, P2, task_state.bins[0], 2)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	var player := game.state.players[P2]
	assert_int(player.held_item).is_equal(package.id)
	var belted := game.state.items.get(player.belt_item) as ItemState
	assert_object(belted).is_not_null()
	assert_str(String(belted.kind.id)).is_equal(String(FixtureCarRepairModes.PARTS[0]))
	# At the car the carrier is refused `two_handed` until it puts the package down.
	_raise(game)
	FixtureCarRepairModes.use(game, P2, task_state.car, 3)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_equal([&"two_handed"])


func test_a_bin_at_the_kinds_cap_vanishes_the_part_that_lay_longest() -> void:
	# Cooking's CE3 through GiveItem: never refused for spam while a part of the kind lies loose.
	var game := _round()
	var task_state := FixtureCarRepairModes.state_of(game)
	var part_id := FixtureCarRepairModes.PARTS[0]
	var oldest := FixtureItemModes.lay(game, part_id, AWAY)
	oldest.rest_tick = 1
	for i in FixtureCarRepairModes.MAX_ITEMS - 1:
		FixtureItemModes.lay(game, part_id, AWAY + Vector3(0, 0, i + 1)).rest_tick = 5
	FixtureCarRepairModes.use(game, P2, task_state.bins[0], 1)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	var vanished := game.view_of(P3).events_named(&"ItemVanished")
	assert_array(vanished).has_size(1)
	assert_int((vanished[0] as ItemVanishedEvent).item).is_equal(oldest.id)
	assert_int(game.state.players[P2].held_item).is_not_equal(-1)


## A round of basic(`parts`) with P1 to P4, every player far from the car.
func _round(parts: int = 3) -> Match:
	return FixtureCarRepairModes.in_round(
		FixtureCarRepairModes.basic(), [P1, P2, P3, P4], {}, {&"car_parts": parts}
	)


## `holder` holds the lift until the car is fully up.
func _raise(game: Match, holder: int = P1) -> void:
	FixtureCarRepairModes.hold(game, holder, 50)
	FixtureModes.run_ticks(game, FixtureCarRepairModes.RISE_TICKS + 1)


## `peer` takes `part_id` (the part needed now by default) from its bin. Returns it.
func _take(game: Match, peer: int, part_id: StringName = &"") -> ItemState:
	var task_state := FixtureCarRepairModes.state_of(game)
	var wanted := part_id if not part_id.is_empty() else task_state.next_part()
	var index := FixtureCarRepairModes.PARTS.find(wanted)
	FixtureCarRepairModes.use(game, peer, task_state.bins[index], 60)
	FixtureModes.run_ticks(game, 1)
	return game.state.items.get(game.state.players[peer].held_item) as ItemState


## A part other than the one needed now.
func _other_part(game: Match) -> StringName:
	var needed := FixtureCarRepairModes.state_of(game).next_part()
	for part_id: StringName in FixtureCarRepairModes.PARTS:
		if part_id != needed:
			return part_id
	return &""


## `peer` stands at the car, claims there and presses E: the fit starts this tick.
func _start_fit(game: Match, peer: int) -> void:
	var task_state := FixtureCarRepairModes.state_of(game)
	var spot := game.state.stations[task_state.car].position + FixtureCarRepairModes.SHORT
	FixtureItemModes.stand(game, peer, spot)
	FixtureMoves.claim(game, peer, spot)
	FixtureStationModes.interact(game, peer, task_state.car, 70)
	FixtureModes.run_ticks(game, 1)


## `peer` claims where it stands, then a tick runs, `count` times: an honest fitter.
func _keep_fitting(game: Match, peer: int, count: int) -> void:
	for i in count:
		FixtureMoves.claim(game, peer, game.state.players[peer].position)
		FixtureModes.run_ticks(game, 1)


## The FitChanged events `peer` received, as plain data.
func _fits(game: Match, peer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in game.view_of(peer).events_named(&"FitChanged"):
		found.append(event.to_dict())
	return found


## The `up` of each LiftChanged P3 received, in order.
func _ups(game: Match) -> Array[bool]:
	var found: Array[bool] = []
	for event: MatchEvent in game.view_of(P3).events_named(&"LiftChanged"):
		found.append((event as LiftChangedEvent).up)
	return found


## The names among the fit's events and LiftChanged that P3 received in the last tick.
func _tail(game: Match) -> Array[StringName]:
	var names: Array[StringName] = []
	names.append_array(FIT_EVENTS)
	names.append(&"LiftChanged")
	var found: Array[StringName] = []
	var last := game.ticked_through()
	for emitted: EmittedEvent in game.emitted():
		if emitted.tick == last and emitted.event.event_name() in names:
			if emitted.recipients.has(P3):
				found.append(emitted.event.event_name())
	return found


## A round of winning() with P1, P2 and P3 and `forced` roles: P1 holds the lift; P2 presses the
## up car with empty hands, takes a wrong part and tries, then takes the right part and fits it.
func _played(forced: Dictionary[int, StringName]) -> Match:
	var game := FixtureCarRepairModes.in_round(
		FixtureCarRepairModes.winning(), [P1, P2, P3], {}, {}, 7, forced
	)
	var task_state := FixtureCarRepairModes.state_of(game)
	_raise(game)
	FixtureCarRepairModes.use(game, P2, task_state.car, 1)
	FixtureModes.run_ticks(game, 1)
	_take(game, P2, _other_part(game))
	FixtureCarRepairModes.use(game, P2, task_state.car, 2)
	FixtureModes.run_ticks(game, FixtureCarRepairModes.RISE_TICKS)
	_take(game, P2)
	_start_fit(game, P2)
	_keep_fitting(game, P2, FIT_TICKS)
	return game
