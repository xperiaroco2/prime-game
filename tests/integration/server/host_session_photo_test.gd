extends GdUnitTestSuite
## The photo task over the real wire, without bots (#789, photo P10; the photo ADR's §8 "The wire,
## without bots", PE10, PE14, PE18; ARCHITECTURE §4.6, §9.5.22): ClientSessions against a
## HostSession over a LoopbackHub, the codec in between, on FixtureWirePhoto's mode, which deals its
## PhotoTask on its one map STUDIO. The host's client stands on the photo spot and takes a film from
## the box, a second client is refused at the empty camera, loads the dealt film, shoots the first,
## takes the film out, prints it and hangs the photo; a third stands beyond the record's reach. What
## each client decoded equals its Match.view_of, and each decoded ShotTaken's record passes the
## record invariant on the decoded side (LeakCheck, fed the positions the host accepted). And the
## box's flood guard and the film cap against one peer's burst of Interact(film_box), which
## ChaosRun's idle-baseline comparison cannot hold (§4.6.5.3).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## The events §8 names, each of which every client decodes at least once.
const EVENTS: Array[StringName] = [
	&"StationPlaced",
	&"FilmLoaded",
	&"ShotTaken",
	&"ItemPickedUp",
	&"ItemSpawned",
	&"PhotoPrinted",
	&"ItemVanished",
	&"PhotoHung",
	&"TaskState",
	&"TaskProgress",
]
## The burst at the box: one Interact a frame for this long, past the cap at 4 takes a second.
const BURST_SECONDS := 5.0
## More than one tick of the box's cooldown between two uses by one player.
const AFTER_USE_S := 0.4

var _h: Harness
## The leak test's view of the host's match, its record_tick called after every tick.
var _leaks: LeakCheck


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null
	_leaks = null


func test_a_shot_print_and_hang_reach_every_client_as_its_view() -> void:
	_h = _in_round(FixtureWirePhoto.SPOTS, 3)
	var subject := _h.own
	var shooter := _h.clients[1]
	var game := _h.session.game
	var task_state := FixturePhotoModes.state_of(game)
	var dealt := FixturePhotoModes.dealt_film(game)
	assert_vector(dealt.position).is_equal(FixtureWirePhoto.FILM_AT)
	# The subject takes a film from the box: it holds it in the shot's record.
	_use(subject, task_state.film_box)
	var subject_film := Items.held_by(game.state, _h.peer_of(subject))
	assert_object(subject_film).is_not_null()
	# Nothing carried at the empty camera: refused, to the shooter alone.
	_use(shooter, task_state.camera)
	# The dealt film: loaded, a shot of the subject, taken out, printed; the photo hung.
	_pick_up(shooter, dealt.id)
	_use(shooter, task_state.camera)
	_use(shooter, task_state.camera)
	_pick_up(shooter, dealt.id)
	_use(shooter, task_state.printer)
	var printed := FixturePhotoModes.printed(game)
	assert_int(printed.size()).is_equal(1)
	_pick_up(shooter, printed[0].id)
	_use(shooter, task_state.board)
	assert_bool(task_state.is_done()).is_true()
	for client: ClientSession in _h.clients:
		for event_name: StringName in EVENTS:
			(
				assert_array(client.view.events_named(event_name))
				. override_failure_message("no %s decoded" % event_name)
				. is_not_empty()
			)
		# One row, the subject's, with the film in its hand; the shooter and the far one left out.
		var shots := client.view.events_named(&"ShotTaken")
		assert_int(shots.size()).is_equal(1)
		var rows: Array = shots[0].fields["record"]
		assert_int(rows.size()).is_equal(1)
		var row: Dictionary = rows[0]
		assert_int(row["peer"] as int).is_equal(_h.peer_of(subject))
		assert_int(row["held_item"] as int).is_equal(subject_film.id)
		var hung := client.view.events_named(&"PhotoHung")
		assert_bool(hung[0].fields["counted"] as bool).is_true()
		assert_array(_h.mismatches(client)).is_empty()
		assert_array(_leaks.check_bot("client", _h.peer_of(client), client.view, false)).is_empty()
	var refused := shooter.view.events_named(&"Rejected")
	assert_int(refused.size()).is_equal(1)
	assert_str(str(refused[0].fields["reason"])).is_equal("no_film")
	assert_array(subject.view.events_named(&"Rejected")).is_empty()
	assert_array(_h.clients[2].view.events_named(&"Rejected")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_burst_of_takes_gets_one_per_cooldown_and_never_passes_the_film_cap() -> void:
	# The second client stands on the photo spot, in the box's reach (the host's own client has no
	# budget, §4.5.6).
	var spots: Array[Vector3] = [FixtureWirePhoto.SHOOT_SPOT, FixtureWirePhoto.SUBJECT_SPOT]
	_h = _in_round(spots, 2)
	var taker := _h.clients[1]
	var game := _h.session.game
	var box := FixturePhotoModes.state_of(game).film_box
	var events_before := taker.view.events.size()
	var calls_before := _h.calls.size()
	var first_tick := game.ticked_through()
	var most := 0
	for _i in ceili(BURST_SECONDS * Harness.SECOND / Harness.FRAME_USEC):
		taker.send_intent(Intents.INTERACT, {"station": box, "item": -1})
		_h.pump()
		most = maxi(most, _count_of(game, &"film"))
	_h.pump_seconds(0.5)
	var ticks := game.ticked_through() - first_tick
	var arrived := _arrived(calls_before, Intents.INTERACT)
	var spawned := 0
	var too_soon := 0
	for event: WireMessage in taker.view.events.slice(events_before):
		if event.name == &"ItemSpawned":
			spawned += 1
		elif event.name == &"Rejected":
			assert_str(str(event.fields["reason"])).is_equal("too_soon")
			too_soon += 1
	# Every Interact that reached the match is a take or too_soon; at most one take per 5 ticks
	# (PE14).
	assert_int(spawned + too_soon).is_equal(arrived)
	assert_int(spawned).is_less_equal(floori(float(ticks) / FixtureWirePhoto.TAKE_TICKS) + 1)
	assert_int(too_soon).is_greater(0)
	# Past the cap the loose film that lay longest vanished before each take (PE10), and never
	# more than CAP films existed though the burst would make about twice as many.
	assert_int(spawned).is_greater(FixtureWirePhoto.CAP)
	assert_int(most).is_equal(FixtureWirePhoto.CAP)
	assert_array(taker.view.events_named(&"ItemVanished")).is_not_empty()
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
		assert_array(_leaks.check_bot("client", _h.peer_of(client), client.view, false)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


## The harness on FixtureWirePhoto, its players on `spots` in peer-id order, with `players` clients
## (the host's own among them), all in the round, the photo task dealt; _leaks records every tick.
func _in_round(spots: Array[Vector3], players: int) -> Harness:
	var made := Harness.new(FixtureWirePhoto.mode(), true, null, FixtureWirePhoto.layouts(spots))
	assert_array(made.session.errors).is_empty()
	assert_bool(made.started).is_true()
	var leaks := LeakCheck.new(made.session.game)
	var inner := made.session.observer
	made.session.observer = func(
		at_tick: int, command: MatchCommand, slice: Array[EmittedEvent]
	) -> void:
		inner.call(at_tick, command, slice)
		if command == null:
			leaks.record_tick(at_tick)
	_leaks = leaks
	for _i in players - 1:
		made.join()
	assert_bool(made.welcome_all()).is_true()
	made.pump_seconds(0.5)
	made.ready_all()
	assert_bool(made.run_until_phase(&"round", 800)).is_true()
	made.pump_seconds(0.5)
	assert_object(FixturePhotoModes.task_of(made.session.game)).is_not_null()
	for i in players:
		var at := made.session.game.state.player(made.peer_of(made.clients[i])).position
		assert_vector(at).is_equal(spots[i])
	return made


## `client` uses `station` (Interact naming it), then waits out the box's cooldown.
func _use(client: ClientSession, station: int) -> void:
	client.send_intent(Intents.INTERACT, {"station": station, "item": -1})
	_h.pump_seconds(AFTER_USE_S)


## `client` picks up the item `item_id`.
func _pick_up(client: ClientSession, item_id: int) -> void:
	client.send_intent(Intents.PICK_UP, {"item": item_id})
	_h.pump_seconds(AFTER_USE_S)


## How many `intent` commands reached the match since the observer's call `calls_before`.
func _arrived(calls_before: int, intent: StringName) -> int:
	var arrived := 0
	for entry: String in _h.calls.slice(calls_before):
		if entry.split(" ")[1] == String(intent):
			arrived += 1
	return arrived


static func _count_of(game: Match, kind_id: StringName) -> int:
	var count := 0
	for item: ItemState in game.state.items.values():
		if item.kind.id == kind_id:
			count += 1
	return count
