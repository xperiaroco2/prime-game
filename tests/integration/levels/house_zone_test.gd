extends GdUnitTestSuite
## The zone task on the House, the one map it plays on (TaskType.maps, the Generator ADR's GD13 (b),
## #804), in the host's real collision world (HostWorldQuery.for_mode, as HostSession builds it).
## Bots never play the House (ARCHITECTURE §9.7), so these are the checks of the three greybox
## scenarios that #804 removed (crew_works_every_zone, dissident_works_a_zone_alone and
## zone_paused_by_a_knockdown), driven without a bot: each command goes into Match as server/ would
## send it, and ScenarioInvariants checks every call and every tick (its §5 invariants: every task
## event, ZoneProgress among them, reaches every present player and no one else; no seed, no
## return key, the voice and the snapshots). The match is FixtureBaseModeWithZones (the base mode
## with the zone task) on the House, set up as a scenario's setup would be: forced roles, then
## ChangeSettings with its settings and the map. The knockdown's match is an own copy of it whose
## Round takes Use (FixtureBaseModeWithMelee.round_takes_use: the M8 slice took the strike out of
## the shipped Round, #1497).
## - Every zone and every package: a crew member delivers the package, another fills the zone, and
##   the crew wins on the second subtask.
## - A dissident alone fills the zone (ZD3: anyone living counts, whatever the role): the crew wins.
## - A knockdown pauses the zone: the dissident knocks the crew member in the zone down from outside
##   it, everyone hears it stop at once, and it counts nothing while the downed member lies in it;
##   another crew member raises it from outside the zone, and the zone counts again and fills.
## Players reach their spots as a placement would (their position, before their first claim): a
## straight walk across the House would cross its walls.

const HOUSE := "res://levels/house/house.tscn"
## The scenarios' seeds were 649000000000 and up; these are this test's own.
const SEED := 804_000_000_001
const BOTS := 3
const DISSIDENT := 1
const CREW := 2
const OTHER_CREW := 3
## The probe's heights above the floor (knee, chest, eye): nothing may stand in the way at any.
const PROBE_HEIGHTS: Array[float] = [0.3, 1.0, 1.6]
## How many directions the probe tries around a spot.
const PROBE_SIDES := 16

var _game: Match
var _world: HostWorldQuery
var _invariants: ScenarioInvariants
var _peers: ScenarioPeers
var _problems := PackedStringArray()
var _seqs: Dictionary[int, int] = {}


func test_the_crew_works_every_zone_and_package_and_wins() -> void:
	# The default draw (both task types, one zone) with one package.
	_start({&"packages": 1}, {})
	var carrier := _peer(CREW)
	var holder := _peer(OTHER_CREW)
	var zone := FixtureZoneModes.zone_of(_game, 0)
	FixtureZoneModes.put(_game, holder, zone.position)
	var delivery := _delivery()
	assert_object(delivery).is_not_null()
	if delivery == null:
		return
	# The House's Delivery by meaning (#828): the item of subtask 0 to its drop-off.
	var dealt := delivery.state as DeliveryByMeaning.State
	var item := _game.state.items[dealt.items[0]]
	var drop_off := _game.state.stations[dealt.stations[0]]
	_carry(carrier, item, drop_off.position)
	assert_int(_game.view_of(carrier).events_named(&"PackageDelivered").size()).is_equal(1)
	assert_str(_game.phase_id()).is_equal("round")
	_hold_until_the_end([holder])
	_assert_the_crew_won()
	_assert_the_zone_filled_for_everyone()


func test_a_dissident_alone_fills_the_zone_and_the_crew_wins() -> void:
	_start({&"tasks": 1}, {&"banned_task_types": PackedStringArray(["delivery"])})
	var dissident := _peer(DISSIDENT)
	assert_str(_game.state.player(dissident).role).is_equal("dissident")
	FixtureZoneModes.put(_game, dissident, FixtureZoneModes.zone_of(_game, 0).position)
	_hold_until_the_end([dissident])
	_assert_the_crew_won()
	_assert_the_zone_filled_for_everyone()


func test_a_knockdown_pauses_the_zone_until_the_raise() -> void:
	_start({&"tasks": 1}, {&"banned_task_types": PackedStringArray(["delivery"])}, true)
	var dissident := _peer(DISSIDENT)
	var downed := _peer(CREW)
	var raiser := _peer(OTHER_CREW)
	var zone := FixtureZoneModes.zone_of(_game, 0)
	# The scenario's spots on one clear side of the zone: the crew member 1.2 m from its centre,
	# inside; the dissident 1 m further out, outside the zone and inside the knife's reach; the
	# raiser 1.8 m beyond the crew member, outside the zone and inside the raise's reach.
	var side := _clear_side(zone.position, 3.2)
	var inside := zone.position + side * 1.2
	FixtureZoneModes.put(_game, downed, inside)
	FixtureZoneModes.put(_game, dissident, zone.position + side * 2.2)
	FixtureZoneModes.put(_game, raiser, inside + side * 1.8)
	for peer: int in [dissident, raiser]:
		assert_bool(zone.contains(_game.state.player(peer).position)).is_false()
	var knife := FixtureItemModes.lay(_game, &"knife", _game.state.player(dissident).position)
	_send(Intents.PICK_UP, dissident, {"item": knife.id})
	_hold([downed], Ticks.RATE)
	assert_bool(FixtureZoneModes.state_of(_game).counting[0]).is_true()
	assert_int(FixtureZoneModes.ticks_of(_game, 0)).is_greater(0)
	# Two hits, a cooldown apart, while the crew member holds the zone.
	_send(Intents.USE, dissident, {"facing": -side})
	_hold([downed], Ticks.RATE)
	_send(Intents.USE, dissident, {"facing": -side})
	_hold([downed], 1)
	assert_int(_game.state.player(downed).life).is_equal(PlayerState.Life.DOWNED)
	# Everyone hears the zone stop with the knockdown's tick.
	for peer: int in _game.state.present_peers():
		var heard := FixtureZoneModes.progress(_game, peer)
		assert_bool(heard.is_empty()).override_failure_message("peer %d" % peer).is_false()
		if heard.is_empty():
			continue
		var last: Dictionary = heard.back()
		assert_bool(last["counting"]).override_failure_message("peer %d" % peer).is_false()
	# The downed member lies in the zone and claims where it lies: nothing counts for 3 s, while the
	# dissident and the raiser stand outside, so only the knockdown stops it.
	assert_bool(zone.contains(_game.state.player(downed).position)).is_true()
	var paused := FixtureZoneModes.ticks_of(_game, 0)
	_hold([downed], 3 * Ticks.RATE)
	assert_int(FixtureZoneModes.ticks_of(_game, 0)).is_equal(paused)
	assert_bool(FixtureZoneModes.state_of(_game).counting[0]).is_false()
	# The knocked-down body moves on the House (PlayerRules.motion_maps) until the host's physics
	# reports it at rest; this core-only match has none, so the reports are sent as it would.
	_settle(downed)
	# The raise, from outside the zone: the zone counts again from the member's first claim after.
	_send(Intents.RAISE, raiser, {"target": downed})
	for i in 10 * Ticks.RATE:
		if _game.state.player(downed).is_alive():
			break
		_hold([downed, raiser], 1)
	assert_bool(_game.state.player(downed).is_alive()).is_true()
	assert_bool(zone.contains(_game.state.player(downed).position)).is_true()
	_hold([downed], Ticks.RATE)
	assert_bool(FixtureZoneModes.state_of(_game).counting[0]).is_true()
	assert_int(FixtureZoneModes.ticks_of(_game, 0)).is_greater(paused)
	_hold_until_the_end([downed])
	_assert_the_crew_won()
	_assert_the_zone_filled_for_everyone()
	for peer: int in _game.state.present_peers():
		assert_int(_game.view_of(peer).events_named(&"Died").size()).is_equal(0)


## Starts the match on the House in the host's world with BOTS players (bot 1 the dissident, the
## rest crew), sends the scenario setup's ForceRoles and ChangeSettings (its `settings` and
## `id_sets`, and the House) and plays it into the round. Every call is checked.
## `melee`: on an own copy of the zone fixture whose Round takes Use, as the shipped one did
## before #1497.
func _start(
	settings: Dictionary[StringName, int],
	id_sets: Dictionary[StringName, PackedStringArray],
	melee := false,
) -> void:
	_problems = PackedStringArray()
	_seqs = {}
	var mode := FixtureBaseModeWithZones.mode()
	if melee:
		mode = FixtureBaseModeWithZones.new()
		FixtureBaseModeWithMelee.round_takes_use(mode)
	var scenario := BotScenario.new()
	scenario.mode = mode
	scenario.session_seed = SEED
	scenario.bots = BOTS
	scenario.map = HOUSE
	scenario.settings = settings
	scenario.id_sets = id_sets
	scenario.forced_roles = {DISSIDENT: &"dissident", CREW: &"crew", OTHER_CREW: &"crew"}
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
	assert_str(_game.state.map).is_equal(HOUSE)
	for number in range(1, BOTS + 1):
		_send(Intents.SET_READY, _peer(number), {"ready": true})
	_tick_until(&"loading")
	for number in range(1, BOTS + 1):
		_send(Intents.LOAD_ACK, _peer(number), {"match_id": _game.state.match_id()})
	_tick_until(&"round")
	assert_str(_game.phase_id()).is_equal("round")
	assert_object(FixtureZoneModes.task_of(_game)).is_not_null()


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


## The host's body of `peer` reports itself at rest where it lies (BodyMoved, slower than the rest
## speed for the rest time): the motion of its knockdown ends.
func _settle(peer: int) -> void:
	var rules := _game.mode.player_rules
	var downed := _game.state.player(peer)
	var args := {"epoch": downed.epoch, "position": downed.position, "velocity": Vector3.ZERO}
	for i in maxi(1, Ticks.from_seconds(rules.rest_s)):
		_game.apply(MatchCommand.new(Intents.BODY_MOVED, peer, _game.ticked_through() + 1, args))
	assert_object(downed.motion).is_null()


## `ticks` ticks, in each of which every one of `peers` claims where it stands.
func _hold(peers: Array[int], ticks: int) -> void:
	for i in ticks:
		for peer: int in peers:
			_claim(peer)
		_tick()


## `peers` hold until the match leaves the round (at most the zone's time and a margin).
func _hold_until_the_end(peers: Array[int]) -> void:
	var limit := FixtureZoneModes.zone_task_of(_game.mode).needed_ticks() + 5 * Ticks.RATE
	for i in limit:
		if _game.phase_id() != &"round":
			return
		_hold(peers, 1)


## `peer` stands beside `item` and picks it up, then stands 1 m (the put-down distance) from
## `target` on a clear side and puts it down towards it: it rests at `target`.
func _carry(peer: int, item: ItemState, target: Vector3) -> void:
	var near := _clear_side(item.position, 0.5)
	FixtureItemModes.stand(_game, peer, item.position + near * 0.5)
	_send(Intents.PICK_UP, peer, {"item": item.id})
	var side := _clear_side(target, 1.0)
	FixtureItemModes.stand(_game, peer, target + side)
	_send(Intents.PUT_DOWN, peer, {"facing": -side})
	_tick()


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


func _delivery() -> MatchTask:
	for id: int in _game.state.tasks:
		if _game.state.tasks[id].type is DeliveryByMeaning:
			return _game.state.tasks[id]
	return null


func _assert_the_crew_won() -> void:
	assert_array(Array(_problems)).is_empty()
	assert_str(_game.phase_id()).is_equal("end")
	assert_str(_game.state.winner).is_equal("crew")
	for peer: int in _game.state.present_peers():
		var ended := _game.view_of(peer).events_named(&"MatchEnded")
		assert_int(ended.size()).is_equal(1)
		assert_str(str(ended[0].to_dict()["side"])).is_equal("crew")
		assert_str(str(ended[0].to_dict()["reason"])).is_equal("every_task_done")
		assert_array(FixtureModes.rejections(_game, peer)).is_empty()
	for line: String in _game.diagnostics:
		assert_bool(line.begins_with("error:")).override_failure_message(line).is_false()


## Every present player's last ZoneProgress says the zone is full: its ticks the needed ones.
func _assert_the_zone_filled_for_everyone() -> void:
	var needed := FixtureZoneModes.zone_task_of(_game.mode).needed_ticks()
	for peer: int in _game.state.present_peers():
		var progress := FixtureZoneModes.progress(_game, peer)
		assert_bool(progress.is_empty()).is_false()
		if progress.is_empty():
			continue
		var last: Dictionary = progress.back()
		assert_int(last["ticks"]).is_equal(needed)
		assert_bool(last["counting"]).is_false()
