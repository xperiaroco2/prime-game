extends GdUnitTestSuite
## The pinball table's reports over the real wire (#1399; ARCHITECTURE §4.5, §7.1.22): a
## HostSession over a LoopbackHub with a fake clock (host_session_harness.gd) on FixturePinball's
## machine, a scripted table in place of the physics (the physics: pinball_table_test.gd). The
## table steps against the live game and its reports head each step-4 batch: BallLaunched before
## BallMoved, so the tick that launches the ball already shows it. Every client decodes the same
## public ball in its snapshots as view_of its peer holds (LeakCheck too), folds it into
## ClientPinball, and loses it with the ball. A host with no physics (the flat world) has no table.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const OWN := 1


## A table without physics: it launches `launches` balls of the live game, moves the ball along x
## each batch, and loses it when `lose` is set.
class ScriptedTable:
	extends PinballTable

	var launches := 1
	var lose := false
	var at := Vector3(0.25, 0.0, -0.5)
	var steps := 0
	## The left flipper as the last step() was handed it.
	var seen_left := false
	var _ball_game := 0
	var _scripted: Array[MatchCommand] = []

	func step(played: Pinball.Machine, _delta: float) -> void:
		steps += 1
		seen_left = played != null and played.left
		if played == null or played.player < 0:
			_ball_game = 0
			return
		if _ball_game == 0 and launches > 0 and not played.in_play and played.balls_left > 0:
			launches -= 1
			_ball_game = played.serial
			_scripted.append(_scripted_report(Intents.BALL_LAUNCHED, {"game": played.serial}))
		elif lose and _ball_game != 0:
			lose = false
			_scripted.append(_scripted_report(Intents.BALL_LOST, {"game": _ball_game}))
			_ball_game = 0

	func reports() -> Array[MatchCommand]:
		var found := _scripted
		_scripted = []
		if _ball_game != 0:
			at += Vector3(0.125, 0.0, 0.0)
			found.append(_scripted_report(Intents.BALL_MOVED, {"game": _ball_game, "position": at}))
		return found

	static func _scripted_report(kind: StringName, args: Dictionary) -> MatchCommand:
		return MatchCommand.new(kind, 0, 0, args)


## A host with physics (HostSession builds its table) whose levels are flat: the harness's levels
## are paths with no scene (host_session_harness.gd), so a FlatWorldQuery answers for them.
class FlatHostWorld:
	extends HostWorldQuery

	var _flat := FlatWorldQuery.new()

	func use_level(_path: String) -> void:
		bodies.use_world(null)

	func line_of_sight(from: Vector3, to: Vector3) -> bool:
		return _flat.line_of_sight(from, to)

	func floor_below(point: Vector3) -> Vector3:
		return _flat.floor_below(point)

	func stand_floor_below(point: Vector3) -> Vector3:
		return _flat.stand_floor_below(point)

	func rest_position(from: Vector3, towards: Vector3) -> Vector3:
		return _flat.rest_position(from, towards)

	func sweep(from: Vector3, to: Vector3, radius: float) -> Vector3:
		return _flat.sweep(from, to, radius)


var _h: Harness
var _leaks: LeakCheck


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null
	_leaks = null


func test_the_ball_reaches_every_client_from_the_tick_it_is_launched() -> void:
	var table := _started_with_table(2)
	var game := _h.session.game
	_h.pump_seconds(0.5)
	# Nobody sits: the table steps, launches nothing, and no snapshot carries a ball.
	assert_int(table.steps).is_greater(0)
	for client: ClientSession in _h.clients:
		assert_bool(_any_ball(client)).is_false()
		assert_bool(client.model.pinball.ball_shown).is_false()
	_h.own.send_intent(Intents.INTERACT, {"station": FixturePinball.machine_id(game), "item": -1})
	_h.pump_seconds(0.5)
	var machine := Pinball.game(game.state)
	assert_int(machine.player).is_equal(OWN)
	assert_bool(machine.in_play).is_true()
	assert_bool(machine.ball_placed).is_true()
	assert_vector(machine.ball).is_equal(table.at)
	# The launch and the first place came in one batch, the launch first: that tick's snapshot
	# already shows the ball.
	var launched_at := _tick_of(Intents.BALL_LAUNCHED)
	assert_int(launched_at).is_greater(0)
	assert_int(_tick_of(Intents.BALL_MOVED)).is_equal(launched_at)
	for client: ClientSession in _h.clients:
		var at_launch: Dictionary = client.view.snapshots.get(launched_at, {})
		assert_bool(at_launch.has("ball")).is_true()
		assert_bool(client.model.pinball.ball_shown).is_true()
		assert_vector(client.model.pinball.ball).is_equal(machine.ball)
	_check_every_client()
	# The ball is lost: the next snapshots carry none, and every client drops it.
	table.lose = true
	_h.pump_seconds(0.5)
	assert_bool(Pinball.game(game.state).in_play).is_false()
	assert_bool(Pinball.game(game.state).ball_placed).is_false()
	var lost_at := _tick_of(Intents.BALL_LOST)
	assert_int(lost_at).is_greater(launched_at)
	for client: ClientSession in _h.clients:
		assert_bool(client.model.pinball.ball_shown).is_false()
		var last_tick: int = client.view.snapshots.keys().max()
		assert_int(last_tick).is_greater(lost_at)
		assert_bool(client.view.snapshots[last_tick].has("ball")).is_false()
	_check_every_client()


func test_a_flipper_reaches_the_table_in_the_step_its_intent_is_applied() -> void:
	var table := _started_with_table(1)
	var game := _h.session.game
	_h.own.send_intent(Intents.INTERACT, {"station": FixturePinball.machine_id(game), "item": -1})
	_h.pump_seconds(0.5)
	assert_int(Pinball.game(game.state).player).is_equal(OWN)
	assert_bool(table.seen_left).is_false()
	_h.own.send_intent(Intents.FLIPPERS, {"left": true, "right": false})
	var applied := false
	for _i in 30:
		_h.pump()
		if Pinball.game(game.state).left:
			applied = true
			break
	assert_bool(applied).is_true()
	# The table stepped after the tick that applied it: no frame waits for the next step.
	assert_bool(table.seen_left).is_true()


func test_a_host_with_physics_builds_its_table_and_reads_it_at_the_first_game() -> void:
	_h = Harness.new(_mode(), true, null, _layouts(), false, FlatHostWorld.new())
	assert_array(_h.session.errors).is_empty()
	assert_bool(_h.started).is_true()
	var table := _h.session.table
	assert_object(table).is_not_null()
	_h.pump_seconds(0.5)
	# Nobody sits: the table is idle and has not read its scene.
	assert_bool(table.is_active()).is_false()
	assert_array(Array(table.target_ids())).is_empty()
	var game := _h.session.game
	_h.own.send_intent(Intents.INTERACT, {"station": FixturePinball.machine_id(game), "item": -1})
	_h.pump_seconds(0.25)
	assert_int(Pinball.game(game.state).player).is_equal(OWN)
	assert_bool(table.is_active()).is_true()
	assert_array(table.errors).is_empty()
	assert_array(Array(table.target_ids())).is_not_empty()
	# The real table launches on its own after the spec's delay, and core takes the ball.
	_h.pump_seconds(table.spec().launch_delay_s + 0.5)
	assert_int(_tick_of(Intents.BALL_LAUNCHED)).is_greater(0)
	assert_bool(Pinball.game(game.state).in_play).is_true()
	assert_bool(Pinball.game(game.state).ball_placed).is_true()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_host_with_no_physics_has_no_table() -> void:
	_h = Harness.new(_mode(), true, null, _layouts())
	assert_bool(_h.started).is_true()
	assert_object(_h.session.table).is_null()
	_h.pump_seconds(0.25)
	assert_bool(_h.session.is_running()).is_true()


## The harness on FixturePinball's machine with `players` clients (the host's own among them),
## welcomed, the scripted table in place and _leaks recording every tick.
func _started_with_table(players: int) -> ScriptedTable:
	_h = Harness.new(_mode(), true, null, _layouts())
	assert_array(_h.session.errors).is_empty()
	assert_bool(_h.started).is_true()
	var table := ScriptedTable.new()
	_h.session.table = table
	var leaks := LeakCheck.new(_h.session.game)
	var inner := _h.session.observer
	_h.session.observer = func(
		at_tick: int, command: MatchCommand, slice: Array[EmittedEvent]
	) -> void:
		inner.call(at_tick, command, slice)
		if command == null:
			leaks.record_tick(at_tick)
	_leaks = leaks
	for _i in players - 1:
		_h.join()
	assert_bool(_h.welcome_all()).is_true()
	return table


## The harness's mode (res:// levels) with the hall's hands and FixturePinball's machine.
static func _mode() -> GameMode:
	var hands := FixtureLobbyHands.with_hands(Harness.fixture_mode())
	return FixturePinball.with_machine(FixtureLobbyHands.clearing(hands))


## The harness's layouts with the machine's marker at FixturePinball.MACHINE in the lobby.
static func _layouts() -> Dictionary[String, LevelLayout]:
	var made := Harness.layouts()
	made[Harness.LOBBY].add_marker(&"pinball", FixturePinball.MACHINE)
	return made


## The tick of the first Match call that applied a command of `kind`, or -1.
func _tick_of(kind: StringName) -> int:
	for entry: String in _h.calls:
		var parts := entry.split(" ")
		if parts[1] == String(kind):
			return int(parts[0])
	return -1


## Whether any snapshot `client` decoded carries a ball.
static func _any_ball(client: ClientSession) -> bool:
	for at_tick: int in client.view.snapshots:
		if client.view.snapshots[at_tick].has("ball"):
			return true
	return false


## What each client decoded is view_of its peer, ball included, and the leak check passes.
func _check_every_client() -> void:
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
		assert_array(_leaks.check_bot("client", _h.peer_of(client), client.view, false)).is_empty()
	assert_array(Array(_h.session.game.diagnostics)).is_empty()
