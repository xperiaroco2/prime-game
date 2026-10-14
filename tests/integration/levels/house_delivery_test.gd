extends GdUnitTestSuite
## Delivery by meaning on the House in the host's real world (the delivery-by-meaning ADR's §7,
## its issue D5, #832). Bots never play the House (ARCHITECTURE §9.7), so a Match over
## HostWorldQuery.for_mode, with the House's markers where MarkerReader.read_levels puts them, is
## driven by the commands server/ would send, and ScenarioInvariants checks every call and every
## tick (as in house_zone_test.gd). The match is the shipped base mode on the House with one task
## (`tasks` 1) and the Generator banned (as the base mode deals both, delivering the packages would
## not end the round), so its one task type is the Delivery by meaning: four routes, a drop-off
## each.
## - On the floor: two items per drop-off, each put down on the floor inside its cylinder near the
##   rim, on two sides of it, are delivered; the drop-off is done with the second.
## - On the props' tops (D4, #831): an item put on the highest top inside each drop-off's
##   cylinder (its table, its bench) is delivered.
## - In the next room: an item put down past the wall nearest its drop-off at eye height is not
##   delivered; carried back onto its drop-off's floor, it is.
## - Through a wall: horizontal rays from each drop-off's marker, above its furniture, reach no
##   point of its cylinder that lies past a wall (both ways blocked: a cylinder may end inside a
##   wall, as the workbench's does, never past it).
## - Every drop-off and storage marker reads without an error, each on a floor.
## A player reaches its spot as a placement would (its position, before its put-down): a straight
## walk across the House would cross its walls. Every spot is found in the host's world, none
## written down, so a moved marker or prop moves it; a drop-off with no spot found fails.

const MAP := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## This test's own seed.
const SEED := 832_000_000_001
const BOTS := 3
const DISSIDENT := 1
const CARRIER := 2
const OTHER_CREW := 3
## The base mode's put-down distance (its PutDownInFront's distance_m): a player puts an item down
## this far in front of it, so it stands this far from the spot.
const PUT_DOWN_M := 1.0
## How many directions are tried around a drop-off.
const SIDES := 16
## How many horizontal rays the wall check casts per height: one every 0.1 m of a 1 m rim, so a
## wall end or corner cannot slip between two.
const WALL_SIDES := 64
## A floor spot lies this far inside its drop-off's rim.
const RIM_INSET_M := 0.2
## The step between the samples of a top along a direction.
const TOP_STEP_M := 0.1
## A rest this high over its drop-off's floor is on the furniture, not on the floor.
const TOP_MIN_M := 0.3
## Floors this close in height are one floor.
const FLAT_M := 0.05
## The step between floor samples along a clear side, and how far its sight line overshoots it.
const CLEAR_STEP_M := 0.25
const CLEAR_OVERSHOOT_M := 0.5
## An item resting this close to the spot it was put down towards is at that spot.
const REST_M := 0.01
## The next room: the nearest wall at eye height within this reach of the marker ...
const NEXT_ROOM_REACH_M := 8.0
## ... whose far face a ray from this far past its near face finds ...
const WALL_MAX_M := 1.0
## ... and the spot this far past that far face.
const PAST_WALL_M := 0.4
## The wall rays' heights over the drop-off's floor: above every drop-off's furniture top (the
## bench's, the highest, is 0.95 m) and below its cylinder's top (2 m); lower, a chair or a leg
## between the marker and the wall blocks a ray both ways.
const WALL_HEIGHTS: Array[float] = [1.0, 1.6, 1.9]
## How many points along each wall ray, up to the rim, are checked.
const WALL_SAMPLES := 20
## The heights of the probe of a clear side around an item (knee, chest, eye).
const PROBE_HEIGHTS: Array[float] = [0.3, 1.0, 1.6]


## Where a player stands to put an item down towards `target`: `side` from it, PUT_DOWN_M away.
class Spot:
	extends RefCounted
	var target: Vector3
	var side: Vector3
	var stand: Vector3

	func _init(at: Vector3, towards_stand: Vector3, feet: Vector3) -> void:
		target = at
		side = towards_stand
		stand = feet


var _game: Match
var _world: HostWorldQuery
var _invariants: ScenarioInvariants
var _peers: ScenarioPeers
var _problems := PackedStringArray()
var _seqs: Dictionary[int, int] = {}


func test_an_item_put_down_on_the_floor_inside_each_drop_off_is_delivered() -> void:
	# Eight items, two per route (DD2 (a)).
	_start(8)
	var drop_offs := _drop_offs()
	assert_int(drop_offs.size()).is_equal(4)
	for drop_off: StationState in drop_offs:
		var spots := _floor_spots(drop_off)
		var items := _items_of(drop_off)
		assert_int(items.size()).override_failure_message(drop_off.kind.id).is_equal(2)
		(
			assert_int(spots.size())
			. override_failure_message("%s: no two floor spots" % drop_off.kind.id)
			. is_equal(2)
		)
		if items.size() != 2 or spots.size() != 2:
			continue
		for i in 2:
			_carry(items[i], spots[i])
			_assert_delivered(items[i], drop_off)
			assert_bool(drop_off.done).override_failure_message(drop_off.kind.id).is_equal(i == 1)
	_assert_the_crew_won()


func test_an_item_put_on_each_drop_off_s_furniture_is_delivered() -> void:
	_start(4)
	var drop_offs := _drop_offs()
	assert_int(drop_offs.size()).is_equal(4)
	for drop_off: StationState in drop_offs:
		var spot := _top_spot(drop_off)
		(
			assert_object(spot)
			. override_failure_message("%s: no top to put an item on" % drop_off.kind.id)
			. is_not_null()
		)
		var items := _items_of(drop_off)
		if spot == null or items.size() != 1:
			continue
		_carry(items[0], spot)
		assert_float(items[0].position.y - drop_off.position.y).is_greater_equal(TOP_MIN_M)
		_assert_delivered(items[0], drop_off)
	_assert_the_crew_won()


func test_an_item_put_down_in_the_next_room_is_not_delivered() -> void:
	_start(4)
	var drop_offs := _drop_offs()
	assert_int(drop_offs.size()).is_equal(4)
	for drop_off: StationState in drop_offs:
		var away := _next_room_spot(drop_off)
		(
			assert_object(away)
			. override_failure_message("%s: no next room found" % drop_off.kind.id)
			. is_not_null()
		)
		var home := _floor_spots(drop_off)
		var items := _items_of(drop_off)
		if away == null or home.is_empty() or items.size() != 1:
			continue
		var item := items[0]
		_carry(item, away)
		var where := "%s: an item put down at %s" % [drop_off.kind.id, item.position]
		assert_bool(drop_off.contains(item.position)).override_failure_message(where).is_false()
		assert_int(item.where).override_failure_message(where).is_equal(ItemState.Where.GROUND)
		assert_bool(_delivered_to_anyone(item)).override_failure_message(where).is_false()
		assert_bool(drop_off.done).override_failure_message(where).is_false()
		# The same item on its drop-off's floor: the check above could pass.
		_carry(item, home[0])
		_assert_delivered(item, drop_off)
	_assert_the_crew_won()


func test_no_drop_off_reaches_past_a_wall() -> void:
	var mode := load(BASE_MODE) as GameMode
	var world := HostWorldQuery.for_mode(mode)
	var levels := MarkerReader.read_levels(mode, world)
	world.use_level(MAP)
	var layout: LevelLayout = levels.layouts.get(MAP)
	assert_object(layout).is_not_null()
	if layout == null:
		return
	var kinds := _delivery_of(mode).station_kinds()
	assert_int(kinds.size()).is_equal(4)
	for kind: StationKind in kinds:
		for marker: Vector3 in layout.positions(kind.spawn_tag):
			for height: float in WALL_HEIGHTS:
				for i in WALL_SIDES:
					var ray := _dir(i, WALL_SIDES)
					var past := _past_a_wall(world, marker + Vector3.UP * height, ray, kind)
					var where := "%s: %s, %.1f m up, lies past a wall" % [kind.id, past, height]
					(
						assert_bool(past == WorldQuery.NO_FLOOR)
						. override_failure_message(where)
						. is_true()
					)


func test_every_drop_off_and_storage_marker_reads_without_an_error() -> void:
	var mode := load(BASE_MODE) as GameMode
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	world.use_level(MAP)
	var layout: LevelLayout = levels.layouts.get(MAP)
	assert_object(layout).is_not_null()
	if layout == null:
		return
	var delivery := _delivery_of(mode)
	for kind: StationKind in delivery.station_kinds():
		var markers := layout.positions(kind.spawn_tag)
		assert_int(markers.size()).override_failure_message(kind.spawn_tag).is_equal(1)
		for at: Vector3 in markers:
			_assert_on_a_floor(world, at, kind.spawn_tag)
	# The storage: as many markers as the most items the setting deals, each on a floor, so an
	# item spawned there lies on it.
	var most := mode.find_setting(delivery.subtasks_setting).max_value
	for tag: StringName in delivery.item_spawn_tags():
		var markers := layout.positions(tag)
		assert_int(markers.size()).override_failure_message(tag).is_greater_equal(most)
		for at: Vector3 in markers:
			_assert_on_a_floor(world, at, tag)


## Starts the shipped base mode on the House in the host's world with BOTS players (bot 1 the
## dissident, the rest crew), `packages` items, and plays it into the round. Every call is checked.
func _start(packages: int) -> void:
	_problems = PackedStringArray()
	_seqs = {}
	var mode := load(BASE_MODE) as GameMode
	var scenario := BotScenario.new()
	scenario.mode = mode
	scenario.session_seed = SEED
	scenario.bots = BOTS
	scenario.map = MAP
	scenario.settings = {&"packages": packages, &"tasks": 1}
	scenario.id_sets = {&"banned_task_types": PackedStringArray(["generator"])}
	scenario.forced_roles = {DISSIDENT: &"dissident", CARRIER: &"crew", OTHER_CREW: &"crew"}
	_peers = ScenarioPeers.core(BOTS)
	_world = HostWorldQuery.for_mode(mode)
	assert_array(Array(_world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, _world)
	assert_array(Array(levels.errors)).is_empty()
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
	assert_str(_game.state.map).is_equal(MAP)
	for number in range(1, BOTS + 1):
		_send(Intents.SET_READY, _peer(number), {"ready": true})
	_tick_until(&"loading")
	for number in range(1, BOTS + 1):
		_send(Intents.LOAD_ACK, _peer(number), {"match_id": _game.state.match_id()})
	_tick_until(&"round")
	assert_str(_game.phase_id()).is_equal("round")
	assert_object(_delivery()).is_not_null()


func _peer(number: int) -> int:
	return _peers.peer_of(number)


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


func _check(command: MatchCommand) -> void:
	for problem: String in _invariants.check_call(command, _game.take_outbox()):
		_problems.append("tick %d: %s" % [_game.ticked_through(), problem])


func _tick_until(phase: StringName) -> void:
	for i in 60 * Ticks.RATE:
		if _game.phase_id() == phase:
			return
		_tick()


## The carrier stands beside `item` and picks it up, then stands at `spot` and puts it down
## towards its target, where it rests.
func _carry(item: ItemState, spot: Spot) -> void:
	var near := _clear_side(item.position, 0.5)
	FixtureItemModes.stand(_game, _peer(CARRIER), item.position + near * 0.5)
	_send(Intents.PICK_UP, _peer(CARRIER), {"item": item.id})
	assert_int(item.where).override_failure_message("not picked up").is_equal(ItemState.Where.HAND)
	FixtureItemModes.stand(_game, _peer(CARRIER), spot.stand)
	_send(Intents.PUT_DOWN, _peer(CARRIER), {"facing": -spot.side})
	_tick()
	var where := (
		"put down towards %s from %s, rests at %s" % [spot.target, spot.stand, item.position]
	)
	assert_float(item.position.distance_to(spot.target)).override_failure_message(where).is_less(
		REST_M
	)


## Two spots on the floor inside `drop_off`, RIM_INSET_M inside its rim, as far apart around it
## as the floor allows; fewer when there are none.
func _floor_spots(drop_off: StationState) -> Array[Spot]:
	var found: Array[Spot] = []
	var eye := _eye_height()
	for i in SIDES:
		var side := _dir(i)
		var at := drop_off.position + side * (drop_off.kind.radius_m - RIM_INSET_M)
		var target := _world.floor_below(at + Vector3.UP * eye)
		if target == WorldQuery.NO_FLOOR or absf(target.y - drop_off.position.y) > FLAT_M:
			continue
		var spot := _spot(target, side, drop_off.position.y)
		if spot != null:
			found.append(spot)
	if found.size() < 2:
		return found
	var apart := found[1]
	for spot: Spot in found:
		if spot.side.dot(found[0].side) < apart.side.dot(found[0].side):
			apart = spot
	var pair: Array[Spot] = [found[0], apart]
	return pair


## A spot on the highest top inside `drop_off` that a player can put an item on (its table or
## bench), at that top's outermost sample
## along a side a player can stand on; null when there is none.
func _top_spot(drop_off: StationState) -> Spot:
	var eye := _eye_height()
	var samples: Array[Vector3] = []
	var sides: Array[Vector3] = []
	for i in SIDES:
		# From the rim inwards, the marker's own column left out.
		for step in range(roundi(drop_off.kind.radius_m / TOP_STEP_M) - 1, 0, -1):
			var at := drop_off.position + _dir(i) * (step * TOP_STEP_M)
			var top := _world.floor_below(at + Vector3.UP * eye)
			if top != WorldQuery.NO_FLOOR and top.y - drop_off.position.y >= TOP_MIN_M:
				samples.append(top)
				sides.append(_dir(i))
	# Top by top, the highest first; the samples along each side run from the rim inwards, so the
	# first on a top along a side is its outermost.
	var tried := INF
	while true:
		var highest := -INF
		for top: Vector3 in samples:
			if top.y < tried - FLAT_M:
				highest = maxf(highest, top.y)
		if highest == -INF:
			return null
		for k in samples.size():
			if samples[k].y < highest - FLAT_M or samples[k].y > highest:
				continue
			var spot := _spot(samples[k], sides[k], drop_off.position.y)
			if spot != null:
				return spot
		tried = highest
	return null


## A floor spot in the room past the wall nearest `drop_off` at eye height (a wall seen both
## ways between it and the marker); null when there is none within NEXT_ROOM_REACH_M.
func _next_room_spot(drop_off: StationState) -> Spot:
	var eye := drop_off.position + Vector3.UP * _eye_height()
	var best: Spot = null
	var nearest := INF
	for i in SIDES:
		var side := _dir(i)
		var reach := eye + side * NEXT_ROOM_REACH_M
		var hit := _world.sweep(eye, reach, 0.0)
		if hit == reach or eye.distance_to(hit) >= nearest:
			continue
		var face := _world.sweep(hit + side * WALL_MAX_M, hit, 0.0)
		if face == hit:
			continue
		var target := _world.floor_below(face + side * PAST_WALL_M)
		if target == WorldQuery.NO_FLOOR:
			continue
		var seen := target + Vector3.UP * _eye_height()
		if _world.line_of_sight(seen, eye) or _world.line_of_sight(eye, seen):
			continue
		var spot := _spot(target, side, target.y)
		if spot != null:
			best = spot
			nearest = eye.distance_to(hit)
	return best


## Where a player stands to put an item down at `target`: PUT_DOWN_M along `side` from it, on a
## floor at `floor_y`, with its body clear and nothing between its eye and the point over
## `target` where the put-down drops the item; null when it cannot.
func _spot(target: Vector3, side: Vector3, floor_y: float) -> Spot:
	var eye_height := _eye_height()
	var feet := Vector3(target.x, floor_y, target.z) + side * PUT_DOWN_M
	var under := _world.floor_below(feet + Vector3.UP * eye_height)
	if under == WorldQuery.NO_FLOOR or absf(under.y - floor_y) > FLAT_M:
		return null
	var eye := feet + Vector3.UP * eye_height
	var low := Items.lifted(feet)
	# Both ways: a ray misses a shape it starts in.
	if not (_world.line_of_sight(low, eye) and _world.line_of_sight(eye, low)):
		return null
	var over := eye - side * PUT_DOWN_M
	if not (_world.line_of_sight(eye, over) and _world.line_of_sight(over, eye)):
		return null
	var rest := _world.floor_below(over)
	if rest == WorldQuery.NO_FLOOR or rest.distance_to(target) > REST_M:
		return null
	return Spot.new(target, side, feet)


## The first of WALL_SAMPLES points from `from` along `side` up to `kind`'s radius that a wall
## hides from `from` both ways (so not one inside the wall, whose ray back starts in it), or
## NO_FLOOR when none is.
static func _past_a_wall(
	world: HostWorldQuery, from: Vector3, side: Vector3, kind: StationKind
) -> Vector3:
	for s in range(1, WALL_SAMPLES + 1):
		var point := from + side * (kind.radius_m * s / WALL_SAMPLES)
		if not world.line_of_sight(from, point) and not world.line_of_sight(point, from):
			return point
	return WorldQuery.NO_FLOOR


func _assert_on_a_floor(world: HostWorldQuery, at: Vector3, tag: StringName) -> void:
	var under := world.floor_below(Items.lifted(at))
	var where := "%s marker at %s: the floor under it at %s" % [tag, at, under]
	assert_bool(under != WorldQuery.NO_FLOOR).override_failure_message(where).is_true()
	assert_float(absf(under.y - at.y)).override_failure_message(where).is_less_equal(FLAT_M)


func _assert_delivered(item: ItemState, drop_off: StationState) -> void:
	var where := "%s: item %d at %s" % [drop_off.kind.id, item.id, item.position]
	assert_bool(drop_off.contains(item.position)).override_failure_message(where).is_true()
	assert_int(item.where).override_failure_message(where).is_equal(ItemState.Where.LOCKED)
	for peer: int in _game.state.present_peers():
		var told := _deliveries(peer).filter(
			func(event: Dictionary) -> bool: return event["item"] == item.id
		)
		assert_int(told.size()).override_failure_message(where).is_equal(1)
		if told.size() == 1:
			assert_int(told[0]["station"] as int).is_equal(drop_off.id)


func _delivered_to_anyone(item: ItemState) -> bool:
	for peer: int in _game.state.present_peers():
		for event: Dictionary in _deliveries(peer):
			if event["item"] == item.id:
				return true
	return false


func _deliveries(peer: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: MatchEvent in _game.view_of(peer).events_named(&"PackageDelivered"):
		found.append(event.to_dict())
	return found


## The stations the Delivery placed, its drop-offs, in id order.
func _drop_offs() -> Array[StationState]:
	var found: Array[StationState] = []
	var task := _delivery()
	if task == null:
		return found
	var dealt := task.state as DeliveryByMeaning.State
	for id: int in dealt.stations:
		var station: StationState = _game.state.stations.get(id)
		if station != null and not found.has(station):
			found.append(station)
	found.sort_custom(func(a: StationState, b: StationState) -> bool: return a.id < b.id)
	return found


## The items routed to `drop_off`, in subtask order.
func _items_of(drop_off: StationState) -> Array[ItemState]:
	var found: Array[ItemState] = []
	var dealt := _delivery().state as DeliveryByMeaning.State
	for i in dealt.items.size():
		if dealt.stations[i] == drop_off.id:
			found.append(_game.state.items[dealt.items[i]])
	return found


func _delivery() -> MatchTask:
	for id: int in _game.state.tasks:
		if _game.state.tasks[id].type is DeliveryByMeaning:
			return _game.state.tasks[id]
	return null


static func _delivery_of(mode: GameMode) -> DeliveryByMeaning:
	return mode.find_task_type(&"delivery") as DeliveryByMeaning


func _eye_height() -> float:
	return _game.mode.player_rules.eye_height_of(false)


static func _dir(i: int, sides: int = SIDES) -> Vector3:
	var angle := TAU * i / sides
	return Vector3(cos(angle), 0.0, sin(angle))


## A horizontal direction from `at` along which the floor stays at `at`'s height and nothing stands
## in the way at any probe height for `length` metres; fails the test when none is.
func _clear_side(at: Vector3, length: float) -> Vector3:
	for i in SIDES:
		var side := _dir(i)
		if _clear(at, side, length):
			return side
	fail("no clear side %.1f m long around %s" % [length, at])
	return Vector3.RIGHT


func _clear(at: Vector3, side: Vector3, length: float) -> bool:
	for height: float in PROBE_HEIGHTS:
		var up := Vector3.UP * height
		if not _world.line_of_sight(at + up, at + side * (length + CLEAR_OVERSHOOT_M) + up):
			return false
	var samples := ceili(length / CLEAR_STEP_M)
	for s in range(1, samples + 1):
		var point := at + side * (length * s / samples)
		var below := _world.floor_below(point + Vector3.UP)
		if absf(below.y - at.y) > FLAT_M:
			return false
	return true


func _assert_the_crew_won() -> void:
	assert_array(Array(_problems)).is_empty()
	assert_str(_game.phase_id()).is_equal("end")
	assert_str(_game.state.winner).is_equal("crew")
	for peer: int in _game.state.present_peers():
		var ended := _game.view_of(peer).events_named(&"MatchEnded")
		assert_int(ended.size()).is_equal(1)
		if ended.size() == 1:
			assert_str(str(ended[0].to_dict()["reason"])).is_equal("every_task_done")
		assert_array(FixtureModes.rejections(_game, peer)).is_empty()
	for line: String in _game.diagnostics:
		assert_bool(line.begins_with("error:")).override_failure_message(line).is_false()
