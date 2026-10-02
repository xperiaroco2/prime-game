extends GdUnitTestSuite
## The bots runner (tests/harness/bots/, ARCHITECTURE §4.6, §9.7) on scenarios built in code: it
## plays the core runner's steps through HostSession and ClientSessions, a failed scenario names its
## bot, step, last events and seed and leaves a command log that replays it (E13), and each check of
## the leak test (LeakCheck) fails on a planted leak, the PR #115 review's ones included: a second
## snapshot of a tick, a gap in a voice stream, lost packets, a lurker lost early, a refused bot not
## refused, a view with no peer, a prefix short of the last MatchEnded. `tools\run.cmd bots` plays
## content/scenarios/.

const BASE_MODE := "res://content/modes/base_mode.tres"
const OUT := "user://bots_runner_test"
const EVENTS_DIR := "res://core/events"
const DROPPED := "res://content/scenarios/dropped_at_the_loading_deadline.tres"


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
	# The lurker decoded nothing; the refused bot exactly its Rejected, then was disconnected.
	assert_array(runner.lurker.view.events).is_empty()
	assert_array(runner.refused.view.event_names()).contains_exactly([&"Rejected"])
	assert_str(str(runner.refused.view.events[0].fields["reason"])).is_equal("wrong_version")
	assert_bool(runner.refused.lost).is_true()
	# Nothing superseded on the LATEST lane, and each speaker's seqs from 0 without a gap.
	for bot: ScenarioBot in runner.bots:
		var client := runner.clients[bot.number]
		assert_int(client.transport().latest_superseded).is_equal(0)
		assert_array(client.view.repeated_snapshots).is_empty()
	var seqs := runner.clients[2].view.voice_seqs
	assert_array(seqs.values()).is_not_empty()


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


func test_a_bot_that_decoded_a_dead_avatar_or_voice_or_a_changed_snapshot_is_a_leak() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	var own := runner.clients[2].view
	var at_tick: int = own.snapshots.keys().back()
	# Peer 1 dead after that tick, bot 2 alive: what the observer would have recorded.
	var leaks := LeakCheck.new(runner.game)
	runner.game.state.players[1].life = PlayerState.Life.DEAD
	leaks.record_tick(at_tick)
	var tampered := _copy(own)
	var avatars: Dictionary = (own.snapshots[at_tick]["avatars"] as Dictionary).duplicate()
	avatars[1] = {"planted": true}
	tampered.snapshots[at_tick] = {"tick": at_tick, "avatars": avatars}
	tampered.voice[Vector2i(1, at_tick)] = [LeakCheck.voice_frame(1, 0)]
	var found := _text(leaks.check_bot("bot 2", 2, tampered, false))
	assert_str(found).contains("the snapshot of tick %d differs from view_of's" % at_tick)
	assert_str(found).contains("it decoded the avatar of dead 1 at tick %d" % at_tick)
	assert_str(found).contains("it heard dead 1 at tick %d" % at_tick)


func test_an_event_that_reaches_the_dead_and_not_every_living_peer_is_a_leak() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	var game := runner.game
	# Past the deal's tick, whose Teammates went to the dissidents alone.
	FixtureModes.run_ticks(game, 2)
	game.state.players[2].life = PlayerState.Life.DEAD
	# The control: an event for the dead peer alone, and one for everyone, are no leak.
	game.emit_event(CorrectionEvent.new(2, 9, Vector3.ZERO, Vector3.ZERO))
	game.emit_event(FixtureNoteEvent.new("for everyone"))
	var last: EmittedEvent = game.emitted().back()
	var at_tick := last.tick
	var leaks := LeakCheck.new(game)
	leaks.record_tick(at_tick)
	var found := _text(leaks.check_bot("bot 2", 2, _decoded(game.view_of(2)), false))
	assert_str(found).not_contains("dead, it decoded")
	# Planted: an event declared to the dead alone.
	game.emit_event(FixtureNoteEvent.new("for the dead", Audience.of_life(PlayerState.Life.DEAD)))
	found = _text(leaks.check_bot("bot 2", 2, _decoded(game.view_of(2)), false))
	assert_str(found).contains(
		"dead, it decoded FixtureNote at tick %d, which living 1 did not" % at_tick
	)


func test_a_downed_bot_hearing_the_not_living_or_a_dead_bot_hearing_anyone_is_a_leak() -> void:
	var scripts := []
	for bot in 3:
		scripts.append([StepReady.new(), _round()])
	var runner := BotsRunner.play(_scenario(scripts))
	assert_array(Array(runner.failures)).is_empty()
	var at_tick: int = runner.clients[2].view.snapshots.keys().back()
	# Peer 2 downed and peer 3 dead after that tick, peer 1 alive: what the observer would have
	# recorded. The control first: bot 2 hearing the living
	# peer 1 is no leak.
	var leaks := LeakCheck.new(runner.game)
	runner.game.state.players[2].life = PlayerState.Life.DOWNED
	runner.game.state.players[3].life = PlayerState.Life.DEAD
	leaks.record_tick(at_tick)
	var downed := _copy(runner.clients[2].view)
	downed.voice[Vector2i(1, at_tick)] = [LeakCheck.voice_frame(1, 0)]
	var found := _text(leaks.check_bot("bot 2", 2, downed, false))
	assert_str(found).not_contains("downed, it heard")
	downed.voice[Vector2i(3, at_tick)] = [LeakCheck.voice_frame(3, 0)]
	found = _text(leaks.check_bot("bot 2", 2, downed, false))
	assert_str(found).contains("downed, it heard 3, who was not living, at tick %d" % at_tick)
	assert_str(found).not_contains("downed, it heard 1,")
	var dead := _copy(runner.clients[3].view)
	dead.voice[Vector2i(1, at_tick)] = [LeakCheck.voice_frame(1, 0)]
	found = _text(leaks.check_bot("bot 3", 3, dead, false))
	assert_str(found).contains("dead, it heard 1 at tick %d" % at_tick)


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


func test_a_second_snapshot_a_gap_in_a_voice_stream_and_lost_packets_are_leaks() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	var leaks := LeakCheck.new(runner.game)
	var own := runner.clients[2].view
	assert_array(Array(leaks.check_voice_streams("bot 2", 2, own))).is_empty()
	# A second snapshot of a tick, kept apart by DecodedView.
	var tampered := _copy(own)
	var at_tick: int = own.snapshots.keys().back()
	tampered.repeated_snapshots.append(own.snapshots[at_tick])
	var found := _text(leaks.check_bot("bot 2", 2, tampered, false))
	assert_str(found).contains("a second snapshot of tick %d" % at_tick)
	# A seq that is not the stream's next: the speaker's own, say.
	var heard: Vector2i = own.voice_seqs.keys().back()
	var seqs: PackedInt32Array = own.voice_seqs[heard]
	tampered.voice_seqs[heard] = PackedInt32Array([seqs[0] + 5])
	var gap := _text(leaks.check_voice_streams("bot 2", 2, tampered))
	assert_str(gap).contains(
		"voice of %d under tick %d has seq %d" % [heard.x, heard.y, seqs[0] + 5]
	)
	# A superseded LATEST message, a rejected packet, a message that did not decode.
	var transport := LoopbackTransport.new(runner.schema.kind_table(), LoopbackHub.new())
	assert_array(Array(LeakCheck.check_counters("bot 2", 2, transport, 0, true))).is_empty()
	transport.latest_superseded = 1
	transport.rejects.count(1, NetRejects.Reason.TOO_SHORT)
	var lost := _text(LeakCheck.check_counters("bot 2", 2, transport, 3, true))
	assert_str(lost).contains("1 LATEST messages were superseded")
	assert_str(lost).contains("rejected 1 packets").contains("3 messages did not decode")
	assert_str(_text(LeakCheck.check_counters("bot 2", 2, transport, 0, false))).not_contains(
		"LATEST"
	)
	# The host's side: no message over budget, no packet its transport rejected.
	assert_array(Array(runner.host_problems())).is_empty()
	runner.session.over_budget = 2
	runner.host_transport.rejects.count(2, NetRejects.Reason.TOO_SHORT)
	var host := _text(runner.host_problems())
	assert_str(host).contains("2 messages over budget").contains("rejected 1 packets")


func test_a_lurker_lost_early_or_a_refused_bot_not_refused_fails() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	var leaks := LeakCheck.new(runner.game)
	# Entering Loading disconnected the lurker (core/'s DisconnectPeer): no failure.
	assert_bool(runner.lurker.lost).is_true()
	assert_array(Array(leaks.check_watcher(runner.lurker))).is_empty()
	# A lurker that lost its connection with no DisconnectPeer of core/ (a hello deadline).
	var early := BotWatcher.lurker(
		LoopbackTransport.new(runner.schema.kind_table(), runner.hub), runner.schema
	)
	early.peer = 99
	early.lost = true
	assert_str(_text(leaks.check_watcher(early))).contains("core/ never disconnected it")
	# A lurker core/ cut off at once, before any match (here: at the refused bot's tick).
	var cut := BotWatcher.lurker(
		LoopbackTransport.new(runner.schema.kind_table(), runner.hub), runner.schema
	)
	cut.peer = runner.refused.peer
	cut.lost = true
	assert_str(_text(leaks.check_watcher(cut))).contains("not on entering Loading")
	# A lurker core/ disconnected that server/ left connected.
	runner.lurker.lost = false
	assert_str(_text(leaks.check_watcher(runner.lurker))).contains("but it is still connected")
	# A refused bot that decoded no Rejected and stayed connected.
	runner.refused.view.events.clear()
	runner.refused.lost = false
	var refused := _text(leaks.check_watcher(runner.refused))
	assert_str(refused).contains("decoded 0 Rejected, not exactly one (wrong_version)")
	assert_str(refused).contains("but it is still connected")
	assert_str(refused).not_contains("never emitted DisconnectPeer")
	# A refused bot core/ never disconnected.
	var ignored := BotWatcher.refused(
		LoopbackTransport.new(runner.schema.kind_table(), runner.hub), runner.schema, 0
	)
	ignored.peer = 98
	assert_str(_text(leaks.check_watcher(ignored))).contains("core/ never emitted DisconnectPeer")


func test_a_short_prefix_a_view_with_no_peer_and_audiences_for_one() -> void:
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	# A view with events but no peer id is a failure, not skipped.
	var own := runner.clients[2].view
	var leaks := LeakCheck.new(runner.game)
	assert_str(_text(leaks.check_bot("bot 2", 0, own, true))).contains("with no peer id")
	assert_array(Array(leaks.check_bot("bot 2", 0, DecodedView.new(), true))).is_empty()
	var voice_only := DecodedView.new()
	voice_only.voice[Vector2i(1, 5)] = [LeakCheck.voice_frame(1, 0)]
	assert_str(_text(leaks.check_bot("bot 2", 0, voice_only, true))).contains("with no peer id")
	# Over ENet a prefix must reach view_of's last MatchEnded.
	var view := runner.game.view_of(2)
	view.events.append(MatchEndedEvent.new(&"crew"))
	view.events.append(ReadyChangedEvent.new(1, false))
	var leaky := LeakCheck.new(LeakyViews.new(runner.game, view))
	var decoded := _decoded(view)
	decoded.events.resize(view.events.size() - 2)
	var short := _text(leaky.check_bot("bot 2", 2, decoded, true, true))
	assert_str(short).contains("short of view_of's last MatchEnded")
	assert_array(Array(leaky.check_bot("bot 2", 2, decoded, true))).is_empty()
	decoded.events.append(WireMessage.new(&"MatchEnded", {"side": &"crew"}))
	assert_array(Array(leaky.check_bot("bot 2", 2, decoded, true, true))).is_empty()
	# The events for one peer: FOR_ONE, or a class declaring ONLY or SENDER.
	var assigned := runner.game.view_of(1).events_named(&"RoleAssigned")[0]
	assert_bool(LeakCheck.for_one(assigned)).is_true()
	assert_bool(LeakCheck.for_one(RejectedEvent.new(2, 1, &"full"))).is_true()
	assert_bool(LeakCheck.for_one(MatchEndedEvent.new(&"crew"))).is_false()
	assert_bool(LeakCheck.for_one(TeammatesEvent.new(&"crew", PackedInt32Array([1])))).is_false()


func test_a_listed_event_for_one_peer_declared_for_everyone_is_still_checked() -> void:
	# A Correction whose class declares no one-peer audience (a misdeclaration) is still for one
	# peer, so a Correction of another player is a leak.
	var misdeclared := MisdeclaredCorrection.new(2)
	assert_bool(LeakCheck.declares_one(misdeclared.get_script() as Script)).is_false()
	assert_bool(LeakCheck.for_one(misdeclared)).is_true()
	var runner := BotsRunner.play(
		_scenario([[StepReady.new(), _round()], [StepReady.new(), _round()]])
	)
	assert_array(Array(runner.failures)).is_empty()
	var view := runner.game.view_of(1)
	view.events.append(misdeclared)
	var leaky := LeakCheck.new(LeakyViews.new(runner.game, view))
	var found := _text(leaky.check_bot("bot 1", 1, _decoded(view), false))
	assert_str(found).contains("decoded Correction of peer 2")


func test_every_event_class_for_one_peer_is_listed_in_for_one() -> void:
	var missing: Array[String] = []
	var checked := 0
	for file: String in DirAccess.get_files_at(EVENTS_DIR):
		if not file.ends_with(".gd"):
			continue
		var script := load(EVENTS_DIR.path_join(file)) as Script
		if not LeakCheck.declares_one(script):
			continue
		checked += 1
		var event_name := StringName(str(script.get_global_name()).trim_suffix("Event"))
		if not LeakCheck.FOR_ONE.has(event_name):
			missing.append(event_name)
	assert_int(checked).is_greater_equal(LeakCheck.FOR_ONE.size())
	assert_array(missing).is_empty()


func test_disconnecting_reaches_only_the_dropped_player_and_a_misdeclared_one_is_a_leak() -> void:
	# #119: the player dropped at the loading deadline alone decodes why, and its session ends so.
	var scenario := load(DROPPED) as BotScenario
	var runner := BotsRunner.play(scenario)
	assert_array(Array(runner.failures)).is_empty()
	var dropped := runner.peers.peer_of(3)
	assert_str(String(runner.clients[3].end_reason)).is_equal("load_deadline")
	assert_array(runner.clients[3].view.events_named(&"Disconnecting")).has_size(1)
	for bot: int in [1, 2]:
		assert_array(runner.clients[bot].view.events_named(&"Disconnecting")).is_empty()
	# The planted leak: Disconnecting declared to everyone reaches bot 1 too.
	var leaked := runner.game.view_of(1)
	leaked.events.append(MisdeclaredDisconnecting.new(dropped))
	var leaky := LeakCheck.new(LeakyViews.new(runner.game, leaked))
	var found := _text(leaky.check_bot("bot 1", 1, _decoded(leaked), false))
	assert_str(found).contains("decoded Disconnecting of peer %d" % dropped)


## A Correction whose class declares no AUDIENCE_KIND.
class MisdeclaredCorrection:
	extends MatchEvent
	var peer: int

	func _init(to_peer: int) -> void:
		peer = to_peer

	func event_name() -> StringName:
		return &"Correction"

	func audience() -> Audience:
		return Audience.everyone()

	func to_dict() -> Dictionary:
		return {"epoch": 1, "position": Vector3.ZERO, "velocity": Vector3.ZERO}


## Disconnecting declared to everyone: the planted leak of #119.
class MisdeclaredDisconnecting:
	extends MatchEvent
	var peer: int

	func _init(to_peer: int) -> void:
		peer = to_peer

	func event_name() -> StringName:
		return &"Disconnecting"

	func audience() -> Audience:
		return Audience.everyone()

	func to_dict() -> Dictionary:
		return {"reason": DisconnectingEvent.LOAD_DEADLINE}


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
	copy.repeated_snapshots = view.repeated_snapshots.duplicate()
	copy.voice = view.voice.duplicate()
	copy.voice_seqs = view.voice_seqs.duplicate()
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
