extends GdUnitTestSuite
## Cooking on the House (#777, cooking C8; the cooking ADR's §7 "Integration tests on House"), the
## one map it plays on, in the host's real collision world (HostWorldQuery.for_mode, as
## HostSession builds it). Bots never play the House (ARCHITECTURE §9.7), so no scenario plays it:
## each command goes into Match as server/ would send it, and ScenarioInvariants checks every call
## and every tick, as the runners check theirs (a BotScenario with no `never`: its §5 invariants,
## every task event, OrderPosted, HerbsDealt, GrillLoaded, IngredientPlaced, ItemChanged and
## ItemVanished among them, reaching every present player and no one else; no seed, no return key,
## the voice and the snapshots). The match is the shipped base mode on the House, set up as a
## scenario's setup would be: forced roles, then ChangeSettings with the map, one task, every other
## task type banned (the base mode deals several on the House; #1062's lesson) and the burgers
## setting at its most, 3, so every place is a station.
## - Every station and box marker reads without errors; the deal places the boards, the grill, a
##   bed per herb and the three places on their markers and each box on a marker of its own tag.
## - A player on each used device's spot passes AtStation and StationInSight: the grill and each
##   place refuse `empty_hand` (StationUsable), each bed gives its herb of the round, the order
##   board refuses `empty_hand`, and `wrong_item` for a herb (it takes a burger, #1101); the herb
##   board, a display kind, refuses `nothing_to_do` before any of that (CE6).
## - A burger from players' commands: a bun and a raw patty from the boxes in storage, the patty
##   fried on the grill in the chill zone, the order's herb from its bed in the greenhouse, all
##   three on the order's place in the kitchen: nothing says right or wrong, the order is not
##   done. The plate is taken (a burger in the hand, BurgerPlated) and served at the order
##   board in the kitchen: the burger is done, and the round goes on (the amendment of
##   2026-10-15, #1101: a burger is checked when it is served).
## - A wrong burger (another bun than the order's) served at the board is thrown away, the order
##   not done and its plate empty, again.
## - A box carrier (CD3 (b)): a herb from a bed goes onto the belt, the grill's patty too, the herb
##   put down at the feet first; then a place refuses `two_handed`. The grill's rule has no
##   busy-hands condition: the base mode's own rules keep CD3 (b).
## - A player behind a wall inside a used device's cylinder is refused `blocked`.
## The matches of the burger and the box carrier are replayed from their command logs
## (Match.replay): the same events to the same recipients on the same ticks, nothing in the
## replay's `diagnostics` (no diverged HostWorldQuery answer: Items.give's put-down at the feet, the
## stations' and the boxes' sight checks, the claims' floors).
## Players move only by MoveClaims the host accepts, so the replay reproduces every position: the
## host checks a claim's speed and height, not the walls (ARCHITECTURE §7.1), so a player waits
## until its tick credit covers a hop at walking speed and claims the floor at its end; the climb
## from storage takes the pantry stairs, landing on the flights and the half landing on the way.

const HOUSE := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## This test's own seed (#777).
const SEED := 777_000_000_001
const BOTS := 3
const DISSIDENT := 1
const CREW := 2
const OTHER_CREW := 3
## The burgers setting at its most (the base mode's max_value), so all three places are dealt.
const BURGERS := 3
## Up the pantry stairs from storage to the pantry (house-map §5; house_stairs_test's walk): the
## floor in front of the bottom step, the middle of the lower flight, the half landing, the middle
## of the upper flight and the pantry's floor beyond its top.
const PANTRY_UP: Array[Vector3] = [
	Vector3(25, -3.2, 29.0),
	Vector3(25, -2.31, 26.5),
	Vector3(26, -1.6, 24.75),
	Vector3(27, -0.95, 26.0),
	Vector3(27, 0, 29.0),
]
## Below this height a player stands in the basement and climbs the pantry stairs first.
const BASEMENT_Y := -1.0
## How far a waypoint's floor may lie from its height, and a station or box from its marker.
const LEVEL_M := 0.5
const NEAR := 0.01
## The longest piece of a walk, its ticks at walking speed well under MovementRule.MAX_TICK_CREDIT.
const HOP_M := 30.0
## How far from a box a taker stands (InReach's 2 m with room to spare).
const BESIDE_M := 1.0
## The search grid inside a cylinder for the spot behind a wall, and its margin from the rim.
const GRID_M := 0.05
const MARGIN_M := 0.05
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


func test_the_markers_read_without_errors_and_the_deal_uses_each() -> void:
	_start()
	var type := _type()
	var task_state := _state()
	# One board each and the grill, on the first (and only) marker of their tags.
	var singles: Dictionary[StationKind, int] = {
		type.order_board: task_state.order_board,
		type.herb_board: task_state.herb_board,
		type.grill: task_state.grill,
	}
	for kind: StationKind in singles:
		var tag := kind.spawn_tag
		assert_int(_layout.count(tag)).override_failure_message(String(tag)).is_equal(1)
		_assert_on_marker(singles[kind], tag, 0)
	# A bed per herb on the bed markers, in level order, each with its herb of the round.
	assert_int(_layout.count(type.herb_bed.spawn_tag)).is_equal(type.herbs.size())
	assert_int(task_state.beds.size()).is_equal(type.herbs.size())
	for i in task_state.beds.size():
		_assert_on_marker(task_state.beds[i], type.herb_bed.spawn_tag, i)
	assert_array(task_state.bed_herbs.duplicate()).contains_exactly_in_any_order(type.herbs)
	# The three places, each with its order.
	assert_int(_layout.count(type.place.spawn_tag)).is_equal(BURGERS)
	assert_int(task_state.orders.size()).is_equal(BURGERS)
	for i in task_state.orders.size():
		_assert_on_marker(task_state.orders[i].station, type.place.spawn_tag, i)
	assert_int(task_state.total()).is_equal(BURGERS)
	# A box of each kind on a marker of its own tag.
	for box_kind: ItemKind in type.boxes:
		var boxes := _items_of(box_kind)
		assert_int(boxes.size()).override_failure_message(String(box_kind.id)).is_equal(1)
		if boxes.size() != 1:
			continue
		var on_marker := false
		for marker: Vector3 in _layout.positions(box_kind.spawn_tag):
			on_marker = on_marker or boxes[0].position.distance_to(marker) < NEAR
		assert_bool(on_marker).override_failure_message(String(box_kind.id)).is_true()
	# The lobby's tap (StationTicks, #1390, cleared at countdown_done), then the deal's stations.
	var stations := 1 + 3 + type.herbs.size() + BURGERS
	for peer: int in _game.state.present_peers():
		var view := _game.view_of(peer)
		assert_int(view.events_named(&"StationPlaced").size()).is_equal(stations)
		assert_int(view.events_named(&"OrderPosted").size()).is_equal(BURGERS)
		assert_int(view.events_named(&"HerbsDealt").size()).is_equal(1)
	_assert_clean()


func test_a_player_on_each_use_spot_passes_at_station_and_station_in_sight() -> void:
	_start()
	var task_state := _state()
	var peer := _peer(CREW)
	# Empty-handed, the grill's, each place's and the order board's refusal comes from
	# StationUsable, after AtStation and StationInSight passed.
	_refused(peer, task_state.grill, &"empty_hand")
	for order: Cooking.Order in task_state.orders:
		_refused(peer, order.station, &"empty_hand")
	_refused(peer, task_state.order_board, &"empty_hand")
	# Each bed gives its herb of the round (into the hand; the hand's herb to the belt, then to
	# the feet).
	for i in task_state.beds.size():
		_walk(peer, [_station(task_state.beds[i]).position])
		_use(peer, task_state.beds[i])
		var held := Items.held_by(_game.state, peer)
		assert_object(held).is_not_null()
		if held != null:
			assert_str(String(held.kind.id)).is_equal(String(task_state.bed_herbs[i].id))
	# The herb board is a display kind: nothing to do there, before any condition (CE6). The order
	# board is no display kind since #1101: with a herb in hand it refuses `wrong_item`, after the
	# conditions (a burger is what it takes).
	_refused(peer, task_state.herb_board, &"nothing_to_do")
	_refused(peer, task_state.order_board, &"wrong_item")
	_assert_quiet()


func test_a_burger_from_players_commands_is_done() -> void:
	_start()
	var task_state := _state()
	var order := task_state.orders[0]
	var cook := _peer(CREW)
	# A bun, then a raw patty, from their boxes in storage: the patty in the hand, the bun belted.
	_take(cook, _box_giving(order.bun))
	_take(cook, _box_giving(order.raw_patty))
	var bun := Items.belted_by(_game.state, cook)
	var patty := Items.held_by(_game.state, cook)
	assert_object(bun).is_not_null()
	assert_object(patty).is_not_null()
	if bun == null or patty == null:
		return
	assert_object(bun.kind).is_same(order.bun)
	assert_object(patty.kind).is_same(order.raw_patty)
	# Up the pantry stairs and out to the chill zone: the patty on the grill, fried, taken off.
	_walk(cook, [_station(task_state.grill).position])
	_use(cook, task_state.grill)
	assert_int(task_state.grill_item).is_equal(patty.id)
	_fry()
	_use(cook, task_state.grill)
	assert_int(task_state.grill_item).is_equal(-1)
	assert_int(_id(Items.held_by(_game.state, cook))).is_equal(patty.id)
	assert_object(patty.kind).is_same(_type().fried_of(order.raw_patty))
	# The kitchen: the patty on the order's place, then the bun from the belt.
	_walk(cook, [_station(order.station).position])
	_use(cook, order.station)
	_send(Intents.SWAP, cook)
	_tick()
	assert_int(_id(Items.held_by(_game.state, cook))).is_equal(bun.id)
	_use(cook, order.station)
	# The greenhouse: the order's herb from its bed; back to the place.
	_walk(cook, [_station(_bed_of(order.herb)).position])
	_use(cook, _bed_of(order.herb))
	var herb := Items.held_by(_game.state, cook)
	assert_object(herb).is_not_null()
	_walk(cook, [_station(order.station).position])
	_use(cook, order.station)
	# The plate is full: nothing says right or wrong, nothing is done (#1101).
	assert_bool(order.done).is_false()
	assert_bool(_station(order.station).done).is_false()
	assert_int(task_state.done_count()).is_equal(0)
	for peer: int in _game.state.present_peers():
		var placed := _game.view_of(peer).events_named(&"IngredientPlaced")
		assert_int(placed.size()).is_equal(3)
		for event: MatchEvent in placed:
			assert_bool(event.to_dict().has("right")).is_false()
		assert_bool(_game.view_of(peer).events_named(&"BurgerServed").is_empty()).is_true()
	# Taking the full plate makes the burger (its three items vanish); it is served at the order
	# board, checked there: the order and the place are done.
	_use(cook, order.station)
	var burger := Items.held_by(_game.state, cook)
	assert_object(burger).is_not_null()
	if burger == null:
		return
	assert_object(burger.kind).is_same(_type().burger)
	assert_bool(order.done).is_false()
	_walk(cook, [_station(task_state.order_board).position])
	_use(cook, task_state.order_board)
	assert_bool(order.done).is_true()
	assert_bool(_station(order.station).done).is_true()
	assert_int(task_state.done_count()).is_equal(1)
	assert_bool(_game.state.items.has(burger.id)).is_false()
	assert_str(_game.phase_id()).is_equal("round")
	for peer: int in _game.state.present_peers():
		var view := _game.view_of(peer)
		assert_int(view.events_named(&"GrillLoaded").size()).is_equal(1)
		assert_int(view.events_named(&"ItemChanged").size()).is_equal(1)
		assert_int(view.events_named(&"IngredientPlaced").size()).is_equal(3)
		assert_int(view.events_named(&"BurgerPlated").size()).is_equal(1)
		var served := view.events_named(&"BurgerServed")
		assert_int(served.size()).is_equal(1)
		for event: MatchEvent in served:
			assert_bool(event.to_dict()["right"]).is_true()
		assert_bool(view.events_named(&"TaskProgress").is_empty()).is_false()
	_assert_clean()
	_assert_replays()


func test_a_wrong_burger_served_at_the_board_is_thrown_away() -> void:
	_start()
	var task_state := _state()
	var order := task_state.orders[0]
	var cook := _peer(CREW)
	var wrong_bun: ItemKind = null
	for bun: ItemKind in _type().buns:
		if bun != order.bun:
			wrong_bun = bun
			break
	assert_object(wrong_bun).is_not_null()
	if wrong_bun == null:
		return
	# The same walk as the right burger's, with another bun than the order's.
	_take(cook, _box_giving(wrong_bun))
	_take(cook, _box_giving(order.raw_patty))
	_walk(cook, [_station(task_state.grill).position])
	_use(cook, task_state.grill)
	_fry()
	_use(cook, task_state.grill)
	_walk(cook, [_station(order.station).position])
	_use(cook, order.station)
	_send(Intents.SWAP, cook)
	_tick()
	_use(cook, order.station)
	_walk(cook, [_station(_bed_of(order.herb)).position])
	_use(cook, _bed_of(order.herb))
	_walk(cook, [_station(order.station).position])
	_use(cook, order.station)
	# Plated and taken, nothing yet said or done; served: thrown away, the plate empty again.
	_use(cook, order.station)
	var burger := Items.held_by(_game.state, cook)
	assert_object(burger).is_not_null()
	if burger == null:
		return
	assert_object(burger.kind).is_same(_type().burger)
	assert_int(task_state.done_count()).is_equal(0)
	_walk(cook, [_station(task_state.order_board).position])
	_use(cook, task_state.order_board)
	assert_bool(order.done).is_false()
	assert_bool(_station(order.station).done).is_false()
	assert_int(task_state.done_count()).is_equal(0)
	assert_bool(_game.state.items.has(burger.id)).is_false()
	assert_int(order.bun_item).is_equal(-1)
	assert_int(order.patty_item).is_equal(-1)
	assert_int(order.herb_item).is_equal(-1)
	assert_str(_game.phase_id()).is_equal("round")
	for peer: int in _game.state.present_peers():
		var served := _game.view_of(peer).events_named(&"BurgerServed")
		assert_int(served.size()).is_equal(1)
		for event: MatchEvent in served:
			assert_bool(event.to_dict()["right"]).is_false()
	_assert_clean()
	_assert_replays()


func test_a_box_carrier_takes_onto_the_belt_and_is_refused_two_handed_at_a_place() -> void:
	_start()
	var task_state := _state()
	var type := _type()
	var carrier := _peer(CREW)
	var griller := _peer(DISSIDENT)
	# The carrier picks a box up in storage and carries it to the first bed: the herb goes onto
	# the belt, the box stays in the hand.
	var box := _items_of(type.boxes[0])[0]
	_walk(carrier, [_beside(box)])
	_send(Intents.PICK_UP, carrier, {"item": box.id})
	_tick()
	assert_int(_game.state.player(carrier).held_item).is_equal(box.id)
	_walk(carrier, [_station(task_state.beds[0]).position])
	_use(carrier, task_state.beds[0])
	var herb := Items.belted_by(_game.state, carrier)
	assert_object(herb).is_not_null()
	if herb == null:
		return
	assert_object(herb.kind).is_same(task_state.bed_herbs[0])
	assert_int(_id(Items.held_by(_game.state, carrier))).is_equal(box.id)
	# A second bed fills the belt's second place (GDD §6, #1218): the belt is full.
	_walk(carrier, [_station(task_state.beds[1]).position])
	_use(carrier, task_state.beds[1])
	assert_int(Items.belted_items(_game.state, carrier).size()).is_equal(2)
	assert_object(Items.belted_by(_game.state, carrier)).is_same(herb)
	# Another player (a dissident: nothing reads a role) loads the grill; the carrier waits there.
	_walk(carrier, [_station(task_state.grill).position])
	_take(griller, _box_giving(type.raw_patties[0]))
	var patty := Items.held_by(_game.state, griller)
	assert_object(patty).is_not_null()
	if patty == null:
		return
	_walk(griller, [_station(task_state.grill).position])
	_use(griller, task_state.grill)
	_fry()
	# The carrier takes the patty off: onto the belt, the lower belt place's herb put down first.
	var placed := _game.view_of(carrier).events_named(&"ItemPlaced").size()
	_use(carrier, task_state.grill)
	assert_int(_id(Items.belted_by(_game.state, carrier))).is_equal(patty.id)
	assert_int(_id(Items.held_by(_game.state, carrier))).is_equal(box.id)
	assert_int(_game.view_of(carrier).events_named(&"ItemPlaced").size()).is_equal(placed + 1)
	assert_int(herb.where).is_equal(ItemState.Where.GROUND)
	assert_float(_flat(herb.position - _game.state.player(carrier).position).length()).is_less(
		LEVEL_M
	)
	# At a place the box in the hand is refused first (the place's HandNotTwoHanded).
	_refused(carrier, task_state.orders[0].station, &"two_handed")
	assert_int(task_state.done_count()).is_equal(0)
	_assert_quiet()
	_assert_replays()


func test_behind_a_wall_inside_a_cylinder_a_use_is_refused_blocked() -> void:
	_start()
	var task_state := _state()
	var peer := _peer(CREW)
	# Behind the grill's body and behind each place's counter, inside the cylinder: the House hides
	# the use spot from the eye (each precondition asserted in _hidden_spot).
	var ids: Array[int] = [task_state.grill]
	for order: Cooking.Order in task_state.orders:
		ids.append(order.station)
	for id: int in ids:
		var station := _station(id)
		var behind := _hidden_spot(station)
		(
			assert_bool(behind != Vector3.INF)
			. override_failure_message("no hidden spot inside station %d's cylinder" % id)
			. is_true()
		)
		if behind == Vector3.INF:
			continue
		assert_bool(station.contains(behind)).is_true()
		_refused(peer, id, &"blocked", behind)
	_assert_quiet()


## Starts the shipped base mode on the House in the host's world with BOTS players (bot 1 the
## dissident, the rest crew), sends the scenario setup's ForceRoles and ChangeSettings (one task,
## BURGERS, every task type but Cooking banned, the House), plays it into the round, and has every
## player claim where it stands (each claim's baseline). Every call is checked.
func _start() -> void:
	_problems = PackedStringArray()
	_seqs = {}
	_placed = {}
	_clocks = {}
	var mode := load(BASE_MODE) as GameMode
	var banned := PackedStringArray()
	for type: TaskType in mode.task_types:
		if not type is Cooking:
			banned.append(String(type.id))
	var scenario := BotScenario.new()
	scenario.mode = mode
	scenario.session_seed = SEED
	scenario.bots = BOTS
	scenario.map = HOUSE
	scenario.settings = {&"tasks": 1, &"burgers": BURGERS}
	scenario.id_sets = {&"banned_task_types": banned}
	scenario.forced_roles = {DISSIDENT: &"dissident", CREW: &"crew", OTHER_CREW: &"crew"}
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
	assert_object(FixtureCookingModes.task_of(_game)).is_not_null()
	assert_int(_game.state.tasks.size()).is_equal(1)
	for peer: int in _game.state.present_peers():
		_placed[peer] = _game.view_of(peer).events_named(&"Correction").size()
		_clocks[peer] = _game.ticked_through()
		_claim(peer, _game.state.player(peer).position, true, 1)
	_tick()


func _peer(number: int) -> int:
	return _peers.peer_of(number)


func _type() -> Cooking:
	return FixtureCookingModes.task_of(_game).type as Cooking


func _state() -> Cooking.State:
	return FixtureCookingModes.state_of(_game)


func _station(id: int) -> StationState:
	return _game.state.stations.get(id)


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
## client clock `covered` ticks on from its last claim: an honest client's own clock, which the
## host's credit (MovementRule) lets lag behind the host's ticks while the player stands idle.
func _claim(peer: int, at: Vector3, on_floor: bool, covered: int) -> void:
	_clocks[peer] += covered
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
			_claim(peer, at, last, covered)
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


## `station_id` is a station placed on marker `index` of `tag` (level order).
func _assert_on_marker(station_id: int, tag: StringName, index: int) -> void:
	var station := _station(station_id)
	var markers := _layout.positions(tag)
	assert_object(station).override_failure_message(String(tag)).is_not_null()
	assert_bool(index < markers.size()).override_failure_message(String(tag)).is_true()
	if station == null or index >= markers.size():
		return
	assert_float(station.position.distance_to(markers[index])).is_less(NEAR)


## The items of `kind` in the match, lowest id first.
func _items_of(kind: ItemKind) -> Array[ItemState]:
	var found: Array[ItemState] = []
	for id: int in _game.state.items:
		if _game.state.items[id].kind == kind:
			found.append(_game.state.items[id])
	found.sort_custom(func(a: ItemState, b: ItemState) -> bool: return a.id < b.id)
	return found


## The dealt box whose take gives `kind` (its target_actions' GiveItem).
func _box_giving(kind: ItemKind) -> ItemState:
	for box_kind: ItemKind in _type().boxes:
		for rule: Rule in box_kind.target_actions:
			for effect: RuleEffect in rule.effects:
				if effect is GiveItem and (effect as GiveItem).kind == kind:
					var boxes := _items_of(box_kind)
					assert_int(boxes.size()).is_equal(1)
					return boxes[0] if boxes.size() == 1 else null
	fail("no box gives %s" % kind.id)
	return null


## The bed whose herb of the round is `herb`.
func _bed_of(herb: ItemKind) -> int:
	var task_state := _state()
	return task_state.beds[task_state.bed_herbs.find(herb)]


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


## `peer` walks beside `box` and takes from it (Interact naming the box); one tick runs. Accepted:
## no refusal (the tests then read what is in hand).
func _take(peer: int, box: ItemState) -> void:
	assert_object(box).is_not_null()
	if box == null:
		return
	_walk(peer, [_beside(box)])
	var seen := FixtureModes.rejections(_game, peer).size()
	_send(Intents.INTERACT, peer, {"station": -1, "item": box.id})
	_tick()
	var refused := FixtureModes.rejections(_game, peer).slice(seen)
	assert_array(refused).override_failure_message("box %d: %s" % [box.id, refused]).is_empty()


## The id of `item`, or -2 for none: an assert on it fails instead of crashing on a null.
func _id(item: ItemState) -> int:
	return -2 if item == null else item.id


## The ticks run until the grill's patty has turned fried, and no further (before its burnt tick).
func _fry() -> void:
	var task_state := _state()
	var patty: ItemState = _game.state.items.get(task_state.grill_item)
	assert_object(patty).is_not_null()
	if patty == null:
		return
	for i in _type().burnt_ticks():
		if _type().fried_patties.has(patty.kind):
			break
		_tick()
	assert_bool(_type().fried_patties.has(patty.kind)).is_true()
	assert_int(_game.ticked_through()).is_less(task_state.burnt_tick)


## `peer` walks to `at` (`station_id`'s use spot by default) and names the station in an Interact:
## refused with `reason` alone.
func _refused(peer: int, station_id: int, reason: StringName, at: Vector3 = Vector3.INF) -> void:
	var station := _station(station_id)
	_walk(peer, [station.position if at == Vector3.INF else at])
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
		assert_int(corrections).is_equal(_placed.get(peer, 0))
	for line: String in _game.diagnostics:
		assert_bool(line.begins_with("error:")).override_failure_message(line).is_false()


## The point of `station`'s cylinder nearest its use spot, on the floor at its level, where a
## player fits and the House hides the use spot from its eye; INF when there is none.
func _hidden_spot(station: StationState) -> Vector3:
	var reach := station.kind.radius_m - MARGIN_M
	var steps := ceili(reach / GRID_M)
	var best := Vector3.INF
	var best_distance := INF
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			var at := station.position + Vector3(ix * GRID_M, 0.0, iz * GRID_M)
			var distance := Vector2(ix, iz).length() * GRID_M
			if distance > reach or distance >= best_distance:
				continue
			var below := _world.floor_below(at + Vector3.UP)
			if below == WorldQuery.NO_FLOOR or absf(below.y - station.position.y) > NEAR:
				continue
			if _world.line_of_sight(_eye(below), Items.lifted(station.position)):
				continue
			if not _fits(below):
				continue
			best = below
			best_distance = distance
	return best


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


## Whether a standing player's capsule (the mode's PlayerRules) with its feet at `feet` meets no
## shape of the House's world.
func _fits(feet: Vector3) -> bool:
	var rules := _game.mode.player_rules
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m - FLOOR_GAP_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LevelWorld.WORLD_LAYER
	var centre := feet + Vector3.UP * (FLOOR_GAP_M + capsule.height / 2.0)
	query.transform = Transform3D(Basis.IDENTITY, centre)
	if _level == null:
		_level = LevelWorld.build(HOUSE)
	return _level.space_state().intersect_shape(query).is_empty()
