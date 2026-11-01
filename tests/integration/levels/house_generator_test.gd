extends GdUnitTestSuite
## The Generator on the House (#802, Generator G7; the Generator ADR's §7 "Integration tests on
## House"), the one map it plays on, in the host's real collision world (HostWorldQuery.for_mode,
## as HostSession builds it). Bots never play the House (ARCHITECTURE §9.7), so no scenario plays
## it: each command goes into Match as server/ would send it, and ScenarioInvariants checks every
## call and every tick, as the runners check theirs (a BotScenario with no `never`: its §5
## invariants, every task event, SwitchChanged and ButtonPressed among them, reaching every present
## player and no one else; no seed, no return key, the voice and the snapshots). The match is the
## shipped base mode on the House, set up as a scenario's setup would be: forced roles, then
## ChangeSettings with the `switches` setting, `tasks` at TASKS and the map; it deals Delivery, the
## Generator, the photo task, Cooking and car repair.
## - The five markers read without errors, and the deal places a station on each of them.
## - With four active switches a player on each use spot uses its station (AtStation and
##   StationInSight pass), a dissident among them, and the button starts the charge.
## - A full charge from scripted commands: every switch on, the button, 60 s; then a press and a
##   switch are refused `unavailable`, and the round goes on (the other tasks are not done).
## - Refusals in the House's own geometry: behind the generator's body inside its cylinder
##   `blocked`; in the darkroom behind the storage's wall, 3 m from switch A, `out_of_reach` at the
##   shipped 2 m radius (no other room lies inside a use cylinder), and `blocked` with the switch's
##   cylinder widened in a copy of the mode to reach through that wall; in the hall in plain sight
##   but outside the cylinder `out_of_reach`.
## - With two active switches the two markers the deal left hold no station (GE14).
## Players reach their spots as a placement would (their position, before any claim): a straight
## walk across the House would cross its walls.

const HOUSE := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## This test's own seed (#802).
const SEED := 802_000_000_001
const BOTS := 3
const DISSIDENT := 1
const CREW := 2
const OTHER_CREW := 3
## The tasks setting every start sends: all five types the House plays (the mode deals 1 by
## default since #1496, the estate's engine alone).
const TASKS := 5
## Switch A's use spot (house-map §6: storage, plan (16, 32) on level -1) and the darkroom's floor
## beyond the storage's south wall, 3 m from it (plan (16, 35)).
const SWITCH_A := Vector3(16.0, -3.2, 32.0)
const DARKROOM := Vector3(16.0, -3.2, 35.0)
## The widened switch cylinder that reaches the darkroom through the wall (a test value, "not a
## decision").
const WIDE_M := 3.5
## How far from the generator's use spot, in plain sight, the out-of-reach player stands.
const OUTSIDE_M := 2.5
## A marker and its station's position agree to float noise.
const NEAR := 0.01
## The search grid behind the generator's body, and its margin inside the cylinder.
const GRID_M := 0.05
const MARGIN_M := 0.05
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05
## The probe's heights above the floor (knee, chest, eye) and its directions.
const PROBE_HEIGHTS: Array[float] = [0.3, 1.0, 1.6]
const PROBE_SIDES := 16

var _game: Match
var _world: HostWorldQuery
## The House alone, for the capsule checks (HostWorldQuery answers rays only).
var _level: LevelWorld
var _layout: LevelLayout
var _invariants: ScenarioInvariants
var _peers: ScenarioPeers
var _problems := PackedStringArray()
var _seqs: Dictionary[int, int] = {}


func test_the_five_markers_read_without_errors_and_each_holds_a_station() -> void:
	_start({&"switches": 4})
	assert_int(_layout.count(&"generator")).is_equal(1)
	assert_int(_layout.count(&"switch")).is_equal(4)
	var placed := _station_positions()
	for tag: StringName in [&"generator", &"switch"]:
		for at: Vector3 in _layout.positions(tag):
			assert_bool(_holds(placed, at)).override_failure_message("%s %s" % [tag, at]).is_true()
	_assert_clean()


func test_with_four_switches_a_player_on_each_use_spot_uses_its_station() -> void:
	_start({&"switches": 4})
	var task_state := FixtureGeneratorModes.state_of(_game)
	assert_int(task_state.switches.size()).is_equal(4)
	for i in task_state.switches.size():
		# Every player in turn, the dissident first: the use reads no role.
		var user := _peer(1 + i % BOTS)
		var station := _game.state.stations[task_state.switches[i]]
		_use(user, station, station.position)
		assert_bool(task_state.on[i]).override_failure_message("switch %d" % i).is_true()
	var button := _game.state.stations[task_state.generator]
	_use(_peer(CREW), button, button.position)
	assert_bool(task_state.running).is_true()
	for peer: int in _game.state.present_peers():
		assert_int(_game.view_of(peer).events_named(&"SwitchChanged").size()).is_equal(4)
		assert_int(_game.view_of(peer).events_named(&"ButtonPressed").size()).is_equal(1)
	_assert_clean()


func test_a_full_charge_from_scripted_commands_then_a_press_is_refused_unavailable() -> void:
	# The mode's default count of active switches.
	_start({})
	var task_state := FixtureGeneratorModes.state_of(_game)
	assert_int(task_state.switches.size()).is_greater(0)
	for i in task_state.switches.size():
		var station := _game.state.stations[task_state.switches[i]]
		_use(_peer(OTHER_CREW), station, station.position)
	var button := _game.state.stations[task_state.generator]
	_use(_peer(DISSIDENT), button, button.position)
	assert_bool(task_state.running).is_true()
	var needed := FixtureGeneratorModes.type_of(_game.mode).needed_ticks()
	var everyone := _game.state.present_peers()
	for i in needed + Ticks.RATE:
		if task_state.done:
			break
		_hold(everyone, 1)
	assert_bool(task_state.done).is_true()
	assert_int(task_state.ticks).is_equal(needed)
	_hold(everyone, Ticks.RATE)
	assert_str(_game.phase_id()).is_equal("round")
	for peer: int in _game.state.present_peers():
		var progress := FixtureGeneratorModes.progress(_game, peer)
		assert_bool(progress.is_empty()).is_false()
		if not progress.is_empty():
			var last: Dictionary = progress.back()
			assert_int(last["ticks"]).is_equal(needed)
			assert_bool(last["counting"]).is_false()
	_assert_clean()
	# A done task refuses every use, the button's and a switch's.
	var first := _game.state.stations[task_state.switches[0]]
	for station: StationState in [button, first]:
		_refused(_peer(CREW), station, station.position, &"unavailable")


func test_behind_the_generator_s_body_inside_its_cylinder_a_press_is_refused_blocked() -> void:
	_start({&"switches": 4})
	var button := _game.state.stations[FixtureGeneratorModes.state_of(_game).generator]
	var behind := _hidden_spot(button)
	assert_bool(button.contains(behind)).is_true()
	_assert_clean()
	_refused(_peer(CREW), button, behind, &"blocked")


func test_from_the_darkroom_behind_the_wall_switch_a_is_out_of_reach_at_its_radius() -> void:
	_start({&"switches": 4})
	var switch_a := _station_at(SWITCH_A)
	_assert_behind_the_wall(switch_a)
	# At the shipped radius the cylinder stops short of the wall's far side.
	assert_bool(switch_a.contains(DARKROOM)).is_false()
	_assert_clean()
	_refused(_peer(CREW), switch_a, DARKROOM, &"out_of_reach")


func test_from_the_darkroom_a_cylinder_through_the_wall_is_refused_blocked() -> void:
	_start({&"switches": 4}, _widened_mode())
	var switch_a := _station_at(SWITCH_A)
	_assert_behind_the_wall(switch_a)
	assert_bool(switch_a.contains(DARKROOM)).is_true()
	_assert_clean()
	_refused(_peer(CREW), switch_a, DARKROOM, &"blocked")


func test_in_plain_sight_outside_the_cylinder_a_press_is_refused_out_of_reach() -> void:
	_start({&"switches": 4})
	var button := _game.state.stations[FixtureGeneratorModes.state_of(_game).generator]
	var outside := button.position + _clear_side(button.position, OUTSIDE_M) * OUTSIDE_M
	assert_bool(button.contains(outside)).is_false()
	assert_bool(_world.line_of_sight(_eye(outside), Items.lifted(button.position))).is_true()
	_assert_clean()
	_refused(_peer(CREW), button, outside, &"out_of_reach")


func test_with_two_switches_the_markers_the_deal_left_hold_no_station() -> void:
	_start({&"switches": 2})
	var task_state := FixtureGeneratorModes.state_of(_game)
	assert_int(task_state.switches.size()).is_equal(2)
	var placed := _station_positions()
	var empty := 0
	for at: Vector3 in _layout.positions(&"switch"):
		if not _holds(placed, at):
			empty += 1
	assert_int(empty).is_equal(2)
	# The generator and two switches: no station stands on a fixed switch's marker.
	var generator_ids: Array[int] = [task_state.generator]
	for id: int in task_state.switches:
		generator_ids.append(id)
	for id: int in _game.state.stations:
		var station := _game.state.stations[id]
		if station.kind.spawn_tag in [&"generator", &"switch"]:
			assert_bool(generator_ids.has(id)).override_failure_message("station %d" % id).is_true()
	for peer: int in _game.state.present_peers():
		var stations := _game.view_of(peer).events_named(&"StationPlaced")
		var ours := 0
		for event: MatchEvent in stations:
			var placed_id: int = event.to_dict()["station"]
			if generator_ids.has(placed_id):
				ours += 1
		assert_int(ours).is_equal(3)
	_assert_clean()


## Starts `mode` (the shipped base mode when null) on the House in the host's world with BOTS
## players (bot 1 the dissident, the rest crew), sends the scenario setup's ForceRoles and
## ChangeSettings (`settings`, `tasks` at TASKS unless `settings` names it, and the House) and plays
## it into the round. Every call is checked.
func _start(settings: Dictionary[StringName, int], mode: GameMode = null) -> void:
	_problems = PackedStringArray()
	_seqs = {}
	if mode == null:
		mode = load(BASE_MODE) as GameMode
	var scenario := BotScenario.new()
	scenario.mode = mode
	scenario.session_seed = SEED
	scenario.bots = BOTS
	scenario.map = HOUSE
	var sent: Dictionary[StringName, int] = settings.duplicate()
	if not sent.has(&"tasks"):
		sent[&"tasks"] = TASKS
	scenario.settings = sent
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
	assert_object(FixtureGeneratorModes.task_of(_game)).is_not_null()


## The shipped base mode with the switch kind's cylinder widened to WIDE_M, in copies: the cached
## shipped resources stay as they are.
func _widened_mode() -> GameMode:
	var base := load(BASE_MODE) as GameMode
	var mode := base.duplicate() as GameMode
	var types: Array[TaskType] = []
	for type: TaskType in base.task_types:
		if type is Generator:
			var copy := type.duplicate() as Generator
			copy.switch = (type as Generator).switch.duplicate() as StationKind
			copy.switch.radius_m = WIDE_M
			types.append(copy)
		else:
			types.append(type)
	mode.task_types = types
	return mode


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


## `peer` claims where the host has it (FixtureMoves.claim's fields: standing on the floor).
func _claim(peer: int) -> void:
	var player := _game.state.player(peer)
	var args := {
		"epoch": player.epoch,
		"client_tick": _game.ticked_through() + 1,
		"position": player.position,
		"velocity": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"sprint": false,
		"moving": false,
		"jumps": FixtureMoves.jumps_of(_game, peer),
		"on_floor": true,
	}
	_send(Intents.MOVE_CLAIM, peer, args)


## `ticks` ticks, in each of which every one of `peers` claims where it stands.
func _hold(peers: Array[int], ticks: int) -> void:
	for i in ticks:
		for peer: int in peers:
			_claim(peer)
		_tick()


## `peer` stands at `at` and names `station` in an Interact; one tick runs. Accepted: no refusal.
func _use(peer: int, station: StationState, at: Vector3) -> void:
	var seen := FixtureModes.rejections(_game, peer).size()
	FixtureItemModes.stand(_game, peer, at)
	_send(Intents.INTERACT, peer, {"station": station.id})
	_tick()
	var refused := FixtureModes.rejections(_game, peer).slice(seen)
	(
		assert_array(refused)
		. override_failure_message("station %d: %s" % [station.id, refused])
		. is_empty()
	)


## `peer` stands at `at` and names `station` in an Interact: refused with `reason`, and no switch
## or button event goes out.
func _refused(peer: int, station: StationState, at: Vector3, reason: StringName) -> void:
	var seen := FixtureModes.rejections(_game, peer).size()
	var used := _station_events()
	FixtureItemModes.stand(_game, peer, at)
	_send(Intents.INTERACT, peer, {"station": station.id})
	_tick()
	var refused := FixtureModes.rejections(_game, peer).slice(seen)
	assert_array(refused).is_equal([reason])
	assert_int(_station_events()).is_equal(used)
	assert_array(Array(_problems)).is_empty()


## How many SwitchChanged and ButtonPressed events every player received in all.
func _station_events() -> int:
	var found := 0
	for peer: int in _game.state.present_peers():
		found += _game.view_of(peer).events_named(&"SwitchChanged").size()
		found += _game.view_of(peer).events_named(&"ButtonPressed").size()
	return found


func _station_positions() -> PackedVector3Array:
	var found := PackedVector3Array()
	for id: int in _game.state.stations:
		found.append(_game.state.stations[id].position)
	return found


func _holds(positions: PackedVector3Array, at: Vector3) -> bool:
	for position: Vector3 in positions:
		if position.distance_to(at) <= NEAR:
			return true
	return false


## The Generator's station whose use spot is `at` (to float noise); fails the test when none is.
func _station_at(at: Vector3) -> StationState:
	for id: int in _game.state.stations:
		var station := _game.state.stations[id]
		if station.kind.spawn_tag == &"switch" and station.position.distance_to(at) <= NEAR:
			return station
	fail("no switch station at %s" % at)
	return null


## The darkroom spot stands on the floor at switch A's level, a player fits there, and the
## storage's wall hides the use spot from its eye.
func _assert_behind_the_wall(switch_a: StationState) -> void:
	assert_object(switch_a).is_not_null()
	if switch_a == null:
		return
	var floor_at := _world.floor_below(DARKROOM + Vector3.UP)
	assert_float(floor_at.y).is_equal_approx(switch_a.position.y, NEAR)
	assert_bool(_fits(DARKROOM)).is_true()
	assert_bool(_world.line_of_sight(_eye(DARKROOM), Items.lifted(switch_a.position))).is_false()


## The point of `station`'s cylinder nearest its use spot, on the floor at its level, where a
## player fits and the House hides the use spot from its eye; fails the test when there is none.
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
	if best == Vector3.INF:
		fail("no hidden spot inside the cylinder at %s" % station.position)
		return station.position
	return best


## A standing player's eye at `feet`, as StationInSight reads it: Items.eye_of itself, on a
## player placed there.
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


## A horizontal direction from `at` along which the floor stays at `at`'s height and nothing stands
## in the way at any probe height for `length` metres; fails the test when none is.
func _clear_side(at: Vector3, length: float) -> Vector3:
	for i in PROBE_SIDES:
		var angle := TAU * i / PROBE_SIDES
		var side := Vector3(cos(angle), 0.0, sin(angle))
		if _clear(at, side, length):
			return side
	fail("no clear side %.1f m long around %s" % [length, at])
	return Vector3.RIGHT


func _clear(at: Vector3, side: Vector3, length: float) -> bool:
	for height: float in PROBE_HEIGHTS:
		var up := Vector3.UP * height
		if not _world.line_of_sight(at + up, at + side * (length + 0.5) + up):
			return false
	var samples := ceili(length / 0.25)
	for s in range(1, samples + 1):
		var point := at + side * (length * s / samples)
		var below := _world.floor_below(point + Vector3.UP)
		if absf(below.y - at.y) > 0.05:
			return false
	return true


## No invariant broke, no command was refused, and the match logged no error.
func _assert_clean() -> void:
	assert_array(Array(_problems)).is_empty()
	for peer: int in _game.state.present_peers():
		assert_array(FixtureModes.rejections(_game, peer)).is_empty()
	for line: String in _game.diagnostics:
		assert_bool(line.begins_with("error:")).override_failure_message(line).is_false()
