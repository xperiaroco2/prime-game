extends GdUnitTestSuite
## The photo task on the House (#788, photo P9; the photo ADR's §8 "Integration tests on House"),
## the one map it plays on, in the host's real collision world (HostWorldQuery.for_mode, as
## HostSession builds it). Bots never play the House (ARCHITECTURE §9.7), so no scenario plays it:
## each command goes into Match as server/ would send it, and ScenarioInvariants checks every call
## and every tick, as the runners check theirs (a BotScenario with no `never`: its §5 invariants,
## every task event, FilmLoaded, ShotTaken, PhotoPrinted and PhotoHung among them, reaching every
## present player and no one else; the record invariant over each ShotTaken; no seed, no return
## key, the voice and the snapshots). The match is the shipped base mode on the House, set up as a
## scenario's setup would be: forced roles, then ChangeSettings with the map, one task and every
## other task type banned (the base mode deals several on the House; #1062's lesson), so the one
## task dealt is the photo task.
## - The five station markers, the tray's and the first film's read without errors; the deal
##   places a station on each, the tray on the photo marker and the film on its marker.
## - A player on each device's use spot passes AtStation and StationInSight: the camera refuses
##   `no_film`, the printer `nothing_to_print`, the board `no_photo`, the box gives a film.
## - The photo spot's whole floor mark lies outside the camera's cylinder; the lens is clear of the
##   camera scene's collision, and the line from the lens to the aim is clear.
## - Shots: a subject on the photo spot counts, one on the mark's near edge too; one behind the
##   gazebo's backdrop (in the frame, out of sight) and one outside the frame (in sight) do not.
## - A scripted chain: a film from the box in storage, the dealt film loaded, a shot with a subject,
##   the film taken out, the print in the study, the hang in the darkroom: a subtask done, and the
##   round goes on.
## The two matches that shoot are replayed from their command logs (Match.replay): the same events
## to the same recipients on the same ticks, nothing in the replay's `diagnostics` (no diverged
## HostWorldQuery answer: the shots' line_of_sight, the stations' sight checks).
## Players move only by MoveClaims the host accepts, so the replay reproduces every position: the
## host checks a claim's speed and height, not the walls (ARCHITECTURE §7.1), so a player waits
## until its tick credit covers a hop at walking speed and claims the floor at its end; a climb to
## the study lands halfway up the external stairs first.

const HOUSE := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## This test's own seed (#788).
const SEED := 788_000_000_001
const BOTS := 3
const DISSIDENT := 1
const CREW := 2
const OTHER_CREW := 3
## The photos setting: more than one, so the chain's one hang leaves the round going (a test
## value, "not a decision").
const PHOTOS := 2
## Up the external stairs from the yard to the balcony, on the way to the study (house-map §5;
## house_stairs_test's walk): the floor in front of the bottom step, the middle of the flight
## and the balcony beyond its top.
const UPSTAIRS: Array[Vector3] = [
	Vector3(39, 0, 14.4), Vector3(39, 1.6, 18), Vector3(39, 3.2, 21.6)
]
## How far a waypoint's floor may lie from its height, and a station from its marker.
const LEVEL_M := 0.5
const NEAR := 0.01
## The longest piece of a walk, its ticks at walking speed well under MovementRule.MAX_TICK_CREDIT.
const HOP_M := 30.0
## The probe for the subject outside the frame: distances from the lens and angles off its axis.
const OUTSIDE_DISTANCES: Array[float] = [4.0, 5.0, 6.0, 7.0]
const OUTSIDE_ANGLES_DEG: Array[float] = [45.0, 55.0, 65.0, 75.0]
## The probe for the subject behind the backdrop: beyond the spot's centre along the axis.
const BEHIND_FROM_M := 1.5
const BEHIND_TO_M := 3.5
const BEHIND_STEP_M := 0.1
## Points sampled on the photo spot's mark (its rim, every few degrees, and its centre).
const RIM_SAMPLES := 72
## The lens's clearance probe: a sphere this big meets no collider of the House.
const LENS_CLEARANCE_M := 0.05
## The capsule's bottom this far above the floor, so the floor under it is no hit.
const FLOOR_GAP_M := 0.05

var _game: Match
var _world: HostWorldQuery
## The House alone, for the shape checks (HostWorldQuery answers rays only).
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
	var task_state := FixturePhotoModes.state_of(_game)
	var type := _type()
	var ids: Array[int] = [
		task_state.camera,
		task_state.photo_spot,
		task_state.film_box,
		task_state.printer,
		task_state.board,
	]
	var kinds: Array[StationKind] = [
		type.camera, type.photo_spot, type.film_box, type.printer, type.board
	]
	for i in ids.size():
		var tag := kinds[i].spawn_tag
		assert_int(_layout.count(tag)).override_failure_message(String(tag)).is_equal(1)
		var station: StationState = _game.state.stations.get(ids[i])
		assert_object(station).override_failure_message(String(tag)).is_not_null()
		if station == null or _layout.count(tag) != 1:
			continue
		assert_float(station.position.distance_to(_layout.positions(tag)[0])).is_less(NEAR)
	assert_int(_layout.count(type.photo.spawn_tag)).is_equal(1)
	assert_int(_layout.count(type.film.spawn_tag)).is_equal(1)
	assert_float(task_state.tray.distance_to(_layout.positions(type.photo.spawn_tag)[0])).is_less(
		NEAR
	)
	var film := FixturePhotoModes.dealt_film(_game)
	assert_object(film).is_not_null()
	if film != null:
		var marker := _layout.positions(type.film.spawn_tag)[0]
		assert_float(film.position.distance_to(marker)).is_less(NEAR)
	assert_int(task_state.photos).is_equal(PHOTOS)
	for peer: int in _game.state.present_peers():
		# The lobby's tap (#1390) and pinball (#1398), cleared at countdown_done, then the deal's 5.
		assert_int(_game.view_of(peer).events_named(&"StationPlaced").size()).is_equal(2 + 5)
	_assert_clean()


func test_a_player_on_each_use_spot_passes_at_station_and_station_in_sight() -> void:
	_start()
	var task_state := FixturePhotoModes.state_of(_game)
	# Empty-handed, each refusal comes from StationUsable, after AtStation and StationInSight
	# passed; the box gives a film.
	_refused(CREW, task_state.camera, &"no_film")
	_refused(OTHER_CREW, task_state.printer, &"nothing_to_print", UPSTAIRS)
	_refused(DISSIDENT, task_state.board, &"no_photo")
	var peer := _peer(CREW)
	_walk(peer, [_station(task_state.film_box).position])
	_use(peer, task_state.film_box)
	var held: ItemState = _game.state.items.get(_game.state.player(peer).held_item)
	assert_object(held).is_not_null()
	if held != null:
		assert_str(String(held.kind.id)).is_equal(String(_type().film.id))
	_assert_quiet()


func test_the_mark_lies_outside_the_cylinder_and_the_lens_sees_the_aim() -> void:
	_start()
	var camera := _station(FixturePhotoModes.state_of(_game).camera)
	var spot := _station(FixturePhotoModes.state_of(_game).photo_spot)
	var radius := spot.kind.radius_m
	assert_bool(camera.contains(spot.position)).is_false()
	for i in RIM_SAMPLES:
		var on_rim := (
			spot.position + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / RIM_SAMPLES) * radius
		)
		(
			assert_bool(camera.contains(on_rim))
			. override_failure_message("the mark's rim at %s is in the camera's cylinder" % on_rim)
			. is_false()
		)
	var lens := _lens(camera)
	assert_int(_hits_at(lens)).override_failure_message("the lens %s" % lens).is_equal(0)
	assert_bool(_world.line_of_sight(lens, _aim())).is_true()
	# The check can fail: twice as far along the line lies past the photo spot, where the backdrop is.
	assert_bool(_world.line_of_sight(lens, _aim() + (_aim() - lens))).is_false()
	_assert_clean()


func test_who_counts_in_a_shot_on_the_house() -> void:
	_start()
	var task_state := FixturePhotoModes.state_of(_game)
	var camera := _station(task_state.camera)
	var spot := _station(task_state.photo_spot)
	var shooter := _peer(CREW)
	var subject := _peer(DISSIDENT)
	_load_the_dealt_film(shooter)
	var towards := _flat(camera.position - spot.position).normalized()
	var near_edge := spot.position + towards * spot.kind.radius_m
	assert_bool(camera.contains(near_edge)).is_false()
	var behind := _behind_the_backdrop()
	var outside := _outside_the_frame()
	var frame := _frame()
	assert_bool(frame.contains(_head(behind))).is_true()
	assert_bool(_world.line_of_sight(_lens(camera), _head(behind))).is_false()
	assert_bool(frame.contains(_head(outside))).is_false()
	assert_bool(_world.line_of_sight(_lens(camera), _head(outside))).is_true()
	var cases := [[spot.position, true], [near_edge, true], [behind, false], [outside, false]]
	for case: Array in cases:
		var at: Vector3 = case[0]
		_walk(subject, [at])
		var shot := _shoot(shooter)
		assert_object(shot).is_not_null()
		if shot == null:
			continue
		var expected: Array[int] = []
		if case[1]:
			expected.append(subject)
		(
			assert_array(Array(shot.subjects))
			. override_failure_message("a subject at %s: %s" % [at, shot.subjects])
			. is_equal(expected)
		)
	_assert_clean()
	_assert_replays()


func test_a_scripted_chain_completes_a_subtask() -> void:
	_start()
	var task_state := FixturePhotoModes.state_of(_game)
	var shooter := _peer(CREW)
	var subject := _peer(DISSIDENT)
	var storer := _peer(OTHER_CREW)
	# A film from the box in storage, the third player kept away from the gazebo.
	_walk(storer, [_station(task_state.film_box).position])
	_use(storer, task_state.film_box)
	var boxed: ItemState = _game.state.items.get(_game.state.player(storer).held_item)
	assert_object(boxed).is_not_null()
	# The dealt film loaded, a subject on the spot, the shot.
	_load_the_dealt_film(shooter)
	_walk(subject, [_station(task_state.photo_spot).position])
	var shot := _shoot(shooter)
	assert_object(shot).is_not_null()
	if shot != null:
		assert_array(Array(shot.subjects)).is_equal([subject])
	# Its record: the subject alone (the shooter stands in the cylinder, the storer beyond the range).
	var taken := _game.view_of(storer).events_named(&"ShotTaken")
	assert_int(taken.size()).is_equal(1)
	if taken.size() == 1:
		var rows: Array = taken[0].to_dict()["record"]
		assert_array(rows.map(func(row: Dictionary) -> int: return row["peer"])).is_equal([subject])
	# The film taken out, printed in the study.
	var exposed := task_state.loaded
	assert_object(exposed).is_not_null()
	if exposed == null:
		return
	_pick_up(shooter, exposed)
	var printer := _station(task_state.printer)
	var route := UPSTAIRS.duplicate()
	route.append(printer.position)
	_walk(shooter, route)
	_use(shooter, task_state.printer)
	(
		assert_bool(_game.state.items.has(exposed.id) and _game.state.items[exposed.id] == exposed)
		. is_false()
	)
	var printed := FixturePhotoModes.printed(_game)
	assert_int(printed.size()).is_equal(1)
	if printed.size() != 1:
		return
	# The photo taken off the tray, hung in the darkroom.
	_pick_up(shooter, printed[0])
	_walk(shooter, [_station(task_state.board).position])
	_use(shooter, task_state.board)
	assert_int(task_state.done_count()).is_equal(1)
	assert_str(_game.phase_id()).is_equal("round")
	for peer: int in _game.state.present_peers():
		var view := _game.view_of(peer)
		for event_name: StringName in [&"FilmLoaded", &"ShotTaken", &"PhotoPrinted", &"PhotoHung"]:
			(
				assert_int(view.events_named(event_name).size())
				. override_failure_message(String(event_name))
				. is_equal(1)
			)
		var hung := view.events_named(&"PhotoHung")
		if hung.size() == 1:
			assert_bool(hung[0].to_dict()["counted"]).is_true()
		var progress := view.events_named(&"TaskProgress")
		assert_bool(progress.is_empty()).is_false()
	_assert_clean()
	_assert_replays()


## Starts the shipped base mode on the House in the host's world with BOTS players (bot 1 the
## dissident, the rest crew), sends the scenario setup's ForceRoles and ChangeSettings (one task,
## PHOTOS, every task type but the photo task banned, the House), plays it into the round, and has
## every player claim where it stands (each claim's baseline). Every call is checked.
func _start() -> void:
	_problems = PackedStringArray()
	_seqs = {}
	_placed = {}
	_clocks = {}
	var mode := load(BASE_MODE) as GameMode
	var banned := PackedStringArray()
	for type: TaskType in mode.task_types:
		if not type is PhotoTask:
			banned.append(String(type.id))
	var scenario := BotScenario.new()
	scenario.mode = mode
	scenario.session_seed = SEED
	scenario.bots = BOTS
	scenario.map = HOUSE
	scenario.settings = {&"tasks": 1, &"photos": PHOTOS}
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
	var task := FixturePhotoModes.task_of(_game)
	assert_object(task).is_not_null()
	assert_int(_game.state.tasks.size()).is_equal(1)
	for peer: int in _game.state.present_peers():
		_placed[peer] = _game.view_of(peer).events_named(&"Correction").size()
		_clocks[peer] = _game.ticked_through()
		_claim(peer, _game.state.player(peer).position, true, 1)
	_tick()


func _peer(number: int) -> int:
	return _peers.peer_of(number)


func _type() -> PhotoTask:
	return FixturePhotoModes.task_of(_game).type as PhotoTask


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
## covers it at walking speed, then claims its end; the host accepts every claim.
func _walk(peer: int, waypoints: Array[Vector3]) -> void:
	var per_tick := _game.mode.player_rules.walk_speed_mps / Ticks.RATE
	for waypoint: Vector3 in waypoints:
		var to := _floor_at(waypoint)
		var player := _game.state.player(peer)
		var from := player.position
		var pieces := ceili(_flat(to - from).length() / HOP_M)
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


## `number`'s player walks by `route` to `station_id`'s use spot and names it in an Interact:
## refused with `reason` alone.
func _refused(number: int, station_id: int, reason: StringName, route: Array[Vector3] = []) -> void:
	var peer := _peer(number)
	var station := _station(station_id)
	var path := route.duplicate()
	path.append(station.position)
	_walk(peer, path)
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


## `peer`, where it stands, picks `item` up; one tick runs. Accepted: it holds the item.
func _pick_up(peer: int, item: ItemState) -> void:
	_send(Intents.PICK_UP, peer, {"item": item.id})
	_tick()
	(
		assert_int(_game.state.player(peer).held_item)
		. override_failure_message("peer %d did not pick up item %d" % [peer, item.id])
		. is_equal(item.id)
	)


## `peer` walks to the camera's use spot, picks up the dealt film beside it and loads it.
func _load_the_dealt_film(peer: int) -> void:
	var task_state := FixturePhotoModes.state_of(_game)
	_walk(peer, [_station(task_state.camera).position])
	var film := FixturePhotoModes.dealt_film(_game)
	assert_object(film).is_not_null()
	if film == null:
		return
	_pick_up(peer, film)
	_use(peer, task_state.camera)
	assert_object(task_state.loaded).is_equal(film)


## `peer`, at the loaded camera, shoots: the shot's entry, or null when no ShotTaken went out.
func _shoot(peer: int) -> PhotoTask.Shot:
	var task_state := FixturePhotoModes.state_of(_game)
	var shots_before := _game.view_of(peer).events_named(&"ShotTaken").size()
	_use(peer, task_state.camera)
	var taken := _game.view_of(peer).events_named(&"ShotTaken")
	if taken.size() != shots_before + 1:
		return null
	var last: MatchEvent = taken[taken.size() - 1]
	var shot_id: int = last.to_dict()["shot"]
	return task_state.shots.get(shot_id)


## The camera's lens: its use spot raised by the mode's eye height (PhotoTask's own).
func _lens(camera: StationState) -> Vector3:
	return camera.position + Vector3.UP * _game.mode.player_rules.eye_height_m


## The frame's aim: the photo spot raised by the eye height.
func _aim() -> Vector3:
	var spot := _station(FixturePhotoModes.state_of(_game).photo_spot)
	return spot.position + Vector3.UP * _game.mode.player_rules.eye_height_m


func _frame() -> PhotoFrame:
	var type := _type()
	var camera := _station(FixturePhotoModes.state_of(_game).camera)
	return PhotoFrame.between(_lens(camera), _aim(), type.fov_deg, type.aspect, type.range_m)


## A standing player's head with its feet at `feet`.
func _head(feet: Vector3) -> Vector3:
	return feet + Vector3.UP * _game.mode.player_rules.eye_height_m


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## The nearest spot beyond the photo spot's centre, along the lens's axis, on the floor, where a
## player fits, its head in the frame and hidden from the lens; fails the test when none is.
func _behind_the_backdrop() -> Vector3:
	var camera := _station(FixturePhotoModes.state_of(_game).camera)
	var spot := _station(FixturePhotoModes.state_of(_game).photo_spot)
	var away := _flat(spot.position - camera.position).normalized()
	var frame := _frame()
	var steps := roundi((BEHIND_TO_M - BEHIND_FROM_M) / BEHIND_STEP_M)
	for i in steps + 1:
		var at := spot.position + away * (BEHIND_FROM_M + i * BEHIND_STEP_M)
		var below := _world.floor_below(at + Vector3.UP)
		if below == WorldQuery.NO_FLOOR or absf(below.y - spot.position.y) > LEVEL_M:
			continue
		if not frame.contains(_head(below)) or not _fits(below):
			continue
		if _world.line_of_sight(_lens(camera), _head(below)):
			continue
		return below
	fail("no spot behind the backdrop beyond %s" % spot.position)
	return spot.position


## A spot in sight of the lens, within its range but outside the frame, on the floor at the
## camera's level, outside the camera's cylinder, where a player fits; fails the test when none is.
func _outside_the_frame() -> Vector3:
	var camera := _station(FixturePhotoModes.state_of(_game).camera)
	var lens := _lens(camera)
	var axis := _flat(_aim() - lens).normalized()
	var frame := _frame()
	for distance: float in OUTSIDE_DISTANCES:
		for angle: float in OUTSIDE_ANGLES_DEG:
			for side: float in [1.0, -1.0]:
				var direction := axis.rotated(Vector3.UP, deg_to_rad(angle) * side)
				var at := camera.position + direction * distance
				var below := _world.floor_below(at + Vector3.UP)
				if below == WorldQuery.NO_FLOOR or absf(below.y - camera.position.y) > LEVEL_M:
					continue
				if camera.contains(below) or frame.contains(_head(below)) or not _fits(below):
					continue
				if not _world.line_of_sight(lens, _head(below)):
					continue
				return below
	fail("no spot in sight outside the frame around %s" % camera.position)
	return camera.position


## How many shapes of the House's world a small sphere at `point` meets.
func _hits_at(point: Vector3) -> int:
	var sphere := SphereShape3D.new()
	sphere.radius = LENS_CLEARANCE_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = LevelWorld.WORLD_LAYER
	query.transform = Transform3D(Basis.IDENTITY, point)
	return _space().intersect_shape(query).size()


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
	return _space().intersect_shape(query).is_empty()


func _space() -> PhysicsDirectSpaceState3D:
	if _level == null:
		_level = LevelWorld.build(HOUSE)
	return _level.space_state()


## The match replayed from its command log gives the same events, in order, to the same peers on
## the same ticks (ARCHITECTURE §3.3), with nothing in the replay's diagnostics: no HostWorldQuery
## answer diverged (the shots' line_of_sight, the stations' sight checks, the claims' floors).
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
