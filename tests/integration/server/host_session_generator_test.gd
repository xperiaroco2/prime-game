extends GdUnitTestSuite
## The Generator over the wire (#797; ARCHITECTURE §4.6, §9.5): ClientSessions against a
## HostSession over a LoopbackHub, the harness's fixture mode with the Generator dealt on
## `loading, all_loaded -> pregame`, Interact from the living and TaskTicks in Round. Two clients
## turn the switches on and press the button, one names a station nobody placed; the charge
## completes, and what each client decoded is its view_of: SwitchChanged, ButtonPressed and the
## progress events reach everyone, the refusal only its sender.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## Every station reaches every round_player marker ((10 + i, 0, 5)) from here.
const REACH_M := 5.0
const GENERATOR_AT := Vector3(12, 0, 6)
const SWITCH_SPOTS: Array[Vector3] = [
	Vector3(10, 0, 6), Vector3(11, 0, 6), Vector3(13, 0, 6), Vector3(14, 0, 6)
]
const UNKNOWN_STATION := 999

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_switches_and_the_button_reach_every_client_as_its_view() -> void:
	_h = Harness.new(_mode(), true, null, _layouts())
	assert_bool(_h.started).is_true()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(0.5)
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 800)).is_true()
	_h.pump_seconds(0.5)
	var game := _h.session.game
	var task_state := FixtureGeneratorModes.state_of(game)
	assert_int(task_state.switches.size()).is_equal(FixtureGeneratorModes.SWITCHES)
	# The button before every switch is on changes nothing but its press.
	second.send_intent(Intents.INTERACT, {"station": task_state.generator})
	second.send_intent(Intents.INTERACT, {"station": UNKNOWN_STATION})
	for i in task_state.switches.size():
		var user := _h.own if i % 2 == 0 else second
		user.send_intent(Intents.INTERACT, {"station": task_state.switches[i]})
	_h.pump_seconds(0.5)
	assert_bool(task_state.on.has(false)).is_false()
	assert_bool(task_state.running).is_false()
	_h.own.send_intent(Intents.INTERACT, {"station": task_state.generator})
	_h.pump_seconds(FixtureGeneratorModes.SECONDS + 1.0)
	assert_bool(task_state.done).is_true()
	for client: ClientSession in _h.clients:
		assert_int(client.view.events_named(&"SwitchChanged").size()).is_equal(
			FixtureGeneratorModes.SWITCHES
		)
		assert_int(client.view.events_named(&"ButtonPressed").size()).is_equal(2)
		# The deal's at 0, the start, the done.
		assert_int(client.view.events_named(&"ZoneProgress").size()).is_equal(3)
		assert_array(client.view.events_named(&"TaskState")).is_not_empty()
		var station := client.model.stations[task_state.switches[0]]
		assert_bool(station.on).is_true()
		assert_int(client.model.stations[task_state.generator].presses).is_equal(2)
		assert_array(_h.mismatches(client)).is_empty()
	var refused := second.view.events_named(&"Rejected")
	assert_int(refused.size()).is_equal(1)
	var reason: String = refused[0].fields["reason"]
	assert_str(reason).is_equal("nothing_to_do")
	assert_array(_h.own.view.events_named(&"Rejected")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


## The harness's fixture mode with the settings `tasks` (1), `banned_task_types` and
## `active_switches` (all of them), the fixture Generator with stations that reach far, the deal
## first on the `all_loaded` row, Interact from the living and TaskTicks in Round.
static func _mode() -> GameMode:
	var made := Harness.fixture_mode()
	if made.find_setting(&"tasks") == null:
		made.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	if made.find_setting(&"banned_task_types") == null:
		made.settings.append(FixtureDealModes.banned_setting())
	var switches := FixtureGeneratorModes.SWITCHES
	made.settings.append(FixtureModes.setting(&"active_switches", switches, 0, switches))
	var type := FixtureGeneratorModes.generator_type()
	type.generator.radius_m = REACH_M
	type.switch.radius_m = REACH_M
	made.task_types = [type]
	var loaded := made.find_transition(&"loading", LoadingPhase.ALL_LOADED)
	loaded.actions.insert(0, FixtureDealModes.deal_tasks())
	var round_phase := made.find_phase(&"round")
	round_phase.accepts.append(AcceptSpec.of(Intents.INTERACT, AcceptSpec.From.LIVING))
	round_phase.tick_systems.append(TaskTicks.new())
	return made


## The harness's layouts with one `generator` marker and exactly SWITCHES `switch` markers on each
## map, near the players.
static func _layouts() -> Dictionary[String, LevelLayout]:
	var found := Harness.layouts()
	for map: String in [Harness.MAP, Harness.SMALL_MAP]:
		found[map].add_marker(&"generator", GENERATOR_AT)
		for spot: Vector3 in SWITCH_SPOTS:
			found[map].add_marker(&"switch", spot)
	return found
