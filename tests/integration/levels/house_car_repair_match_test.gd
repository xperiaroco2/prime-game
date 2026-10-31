extends GdUnitTestSuite
## The car repair on the House (#812, car repair R8; the car repair ADR's §7 "Integration tests on
## House"), the one map it plays on, in the host's real collision world (HostWorldQuery.for_mode,
## as HostSession builds it). Bots never play the House (ARCHITECTURE §9.7), so no scenario plays
## it: each command goes into Match as server/ would send it, and ScenarioInvariants checks every
## call and every tick, as the runners check theirs (a BotScenario with no `never`: its §5
## invariants, every task event, LiftChanged, PartNeeded, FitChanged and PartFitted among them,
## reaching every present player and no one else; no seed, no return key, the voice and the
## snapshots). The match is the shipped base mode on the House with the data's numbers, set up as
## a scenario's setup would be: forced roles, then ChangeSettings with the map, one task, every
## other task type banned (the base mode deals several on the House) and CAR_PARTS parts; the
## package carrier's match deals Delivery beside it (its packages are the House's two-handed
## items).
## - The deal: every station on its marker, the car's use spot on the garage floor (RE16), no
##   spawn or respawn marker of the House inside the car's footprint box (RE7, by the type's own
##   in_box), the raised car too low to stand under and higher than a crouched player (RD1), its
##   scene's lowered body (layer 4) above the floor and below `clearance_m`.
## - RE15's "no view": from every point of the panel's cylinder where a player fits and the panel
##   is in sight, at every eye height of the crouch band (`crouch_eye_height_m` to `eye_height_m`,
##   every 0.1 m with both ends; R8 lands after the crouch's 727a, #790: the band is its own),
##   no line of sight to the space under the raised car; the voice distance (RD2).
## - A part from each bin; a package carrier's take onto the belt (RD17), then `two_handed` at the
##   panel.
## - A full repair from players' commands: the holder at the panel, the fitter fetching each
##   needed part from its bin in storage and fitting it under the raised car.
## - The drop: the holder lets go and only the fitter, under the car, dies; a bystander beside the
##   car and one past its end live.
## - The chaos run's class-5 case: the holder's claim from the panel into the box, then a Swap in
##   the same tick: the hold stops, the holder dies once, no KnockedDown after its Died.
## Each match with a drop or a fit is replayed from its command log (Match.replay): the same events
## to the same recipients on the same ticks, nothing in the replay's `diagnostics`. Players move
## only by MoveClaims the host accepts (each with its own client clock, the climb from storage by
## the pantry stairs), as in house_cooking_test.gd.

const HOUSE := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
const CAR_SCENE := "res://levels/stations/car.tscn"
## This test's own seed (#812).
const SEED := 812_000_000_001
const BOTS := 4
const DISSIDENT := 1
const HOLDER := 2
const FITTER := 3
const OTHER_CREW := 4
## The parts setting at its most (the base mode's max_value).
const CAR_PARTS := 3
## Delivery's packages beside the car repair, in the package carrier's match.
const PACKAGES := 1
## The car's layer (4) in a collision mask: the lift's body, which the host never sees.
const MOVERS_LAYER := 8
## Up the pantry stairs from storage to the pantry (house-map §5; house_cooking_test's walk).
const PANTRY_UP: Array[Vector3] = [
	Vector3(25, -3.2, 29.0),
	Vector3(25, -2.31, 26.5),
	Vector3(26, -1.6, 24.75),
	Vector3(27, -0.95, 26.0),
	Vector3(27, 0, 29.0),
]
## Below this height a player stands in the basement and climbs the pantry stairs first.
const BASEMENT_Y := -1.0
## How far a waypoint's floor may lie from its height.
const LEVEL_M := 0.5
const NEAR := 0.01
## The longest piece of a walk, its ticks at walking speed well under MovementRule.MAX_TICK_CREDIT.
const HOP_M := 30.0
## How far from an item a taker stands (InReach's 2 m with room to spare).
const BESIDE_M := 1.0
## RE15's grids: the box every 0.5 m (with both ends) from just above the floor; the eyes every
## 0.1 m; the panel's cylinder every 0.25 m.
const BOX_GRID_M := 0.5
const FLOOR_LIFT_M := 0.05
const EYE_STEP_M := 0.1
const ORIGIN_GRID_M := 0.25
## RD2: the panel's whole cylinder within the voice radius less this of the car's use spot.
const VOICE_MARGIN_M := 1.0
## How far outside the box the bystanders stand, at least and at most.
const OUTSIDE_M: Array[float] = [0.3, 0.5, 0.8, 1.2]
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05

var _game: Match
var _world: HostWorldQuery
## The House alone, for the capsule checks (HostWorldQuery answers rays only).
var _level: LevelWorld
var _layout: LevelLayout
var _invariants: ScenarioInvariants
var _peers: ScenarioPeers
var _problems := PackedStringArray()
var _seqs: Dictionary[int, int] = {}
## Each player's Corrections when the round began (PlacePlayers sends one with each placement).
var _placed: Dictionary[int, int] = {}
## Each player's client clock: the client tick of its last claim.
var _clocks: Dictionary[int, int] = {}
## Each player's host tick of its last claim.
var _claimed_at: Dictionary[int, int] = {}


func test_the_deal_places_each_station_on_its_marker_and_the_car_s_box_holds_no_spawn() -> void:
	_start()
	var type := _type()
	var task_state := _state()
	_assert_on_marker(task_state.car, type.car.spawn_tag)
	_assert_on_marker(task_state.panel, type.lift_panel.spawn_tag)
	_assert_on_marker(task_state.picture, type.picture.spawn_tag)
	assert_int(task_state.bins.size()).is_equal(type.bins.size())
	for i in task_state.bins.size():
		_assert_on_marker(task_state.bins[i], type.bins[i].spawn_tag)
	assert_int(task_state.total()).is_equal(CAR_PARTS)
	var stations := 2 + 3 + type.bins.size()  # the lobby's tap and pinball, then the deal's
	for peer: int in _game.state.present_peers():
		var view := _game.view_of(peer)
		assert_int(view.events_named(&"StationPlaced").size()).is_equal(stations)
		assert_int(view.events_named(&"PartNeeded").size()).is_equal(1)
	# RE16: the car's use spot (under the car, its middle) lies on the garage floor of the host's
	# world, as does car_end, which gives the axis.
	var car := _station(task_state.car).position
	var under := _world.floor_below(car + Vector3.UP)
	assert_bool(under != WorldQuery.NO_FLOOR).is_true()
	assert_float(under.y).is_equal_approx(car.y, NEAR)
	assert_float(task_state.car_end.y).is_equal_approx(car.y, NEAR)
	assert_float(_flat(task_state.car_end - car).length()).is_greater(1.0)
	# RE7: no spawn or respawn marker (nor any other but the car's own) inside the footprint box,
	# by the type's own box test.
	for tag: StringName in [&"round_player", &"respawn"]:
		assert_int(_layout.count(tag)).override_failure_message(String(tag)).is_greater(0)
	var inside: Array[String] = []
	for tag: StringName in _layout.tags():
		if tag == type.car.spawn_tag or tag == type.car_end_tag:
			continue
		for at: Vector3 in _layout.positions(tag):
			if type.in_box(car, task_state.car_end, at):
				inside.append("%s at %s" % [tag, at])
	assert_array(inside).override_failure_message("in the car's box: %s" % [inside]).is_empty()
	# The check can fail: the use spot itself lies in the box.
	assert_bool(type.in_box(car, task_state.car_end, car)).is_true()
	_assert_clean()


func test_the_raised_car_is_too_low_to_stand_under_and_its_body_rises_to_it() -> void:
	_start()
	var type := _type()
	var rules := _game.mode.player_rules
	# RD1: only a crouched player gets under the raised car (height alone).
	assert_float(rules.crouch_height_m).is_less(type.clearance_m)
	assert_float(type.clearance_m).is_less(rules.capsule_height_m)
	# The car scene's lowered body (its layer-4 shapes) lies above the floor and below
	# clearance_m, so R7's drive, which raises its underside to clearance_m, always raises it.
	var root := auto_free((load(CAR_SCENE) as PackedScene).instantiate()) as Node3D
	var use_spot := _first_in_group(root, &"spawn_car") as Node3D
	assert_object(use_spot).is_not_null()
	if use_spot == null:
		return
	var floor_y := _local_transform(root, use_spot).origin.y
	var lowest := INF
	var shapes := 0
	for body: CollisionObject3D in _bodies(root):
		if (body.collision_layer & MOVERS_LAYER) == 0:
			continue
		for child: Node in body.get_children():
			var shape := child as CollisionShape3D
			if shape == null or shape.disabled:
				continue
			var box := shape.shape as BoxShape3D
			assert_object(box).override_failure_message(String(shape.name)).is_not_null()
			if box == null:
				continue
			shapes += 1
			var at := _local_transform(root, shape)
			var half := box.size / 2.0
			for corner in 8:
				var offset := Vector3(
					half.x if corner & 1 else -half.x,
					half.y if corner & 2 else -half.y,
					half.z if corner & 4 else -half.z
				)
				lowest = minf(lowest, (at * offset).y - floor_y)
	assert_int(shapes).is_greater(0)
	assert_float(lowest).is_greater(0.0)
	assert_float(lowest).is_less(type.clearance_m)


func test_the_panel_sees_nothing_under_the_car_from_any_eye_of_the_crouch_band() -> void:
	_start()
	var type := _type()
	var task_state := _state()
	var rules := _game.mode.player_rules
	var car := _station(task_state.car).position
	var panel := _station(task_state.panel)
	var grid := _box_grid(car, task_state.car_end, type)
	assert_int(grid.size()).is_greater(100)
	var eyes := _steps(rules.crouch_eye_height_m, rules.eye_height_m, EYE_STEP_M)
	assert_float(eyes[0]).is_equal(rules.crouch_eye_height_m)
	assert_float(eyes[eyes.size() - 1]).is_equal(rules.eye_height_m)
	assert_int(eyes.size()).is_greater(2)
	# Every floor point of the panel's cylinder where a player fits: standing, each eye of the
	# band; crouched only (under something low), the crouched eye. A holder holds from wherever
	# the panel's use spot is in sight (StationInSight), so each eye that sees it is checked.
	var target := Items.lifted(panel.position)
	var reach := panel.kind.radius_m
	var steps := floori(reach / ORIGIN_GRID_M)
	var holds := 0
	var seen: Array[String] = []
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			var at := panel.position + Vector3(ix, 0, iz) * ORIGIN_GRID_M
			if Vector2(ix, iz).length() * ORIGIN_GRID_M > reach:
				continue
			var below := _world.floor_below(at + Vector3.UP)
			if below == WorldQuery.NO_FLOOR or absf(below.y - panel.position.y) > LEVEL_M:
				continue
			var heights: Array[float] = []
			if _fits(below, rules.capsule_height_m):
				heights = eyes
			elif _fits(below, rules.crouch_height_m):
				heights = [rules.crouch_eye_height_m]
			for height: float in heights:
				var eye := below + Vector3.UP * height
				if not _world.line_of_sight(eye, target):
					continue
				holds += 1
				for point: Vector3 in grid:
					if seen.size() < 5 and _world.line_of_sight(eye, point):
						seen.append("%s sees %s" % [eye, point])
	assert_int(holds).is_greater(eyes.size())
	(
		assert_array(seen)
		. override_failure_message("the panel sees under the car: %s" % [seen])
		. is_empty()
	)
	# The check can fail: from the car's use spot a crouched eye sees the box's points.
	var crouched := car + Vector3.UP * rules.crouch_eye_height_m
	(
		assert_bool(_world.line_of_sight(crouched, car + Vector3(0, 0.5, 0) + _axis(car) * 1.0))
		. is_true()
	)


func test_the_panel_s_cylinder_lies_within_voice_range_and_out_of_the_car_s_reach() -> void:
	_start()
	var task_state := _state()
	var car := _station(task_state.car)
	var panel := _station(task_state.panel)
	var voice := (_game.mode.find_phase(&"round").voice_rule as RoundVoice).living_m
	var apart := _flat(panel.position - car.position).length()
	# RD2: every point of the panel's cylinder within the voice radius less the margin of the car's
	# use spot, and the two cylinders apart (one player cannot hold the lift and fit).
	assert_float(apart + panel.kind.radius_m).is_less_equal(voice - VOICE_MARGIN_M)
	assert_float(apart).is_greater(panel.kind.radius_m + car.kind.radius_m)


func test_a_part_from_each_bin() -> void:
	_start()
	var type := _type()
	var task_state := _state()
	var taker := _peer(OTHER_CREW)
	for i in task_state.bins.size():
		_take_from(taker, task_state.bins[i])
		var held := Items.held_by(_game.state, taker)
		assert_object(held).is_not_null()
		if held != null:
			assert_object(held.kind).is_same(type.parts[i])
	# A take with the hand full goes into the lowest free place and is selected (GDD §6, #1218):
	# the three parts are carried, one in each place, none on the ground.
	var parts := 0
	for kind: ItemKind in type.parts:
		parts += _items_of(kind).size()
	assert_int(parts).is_equal(type.parts.size())
	assert_int(type.parts.size()).is_greater_equal(3)
	var belted := Items.belted_by(_game.state, taker)
	assert_object(belted).is_not_null()
	if belted != null:
		assert_object(belted.kind).is_same(type.parts[0])
	for i in type.parts.size():
		for item: ItemState in _items_of(type.parts[i]):
			assert_int(item.where).override_failure_message(str(i)).is_not_equal(
				ItemState.Where.GROUND
			)
	_assert_clean()


func test_a_package_carrier_takes_parts_onto_the_belt_and_is_refused_two_handed() -> void:
	_start(true)
	var type := _type()
	var task_state := _state()
	var carrier := _peer(OTHER_CREW)
	var bin := _station(task_state.bins[0])
	var package := _package_nearest(bin.position)
	assert_object(package).is_not_null()
	if package == null:
		return
	_walk(carrier, [_beside(package)])
	_send(Intents.PICK_UP, carrier, {"item": package.id})
	_tick()
	assert_int(_game.state.player(carrier).held_item).is_equal(package.id)
	# A take onto the belt: the package stays in the hand (RD17 (a)).
	_take_from(carrier, task_state.bins[0])
	var first := Items.belted_by(_game.state, carrier)
	assert_object(first).is_not_null()
	if first == null:
		return
	assert_object(first.kind).is_same(type.parts[0])
	assert_int(_id(Items.held_by(_game.state, carrier))).is_equal(package.id)
	# A second take fills the belt's second place; a third puts the lower part down at the feet.
	var placed := _game.view_of(carrier).events_named(&"ItemPlaced").size()
	_take_from(carrier, task_state.bins[1])
	assert_int(Items.belted_items(_game.state, carrier).size()).is_equal(2)
	_take_from(carrier, task_state.bins[2])
	var third := Items.belted_by(_game.state, carrier)
	assert_bool(third != null and third.kind == type.parts[2]).is_true()
	assert_int(_id(Items.held_by(_game.state, carrier))).is_equal(package.id)
	assert_int(_game.view_of(carrier).events_named(&"ItemPlaced").size()).is_equal(placed + 1)
	assert_int(first.where).is_equal(ItemState.Where.GROUND)
	# At the panel the package in the hand is refused first (HandNotTwoHanded).
	_refused(carrier, task_state.panel, &"two_handed")
	assert_int(_game.view_of(carrier).events_named(&"LiftChanged").size()).is_equal(0)
	# Under the raised car too (ADR §4): the package in the hand is refused before any part check.
	_hold(_peer(HOLDER))
	_wait_up()
	_refused(carrier, task_state.car, &"two_handed")
	assert_int(_game.view_of(carrier).events_named(&"FitChanged").size()).is_equal(0)
	_assert_quiet()
	_assert_replays()


func test_a_full_repair_from_players_commands() -> void:
	_start()
	var task_state := _state()
	var holder := _peer(HOLDER)
	var fitter := _peer(FITTER)
	var car := _station(task_state.car).position
	_hold(holder)
	for part in CAR_PARTS:
		_take_from(fitter, _bin_of(task_state.next_part()))
		_walk(fitter, [car])
		_wait_up()
		_fit(fitter)
		assert_int(task_state.fitted).is_equal(part + 1)
	assert_bool(task_state.is_done()).is_true()
	for peer: int in _game.state.present_peers():
		var view := _game.view_of(peer)
		assert_int(view.events_named(&"PartFitted").size()).is_equal(CAR_PARTS)
		assert_int(view.events_named(&"TaskProgress").size()).is_greater(0)
		var needed := view.events_named(&"PartNeeded")
		assert_int(needed.size()).is_equal(CAR_PARTS + 1)
		assert_str(String((needed[needed.size() - 1] as PartNeededEvent).kind)).is_empty()
		assert_int(view.events_named(&"Died").size()).is_equal(0)
	# Each fitted part lies locked at the car.
	for id: int in _game.state.items:
		var item: ItemState = _game.state.items[id]
		if item.kind in _type().parts:
			assert_bool(item.position.distance_to(car) < NEAR).is_true()
	_assert_clean()
	_assert_replays()


func test_when_the_holder_lets_go_only_the_fitter_under_the_car_dies() -> void:
	_start()
	var type := _type()
	var task_state := _state()
	var holder := _peer(HOLDER)
	var fitter := _peer(FITTER)
	var beside := _peer(DISSIDENT)
	var past_end := _peer(OTHER_CREW)
	var car := _station(task_state.car).position
	var side := _axis(car).cross(Vector3.UP)
	# A bystander beside the car, one past its far end (the end away from car_end), both outside
	# the box on the garage floor, where a player fits.
	var beside_at := _outside(car, side, type.half_width_m)
	var past_at := _outside(car, -_axis(car), _flat(task_state.car_end - car).length())
	for at: Vector3 in [beside_at, past_at]:
		assert_bool(at != Vector3.INF).is_true()
		if at == Vector3.INF:
			return
		assert_bool(type.in_box(car, task_state.car_end, at)).is_false()
	_take_from(fitter, _bin_of(task_state.next_part()))
	_hold(holder)
	_walk(beside, [beside_at])
	_walk(past_end, [past_at])
	_walk(fitter, [car])
	_wait_up()
	# The fit runs a few ticks with the right part, then the holder lets go.
	_claim(fitter, _game.state.player(fitter).position, true)
	_use(fitter, task_state.car)
	for i in Ticks.RATE:
		_claim(fitter, _game.state.player(fitter).position, true)
		_tick()
	assert_object(Channels.on_station(_game.state, task_state.car)).is_not_null()
	_send(Intents.STOP_RAISE, holder)
	_ticks(2)
	for peer: int in _game.state.present_peers():
		var view := _game.view_of(peer)
		var died := view.events_named(&"Died")
		assert_int(died.size()).is_equal(1)
		if died.size() == 1:
			assert_int((died[0] as DiedEvent).peer).is_equal(fitter)
		# The car went up once and came down once; the fit started and stopped (RD10 (d)).
		var lifts: Array[bool] = []
		for event: MatchEvent in view.events_named(&"LiftChanged"):
			lifts.append((event as LiftChangedEvent).up)
		assert_array(lifts).override_failure_message("peer %d" % peer).is_equal([true, false])
		var fitters: Array[int] = []
		for event: MatchEvent in view.events_named(&"FitChanged"):
			fitters.append((event as FitChangedEvent).fitter)
		assert_array(fitters).override_failure_message("peer %d" % peer).is_equal([fitter, 0])
	assert_int(_game.state.player(fitter).life).is_equal(PlayerState.Life.DEAD)
	for peer: int in [holder, beside, past_end]:
		assert_int(_game.state.player(peer).life).is_equal(PlayerState.Life.ALIVE)
	assert_int(task_state.fitted).is_equal(0)
	_assert_quiet()
	_assert_replays()


func test_the_holder_s_claim_into_the_box_then_a_swap_ends_with_it_dead_once() -> void:
	_start()
	var type := _type()
	var task_state := _state()
	var holder := _peer(HOLDER)
	var car := _station(task_state.car).position
	# A part in the hand, so the Swap is an applied action (hand to belt).
	_take_from(holder, task_state.bins[0])
	var part := Items.held_by(_game.state, holder)
	assert_object(part).is_not_null()
	_hold(holder)
	# A modified client's claim from the panel straight into the box, half-way to its side
	# nearest the panel: the host checks its speed and height, not the walls.
	var side := _axis(car).cross(Vector3.UP)
	var toward := 1.0 if side.dot(_station(task_state.panel).position - car) > 0.0 else -1.0
	var into := _floor_at(car + side * toward * type.half_width_m * 0.5)
	assert_bool(type.in_box(car, task_state.car_end, into)).is_true()
	var player := _game.state.player(holder)
	var per_tick := _game.mode.player_rules.walk_speed_mps / Ticks.RATE
	var covered := ceili(_flat(into - player.position).length() / per_tick) + 1
	_ticks(covered)
	_claim(holder, into, true)
	assert_vector(player.position).is_equal_approx(into, Vector3.ONE * NEAR)
	assert_int(player.life).is_equal(PlayerState.Life.ALIVE)
	# The action in the same tick: the hold stops first, the Swap runs for a living actor, then
	# the drop kills the holder (RE17). Applied, not refused: a refused or skipped Swap would leave
	# the holder dead all the same, by ChannelTicks' re-check of the hold from the box.
	var seen := FixtureModes.rejections(_game, holder).size()
	var claim_tick := _game.ticked_through() + 1
	var from := _game.emitted().size()
	_send(Intents.SWAP, holder)
	_tick()
	var refused := FixtureModes.rejections(_game, holder).slice(seen)
	assert_array(refused).override_failure_message("the Swap: %s" % [refused]).is_empty()
	# What the holder was sent: the drop, then its Swap, then its Died, all on the claim's tick.
	var order: Array[String] = []
	var body := Vector3.INF
	for emitted: EmittedEvent in _game.emitted().slice(from):
		if not emitted.recipients.has(holder):
			continue
		var step := ""
		var lift := emitted.event as LiftChangedEvent
		var swapped := emitted.event as SwappedEvent
		var died := emitted.event as DiedEvent
		if lift != null:
			step = "LiftChanged(%s)" % lift.up
		elif swapped != null and swapped.peer == holder:
			step = "Swapped"
		elif died != null and died.peer == holder:
			step = "Died"
			body = died.position
		if not step.is_empty():
			order.append("%s on %d" % [step, emitted.tick])
	var want: Array[String] = []
	for step: String in ["LiftChanged(false)", "Swapped", "Died"]:
		want.append("%s on %d" % [step, claim_tick])
	assert_array(order).is_equal(want)
	_ticks(Ticks.RATE)
	assert_int(player.life).is_equal(PlayerState.Life.DEAD)
	for peer: int in _game.state.present_peers():
		var died := 0
		var knocked_after := 0
		for event: MatchEvent in _game.view_of(peer).events:
			var kind := event.event_name()
			if kind != &"Died" and kind != &"KnockedDown":
				continue
			if (event.to_dict()["peer"] as int) != holder:
				continue
			if kind == &"Died":
				died += 1
			elif died > 0:
				knocked_after += 1
		assert_int(died).override_failure_message("peer %d's Died" % peer).is_equal(1)
		assert_int(knocked_after).is_equal(0)
		var lifts := _game.view_of(peer).events_named(&"LiftChanged")
		assert_int(lifts.size()).is_equal(2)
	# The part, swapped onto the belt, dropped at the body as for every death (ADR §4).
	if part != null:
		assert_int(part.where).is_equal(ItemState.Where.GROUND)
		assert_vector(part.position).is_equal_approx(body, Vector3.ONE * NEAR)
		var at_death := 0
		for event: MatchEvent in _game.view_of(holder).events_named(&"ItemPlaced"):
			var placed := event as ItemPlacedEvent
			if placed.item == part.id and placed.cause == Items.DEATH:
				at_death += 1
		assert_int(at_death).is_equal(1)
	assert_object(Channels.of_actor(_game.state, holder)).is_null()
	_assert_quiet()
	_assert_replays()


## Starts the shipped base mode on the House in the host's world with BOTS players (bot 1 the
## dissident, the rest crew), sends the scenario setup's ForceRoles and ChangeSettings (the car
## repair alone, or with Delivery when `with_delivery`; CAR_PARTS; the House), plays it into the
## round, and has every player claim where it stands (each claim's baseline). Every call is
## checked.
func _start(with_delivery: bool = false) -> void:
	_problems = PackedStringArray()
	_seqs = {}
	_placed = {}
	_clocks = {}
	_claimed_at = {}
	var mode := load(BASE_MODE) as GameMode
	var banned := PackedStringArray()
	for type: TaskType in mode.task_types:
		if type is CarRepair or (with_delivery and type.id == &"delivery"):
			continue
		banned.append(String(type.id))
	var scenario := BotScenario.new()
	scenario.mode = mode
	scenario.session_seed = SEED
	scenario.bots = BOTS
	scenario.map = HOUSE
	scenario.settings = {&"tasks": 2 if with_delivery else 1, &"car_parts": CAR_PARTS}
	if with_delivery:
		scenario.settings[&"packages"] = PACKAGES
	scenario.id_sets = {&"banned_task_types": banned}
	scenario.forced_roles = {
		DISSIDENT: &"dissident", HOLDER: &"crew", FITTER: &"crew", OTHER_CREW: &"crew"
	}
	_peers = ScenarioPeers.core(BOTS)
	_world = HostWorldQuery.for_mode(mode)
	assert_array(Array(_world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, _world)
	assert_array(Array(levels.errors)).is_empty()
	_layout = levels.layouts[HOUSE]
	_game = Match.new(mode, scenario.session_seed, _world, levels.layouts)
	assert_array(Array(_game.refusals)).is_empty()
	_game.keep_history = true
	_invariants = ScenarioInvariants.new(_game, scenario, _peers)
	assert_bool(_game.start(0)).is_true()
	_check(null)
	for number in range(1, BOTS + 1):
		var peer := _peer(number)
		_send(Intents.PEER_CONNECTED, peer)
		var hello := {
			"name": "",
			"version": JoinRules.PROTOCOL_VERSION,
			"content": _game.content_hash,
			"key": ScenarioBot.key_of(number),
		}
		_send(Intents.HELLO, peer, hello)
	for number: int in scenario.forced_roles:
		_send(Intents.FORCE_ROLE, _peer(number), {"role": String(scenario.forced_roles[number])})
	_send(Intents.CHANGE_SETTINGS, _peer(1), scenario.setup_change())
	assert_str(_game.state.map).is_equal(HOUSE)
	for number in range(1, BOTS + 1):
		_send(Intents.SET_READY, _peer(number), {"ready": true})
	_tick_until(&"loading")
	for number in range(1, BOTS + 1):
		_send(Intents.LOAD_ACK, _peer(number), {"match_id": _game.state.match_id()})
	_tick_until(&"round")
	assert_str(_game.phase_id()).is_equal("round")
	assert_object(_task()).is_not_null()
	assert_int(_game.state.tasks.size()).is_equal(2 if with_delivery else 1)
	for peer: int in _game.state.present_peers():
		_placed[peer] = _game.view_of(peer).events_named(&"Correction").size()
		_clocks[peer] = _game.ticked_through()
		_claimed_at[peer] = _game.ticked_through()
		_claim(peer, _game.state.player(peer).position, true)
	_tick()


func _peer(number: int) -> int:
	return _peers.peer_of(number)


func _task() -> MatchTask:
	return FixtureCarRepairModes.task_of(_game)


func _type() -> CarRepair:
	return _task().type as CarRepair


func _state() -> CarRepair.State:
	return FixtureCarRepairModes.state_of(_game)


func _station(id: int) -> StationState:
	return _game.state.stations.get(id)


## The car's long axis on the floor: from its use spot towards car_end, a unit vector.
func _axis(car: Vector3) -> Vector3:
	return _flat(_state().car_end - car).normalized()


## Applies one command, as HostSession would, and checks its slice of events.
func _send(kind: StringName, peer: int, args: Dictionary = {}) -> void:
	_seqs[peer] = _seqs.get(peer, 0) + 1
	var command := MatchCommand.new(kind, peer, _game.ticked_through() + 1, args, _seqs[peer])
	_game.apply(command)
	_check(command)


## Runs the next host tick and checks its events, snapshots and voice.
func _tick() -> void:
	_game.tick(_game.ticked_through() + 1)
	_check(null)


func _ticks(count: int) -> void:
	for i in count:
		_tick()


func _check(command: MatchCommand) -> void:
	for problem: String in _invariants.check_call(command, _game.take_outbox()):
		_problems.append("tick %d: %s" % [_game.ticked_through(), problem])


func _tick_until(phase: StringName) -> void:
	for i in 60 * Ticks.RATE:
		if _game.phase_id() == phase:
			return
		_tick()


## `peer` claims to stand at `at` (FixtureMoves.claim's fields; on the floor when `on_floor`), its
## client clock on by the host ticks since its last claim (at least 1, at most MAX_TICK_CREDIT):
## an honest client claims one client tick per host tick, so it stores no credit while it stands
## idle (MovementRule.credit_gain), which a timed station channel's re-check refuses (the fit's
## AtStation, RE2).
func _claim(peer: int, at: Vector3, on_floor: bool) -> void:
	var now := _game.ticked_through() + 1
	_clocks[peer] += clampi(now - _claimed_at[peer], 1, MovementRule.MAX_TICK_CREDIT)
	_claimed_at[peer] = now
	var player := _game.state.player(peer)
	var args := {
		"epoch": player.epoch,
		"client_tick": _clocks[peer],
		"position": at,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"sprint": false,
		"moving": not at.is_equal_approx(player.position),
		"jumps": FixtureMoves.jumps_of(_game, peer),
		"on_floor": on_floor,
	}
	_send(Intents.MOVE_CLAIM, peer, args)


## `peer` walks to the floor at each of `waypoints` in turn, a hop each: a hop longer than HOP_M
## goes in pieces of at most HOP_M at its start's height, off the floor (no landing, no rise), its
## last piece landing on the waypoint's floor. For each piece the player waits until its credit
## covers it at walking speed, then claims its end; the host accepts every claim. From the
## basement to a higher floor it climbs the pantry stairs first.
func _walk(peer: int, waypoints: Array[Vector3]) -> void:
	var per_tick := _game.mode.player_rules.walk_speed_mps / Ticks.RATE
	var route: Array[Vector3] = []
	var low := _game.state.player(peer).position.y < BASEMENT_Y
	for waypoint: Vector3 in waypoints:
		if low and waypoint.y >= BASEMENT_Y:
			route.append_array(PANTRY_UP)
		low = waypoint.y < BASEMENT_Y
		route.append(waypoint)
	for waypoint: Vector3 in route:
		var to := _floor_at(waypoint)
		var player := _game.state.player(peer)
		var from := player.position
		var pieces := maxi(1, ceili(_flat(to - from).length() / HOP_M))
		for piece in range(1, pieces + 1):
			var last := piece == pieces
			var at := to
			if not last:
				at = from.lerp(to, float(piece) / pieces)
				at.y = from.y
			var travel := _flat(at - player.position).length()
			var covered := ceili(travel / per_tick) + 1
			_ticks(covered)
			_claim(peer, at, last)
			_tick()
			(
				assert_vector(player.position)
				. override_failure_message("peer %d's claim to %s was not accepted" % [peer, at])
				. is_equal_approx(at, Vector3.ONE * NEAR)
			)


## The floor below `waypoint` (probed from 1 m above it), which lies within LEVEL_M of its height.
func _floor_at(waypoint: Vector3) -> Vector3:
	var found := _world.floor_below(waypoint + Vector3.UP)
	(
		assert_bool(found != WorldQuery.NO_FLOOR and absf(found.y - waypoint.y) < LEVEL_M)
		. override_failure_message("no floor at %s: %s" % [waypoint, found])
		. is_true()
	)
	return found if found != WorldQuery.NO_FLOOR else waypoint


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## `station_id` is a station placed on the one marker of `tag`.
func _assert_on_marker(station_id: int, tag: StringName) -> void:
	var station := _station(station_id)
	var markers := _layout.positions(tag)
	assert_object(station).override_failure_message(String(tag)).is_not_null()
	assert_int(markers.size()).override_failure_message(String(tag)).is_equal(1)
	if station == null or markers.size() != 1:
		return
	assert_float(station.position.distance_to(markers[0])).is_less(NEAR)


## The items of `kind` in the match, lowest id first.
func _items_of(kind: ItemKind) -> Array[ItemState]:
	var found: Array[ItemState] = []
	for id: int in _game.state.items:
		if _game.state.items[id].kind == kind:
			found.append(_game.state.items[id])
	found.sort_custom(func(a: ItemState, b: ItemState) -> bool: return a.id < b.id)
	return found


## The two-handed item on the ground nearest `at` (Delivery's packages), or null.
func _package_nearest(at: Vector3) -> ItemState:
	var best: ItemState = null
	for id: int in _game.state.items:
		var item: ItemState = _game.state.items[id]
		if not item.kind.is_two_handed() or item.where != ItemState.Where.GROUND:
			continue
		if best == null or item.position.distance_to(at) < best.position.distance_to(at):
			best = item
	return best


## The bin that gives the part kind `part_id`.
func _bin_of(part_id: StringName) -> int:
	var type := _type()
	for i in type.parts.size():
		if type.parts[i].id == part_id:
			return _state().bins[i]
	fail("no bin gives %s" % part_id)
	return -1


## A floor spot BESIDE_M from `item` at its level, where a player fits and sees it (ItemInSight's
## line from the eye); fails the test when there is none.
func _beside(item: ItemState) -> Vector3:
	for side: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		var at := item.position + side * BESIDE_M
		var below := _world.floor_below(at + Vector3.UP)
		if below == WorldQuery.NO_FLOOR or absf(below.y - item.position.y) > LEVEL_M:
			continue
		if _fits(below) and _world.line_of_sight(_eye(below), Items.lifted(item.position)):
			return below
	fail("no spot beside item %d at %s" % [item.id, item.position])
	return item.position


## A floor spot on the car's floor `reach` + one of OUTSIDE_M from its use spot along `direction`
## (a unit vector on the floor), at most 1 m along the other axis, where a player fits; INF when
## there is none.
func _outside(car: Vector3, direction: Vector3, reach: float) -> Vector3:
	var across := direction.cross(Vector3.UP)
	for out: float in OUTSIDE_M:
		for shift: float in [0.0, -0.5, 0.5, -1.0, 1.0]:
			var at := car + direction * (reach + out) + across * shift
			var below := _world.floor_below(at + Vector3.UP)
			if below == WorldQuery.NO_FLOOR or absf(below.y - car.y) > NEAR:
				continue
			if _fits(below):
				return below
	return Vector3.INF


## `peer` walks to `bin_id`'s use spot and takes from it (Interact naming the bin), a second after
## its last take at the latest (the bins' shared Cooldown); one tick runs. Accepted: no refusal.
func _take_from(peer: int, bin_id: int) -> void:
	_walk(peer, [_station(bin_id).position])
	_ticks(Ticks.RATE)
	_use(peer, bin_id)


## `peer` walks to the lift panel's use spot and holds the lift there.
func _hold(peer: int) -> void:
	var panel := _state().panel
	_walk(peer, [_station(panel).position])
	_use(peer, panel)
	assert_object(Channels.on_station(_game.state, panel)).is_not_null()


## The ticks run until the car is fully up (RD5 (b)).
func _wait_up() -> void:
	var type := _type()
	for i in type.rise_ticks() + 1:
		if type.is_up(_state(), _game.ticked_through()):
			return
		_tick()
	assert_bool(type.is_up(_state(), _game.ticked_through())).is_true()


## `fitter`, under the raised car with the needed part, fits it: a claim where it stands, an
## Interact at the car, then a claim every tick (the fit's AtStation wants a fresh claim, RE2)
## until the part is fitted, and no longer than ten seconds.
func _fit(fitter: int) -> void:
	var task_state := _state()
	var fitted := task_state.fitted
	_claim(fitter, _game.state.player(fitter).position, true)
	_use(fitter, task_state.car)
	for i in 10 * Ticks.RATE:
		if task_state.fitted > fitted:
			return
		_claim(fitter, _game.state.player(fitter).position, true)
		_tick()
	assert_int(task_state.fitted).override_failure_message("the fit did not complete").is_equal(
		fitted + 1
	)


## The id of `item`, or -2 for none: an assert on it fails instead of crashing on a null.
func _id(item: ItemState) -> int:
	return -2 if item == null else item.id


## `peer` walks to `station_id`'s use spot and names the station in an Interact: refused with
## `reason` alone.
func _refused(peer: int, station_id: int, reason: StringName) -> void:
	var station := _station(station_id)
	_walk(peer, [station.position])
	var seen := FixtureModes.rejections(_game, peer).size()
	_send(Intents.INTERACT, peer, {"station": station.id})
	_tick()
	var refused := FixtureModes.rejections(_game, peer).slice(seen)
	assert_array(refused).override_failure_message("station %d" % station.id).is_equal([reason])


## `peer`, where it stands, names `station_id` in an Interact; one tick runs. Accepted: no refusal.
func _use(peer: int, station_id: int) -> void:
	var seen := FixtureModes.rejections(_game, peer).size()
	_send(Intents.INTERACT, peer, {"station": station_id})
	_tick()
	var refused := FixtureModes.rejections(_game, peer).slice(seen)
	(
		assert_array(refused)
		. override_failure_message("station %d: %s" % [station_id, refused])
		. is_empty()
	)


## The match replayed from its command log gives the same events, in order, to the same peers on
## the same ticks (ARCHITECTURE §3.3), with nothing in the replay's diagnostics: no HostWorldQuery
## answer diverged (Items.give's put-down at the feet, the sight checks, the claims' floors).
func _assert_replays() -> void:
	var replayed := Match.replay(_game.command_log, _game.mode)
	assert_array(Array(replayed.refusals)).is_empty()
	assert_array(Array(replayed.diagnostics)).is_empty()
	var recorded := _game.emitted()
	var again := replayed.emitted()
	assert_int(again.size()).is_equal(recorded.size())
	for i in mini(recorded.size(), again.size()):
		var same := (
			again[i].event.describe() == recorded[i].event.describe()
			and again[i].recipients == recorded[i].recipients
			and again[i].tick == recorded[i].tick
		)
		if not same:
			fail(
				(
					"event %d differs in the replay: %s to %s on %d, recorded %s to %s on %d"
					% [
						i,
						again[i].event.describe(),
						again[i].recipients,
						again[i].tick,
						recorded[i].event.describe(),
						recorded[i].recipients,
						recorded[i].tick
					]
				)
			)
			return


## No invariant broke, no command was refused, no claim corrected, and the match logged no error.
func _assert_clean() -> void:
	for peer: int in _game.state.present_peers():
		assert_array(FixtureModes.rejections(_game, peer)).is_empty()
	_assert_quiet()


## No invariant broke, no claim was corrected, the match logged no error; refusals are not looked at
## (a test that expects some calls this, not `_assert_clean`).
func _assert_quiet() -> void:
	assert_array(Array(_problems)).is_empty()
	for peer: int in _game.state.present_peers():
		var corrections := _game.view_of(peer).events_named(&"Correction").size()
		var what := "peer %d's Corrections: %s" % [peer, _corrections(peer)]
		assert_int(corrections).override_failure_message(what).is_equal(_placed.get(peer, 0))
	for line: String in _game.diagnostics:
		assert_bool(line.begins_with("error:")).override_failure_message(line).is_false()


## Points of the space under the car: across its footprint box (the type's half-length to car_end
## and half_width_m), from just above the floor up to clearance_m, every BOX_GRID_M with both ends.
func _box_grid(car: Vector3, end: Vector3, type: CarRepair) -> Array[Vector3]:
	var along := _flat(end - car)
	var half_length := along.length()
	along = along.normalized()
	var side := along.cross(Vector3.UP)
	var points: Array[Vector3] = []
	for a: float in _steps(-half_length, half_length, BOX_GRID_M):
		for w: float in _steps(-type.half_width_m, type.half_width_m, BOX_GRID_M):
			for h: float in _steps(FLOOR_LIFT_M, type.clearance_m, BOX_GRID_M):
				points.append(car + along * a + side * w + Vector3.UP * h)
	return points


## From `from` to `to` every `step`, with both ends.
static func _steps(from: float, to: float, step: float) -> Array[float]:
	var values: Array[float] = []
	var at := from
	while at < to - 1e-4:
		values.append(at)
		at += step
	values.append(to)
	return values


## A standing player's eye at `feet`, as StationInSight and ItemInSight read it: Items.eye_of
## itself, on a player placed there.
func _eye(feet: Vector3) -> Vector3:
	var ctx := MatchContext.new(_game)
	ctx.state = _game.state
	ctx.mode = _game.mode
	ctx.world = _world
	var player := PlayerState.new(0, "")
	player.position = feet
	return Items.eye_of(ctx, player)


## Whether a player's capsule (the mode's PlayerRules; `height` its height, standing by default)
## with its feet at `feet` meets no shape of the House's world.
func _fits(feet: Vector3, height: float = -1.0) -> bool:
	var rules := _game.mode.player_rules
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = (rules.capsule_height_m if height < 0.0 else height) - FLOOR_GAP_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := feet + Vector3.UP * (FLOOR_GAP_M + capsule.height / 2.0)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	if _level == null:
		_level = LevelWorld.build(HOUSE)
	return _level.space_state().intersect_shape(query).is_empty()


## The first node of `group` at or below `node` (outside the tree: groups set in the scene).
func _first_in_group(node: Node, group: StringName) -> Node:
	if node.is_in_group(group):
		return node
	for child: Node in node.get_children():
		var found := _first_in_group(child, group)
		if found != null:
			return found
	return null


## Every collision body at or below `node`.
func _bodies(node: Node) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []
	if node is CollisionObject3D:
		found.append(node as CollisionObject3D)
	for child: Node in node.get_children():
		found.append_array(_bodies(child))
	return found


## `node`'s transform relative to `root` (an ancestor), outside the tree.
static func _local_transform(root: Node, node: Node3D) -> Transform3D:
	var at := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != root:
		if walk is Node3D:
			at = (walk as Node3D).transform * at
		walk = walk.get_parent()
	return at


## `peer`'s Corrections, described, for a failure message.
func _corrections(peer: int) -> Array[String]:
	var found: Array[String] = []
	for event: MatchEvent in _game.view_of(peer).events_named(&"Correction"):
		found.append(str(event.describe()))
	return found
