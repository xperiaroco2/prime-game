extends GdUnitTestSuite
## The bots runner (tests/harness/bots/, ARCHITECTURE §4.6, §9.7) on scenarios built in code: it
## plays the core runner's steps through HostSession and ClientSessions, a failed scenario names its
## bot, step, last events and seed and leaves a command log that replays it (E13), and each check of
## the leak test (LeakCheck) fails on a planted leak. `tools\run.cmd bots` plays content/scenarios/.

const BASE_MODE := "res://content/modes/base_mode.tres"
const OUT := "user://bots_runner_test"


func after_test() -> void:
	if not DirAccess.dir_exists_absolute(OUT):
		return
	for file: String in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(OUT.path_join(file))
	DirAccess.remove_absolute(OUT)


func test_two_bots_ready_up_and_reach_the_round_through_the_network() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	assert_int(runner.peers.peer_of(1)).is_equal(1)
	assert_int(runner.peers.peer_of(2)).is_equal(2)
	for bot: ScenarioBot in runner.bots:
		var view := runner.clients[bot.number].view
		assert_array(view.event_names()).contains([&"Welcome", &"RoleAssigned", &"LoadMatch"])
		assert_array(view.snapshots.keys()).is_not_empty()
	# Proximity voice in the lobby: each heard the other's synthetic frames, unchanged.
	assert_array(runner.clients[1].view.speakers().values()).is_not_empty()
	# The lurker decoded nothing; the refused bot exactly its Rejected.
	assert_array(runner.lurker.view.events).is_empty()
	assert_array(runner.refused.view.event_names()).contains_exactly([&"Rejected"])
	assert_str(str(runner.refused.view.events[0].fields["reason"])).is_equal("wrong_version")


func test_a_failed_scenario_names_its_bot_step_and_seed_and_leaves_a_log_that_replays() -> void:
	var walk := StepWalkTo.new()
	walk.target = ScenarioTarget.new()
	walk.target.kind = ScenarioTarget.Kind.PACKAGE
	var scenario := _scenario([[StepReady.new()], [walk]])
	var runner := BotsRunner.play(scenario, OUT)
	var text := "\n".join(runner.failures)
	assert_str(text).contains("bot 2 (peer 2), step 1 (WalkTo)").contains("cannot know")
	assert_str(text).contains("its last events [").contains("seed %d" % scenario.session_seed)
	assert_str(runner.replay_path).starts_with(OUT)
	var recorded := ReplayFiles.read(runner.replay_path)
	assert_object(recorded).is_not_null()
	var replayed := Match.replay(recorded, scenario.mode)
	assert_array(Array(replayed.refusals)).is_empty()
	assert_int(replayed.emitted().size()).is_equal(runner.game.emitted().size())
	# Each bot's view file reads back as what it decoded.
	var file := ViewFile.read(OUT, 2)
	assert_int(file["peer"] as int).is_equal(2)
	var decoded: DecodedView = file["view"]
	assert_array(decoded.event_names()).is_equal(runner.clients[2].view.event_names())


func test_the_leak_check_fails_on_each_planted_leak() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	var leaks := LeakCheck.new(runner.game)
	var own := runner.clients[2].view
	assert_array(Array(leaks.check_bot("bot 2", 2, own, false))).is_empty()
	# An event view_of lacks, and a prefix where the whole view is due.
	var extra := _copy(own)
	extra.events.append(WireMessage.new(&"ReadyChanged", {"peer": 1, "ready": false}))
	assert_str(_text(leaks.check_bot("bot 2", 2, extra, true))).contains("beyond view_of")
	var short := _copy(own)
	short.events.pop_back()
	assert_str(_text(leaks.check_bot("bot 2", 2, short, false))).contains("view_of holds")
	assert_array(Array(leaks.check_bot("bot 2", 2, short, true))).is_empty()
	# Another player's view: the comparison sees its first event, bot 1's Welcome.
	var other := _copy(runner.clients[1].view)
	assert_str(_text(leaks.check_bot("bot 2", 2, other, true))).contains("event 0: decoded Welcome")
	# A snapshot of a tick view_of never sent, a speaker it may not hear, a changed frame.
	var tampered := _copy(own)
	tampered.snapshots[999999] = {"tick": 999999, "avatars": {}}
	tampered.voice[Vector2i(7, 3)] = [LeakCheck.voice_frame(7, 0)]
	var heard: Vector2i = own.voice.keys()[0]
	var changed := LeakCheck.voice_frame(heard.x, 5)
	changed[LeakCheck.FRAME_HEAD] = 0
	tampered.voice[heard] = [changed]
	var found := _text(leaks.check_bot("bot 2", 2, tampered, false))
	assert_str(found).contains("tick 999999 that view_of lacks")
	assert_str(found).contains("voice of 7 under tick 3")
	assert_str(found).contains("was changed")
	# A peer that is not a player and decoded an everyone event, a snapshot or voice.
	runner.lurker.view.events.append(own.events[0])
	runner.lurker.view.snapshots[1] = {"tick": 1, "avatars": {}}
	runner.lurker.view.voice[heard] = [LeakCheck.voice_frame(heard.x, 0)]
	var lurked := _text(leaks.check_watcher(runner.lurker))
	assert_str(lurked).contains("a peer that is not a player").contains("snapshots")
	assert_str(lurked).contains("decoded voice of 1 speaker-ticks")
	# Different task events for two bots present for the whole match.
	var tasks_a := DecodedView.new()
	var tasks_b := DecodedView.new()
	for view: DecodedView in [tasks_a, tasks_b]:
		view.events.append(WireMessage.new(&"LoadMatch", {"match_id": 1}))
		view.events.append(WireMessage.new(&"TaskProgress", {"done": 0, "total": 6}))
	tasks_b.events.append(WireMessage.new(&"TaskProgress", {"done": 1, "total": 6}))
	for view: DecodedView in [tasks_a, tasks_b]:
		view.events.append(WireMessage.new(&"MatchEnded", {"side": "crew"}))
	var views: Dictionary[String, DecodedView] = {"a": tasks_a, "b": tasks_b}
	assert_str(_text(leaks.check_tasks(views))).contains("different task events in match 1")


func test_a_teammates_for_a_role_that_does_not_know_them_is_a_leak() -> void:
	# Bot 2 is forced crew, which does not know its teammates (§5), bot 1 dissident.
	var scenario := _scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	scenario.forced_roles = {1: &"dissident", 2: &"crew"}
	var runner := BotsRunner.play(scenario)
	assert_array(Array(runner.failures)).is_empty()
	var view := runner.game.view_of(2)
	var teammates := runner.game.view_of(1).events_named(&"Teammates")
	assert_array(teammates).is_not_empty()
	# What a server/ that sent bot 1's Teammates to bot 2 would make view_of hold, decoded alike.
	view.events.append(teammates[0])
	var decoded := _copy(runner.clients[2].view)
	decoded.events.append(WireMessage.new(&"Teammates", teammates[0].to_dict()))
	var leaky := LeakyViews.new(runner.game, view)
	var found := _text(LeakCheck.new(leaky).check_bot("bot 2", 2, decoded, false))
	assert_str(found).contains("decoded Teammates as crew")


func test_a_teammates_of_another_role_or_naming_another_role_is_a_leak() -> void:
	var scenario := _scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	scenario.forced_roles = {1: &"dissident", 2: &"crew"}
	var runner := BotsRunner.play(scenario)
	assert_array(Array(runner.failures)).is_empty()
	# What bot 1 (dissident) would decode from a server/ that sent it the crew's Teammates.
	var teammates := runner.game.view_of(1).events_named(&"Teammates")[0] as TeammatesEvent
	teammates.role = &"crew"
	teammates.peers = PackedInt32Array([1, 2])
	var view := runner.game.view_of(1)
	var found := _text(LeakCheck.new(runner.game).check_bot("bot 1", 1, _decoded(view), false))
	assert_str(found).contains("decoded the Teammates of crew as dissident")
	assert_str(found).contains("decoded Teammates naming peer 2, not dissident")


func test_another_players_event_for_one_peer_is_a_leak() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	# What a server/ that sent bot 1's RoleAssigned to bot 2 would make view_of hold, decoded alike.
	var view := runner.game.view_of(2)
	view.events.append(runner.game.view_of(1).events_named(&"RoleAssigned")[0])
	var leaky := LeakyViews.new(runner.game, view)
	var found := _text(LeakCheck.new(leaky).check_bot("bot 2", 2, _decoded(view), false))
	assert_str(found).contains("decoded RoleAssigned of peer 1")


func test_a_living_bot_that_decoded_a_ghost_or_a_changed_snapshot_is_a_leak() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	var own := runner.clients[2].view
	var at_tick: int = own.snapshots.keys().back()
	# Peer 1 a ghost after that tick, bot 2 alive: what the observer would have recorded.
	var leaks := LeakCheck.new(runner.game)
	runner.game.state.players[1].life = PlayerState.Life.GHOST
	leaks.record_tick(at_tick)
	var tampered := _copy(own)
	var avatars: Dictionary = (own.snapshots[at_tick]["avatars"] as Dictionary).duplicate()
	avatars[1] = {"planted": true}
	tampered.snapshots[at_tick] = {"tick": at_tick, "avatars": avatars}
	tampered.voice[Vector2i(1, at_tick)] = [LeakCheck.voice_frame(1, 0)]
	var found := _text(leaks.check_bot("bot 2", 2, tampered, false))
	assert_str(found).contains("the snapshot of tick %d differs from view_of's" % at_tick)
	assert_str(found).contains("living, it decoded ghost 1 at tick %d" % at_tick)
	assert_str(found).contains("living, it heard ghost 1 at tick %d" % at_tick)


func test_a_decoded_seed_is_a_leak() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	var seed_value := 123_456_789_012
	var leaks := LeakCheck.new(runner.game)
	leaks.set_seeds([seed_value])
	var own := runner.clients[2].view
	assert_array(Array(leaks.check_bot("bot 2", 2, own, false))).is_empty()
	var tampered := _copy(own)
	var fields := tampered.events[0].fields.duplicate()
	fields["planted"] = seed_value
	tampered.events[0] = WireMessage.new(tampered.events[0].name, fields)
	var at_tick: int = own.snapshots.keys().back()
	var snapshot: Dictionary = own.snapshots[at_tick].duplicate()
	snapshot["planted"] = [seed_value]
	tampered.snapshots[at_tick] = snapshot
	var found := _text(leaks.check_bot("bot 2", 2, tampered, false))
	assert_str(found).contains("decoded Welcome holding a seed")
	assert_str(found).contains("the snapshot of tick %d holds a seed" % at_tick)


## A match whose view_of(peer) is a planted one.
class LeakyViews:
	extends Match
	var planted: PeerView
	var played: Match

	func _init(from: Match, view: PeerView) -> void:
		super(from.mode, 1, FlatWorldQuery.new(), {})
		state = from.state
		planted = view
		played = from

	func view_of(_peer: int) -> PeerView:
		return planted

	func emitted() -> Array[EmittedEvent]:
		return played.emitted()


func _scenario(scripts: Array) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = maxi(1, scripts.size())
	scenario.session_seed = 490_000_000_011
	scenario.expected_ends = [BotScenario.NONE]
	scenario.time_limit_s = 30.0
	var made: Array[BotScript] = []
	for steps: Array in scripts:
		var script := BotScript.new()
		for step: ScenarioStep in steps:
			script.steps.append(step)
		made.append(script)
	scenario.scripts = made
	return scenario


func _round() -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = &"PhaseChanged"
	step.fields = {"phase": "round"}
	return step


static func _copy(view: DecodedView) -> DecodedView:
	var copy := DecodedView.new()
	copy.peer = view.peer
	copy.events = view.events.duplicate()
	copy.snapshots = view.snapshots.duplicate()
	copy.voice = view.voice.duplicate()
	return copy


## What an honest client decodes from `view`'s events.
static func _decoded(view: PeerView) -> DecodedView:
	var decoded := DecodedView.new()
	decoded.peer = view.peer
	for event: MatchEvent in view.events:
		decoded.events.append(WireMessage.new(event.event_name(), event.to_dict()))
	return decoded


static func _text(found: PackedStringArray) -> String:
	return "\n".join(found)
