extends GdUnitTestSuite
## The ENet bots runner's start (BotsEnet, ARCHITECTURE §4.6, #284): its instances are processes
## that a loaded machine starts seconds apart, so bot 1 acts only once every bot that joins at the
## start is in its lobby, and a remote bot whose join went unanswered joins again. Built in code,
## no process started: `tools\run.cmd bots <scenario> --instances N` runs the real thing.

const BASE_MODE := "res://content/modes/base_mode.tres"
const NO_PORT := 9
const OUT := "user://bots_enet_test"
const START_USEC := 1_000_000
const FRAME_USEC := 16_667


## Bot 2's instance with its joins on a LoopbackTransport that is never hosted: no ENet client.
## Each join it starts records whether bot 2's client was made by then.
class RemoteBot:
	extends BotsEnet

	var client_made_at_join: Array[bool] = []
	var join_started_usec := START_USEC

	func _init(bot_scenario: BotScenario) -> void:
		super(bot_scenario, 2, NO_PORT, OUT)

	func add_bot() -> ScenarioBot:
		var bot := ScenarioBot.new(2, 0, scenario.steps_of(2), peers)
		bots.append(bot)
		return bot

	func _unjoined() -> NetTransport:
		return LoopbackTransport.new(schema.kind_table(), null)

	func _join_started_usec() -> int:
		return join_started_usec

	func _start_join(transport: NetTransport) -> void:
		var client: BotClient = clients.get(2)
		client_made_at_join.append(client != null and client.transport() == transport)


func test_bot_1_acts_once_every_bot_that_joins_at_the_start_is_in_its_lobby() -> void:
	var late := StepJoin.new()
	var runner := BotsEnet.new(_scenario([[], [], [late]]), 1, NO_PORT, OUT)
	var bot := ScenarioBot.new(1, 1, [], runner.peers)
	runner.peers.set_peer(1, 1)
	assert_bool(runner._lobby_full(bot)).is_false()
	runner.peers.set_peer(2, 22)
	assert_bool(runner._lobby_full(bot)).is_false()
	bot.seen[22] = Vector3.ZERO
	# Bot 3 joins later (a Join step): bot 1 does not wait for it.
	assert_bool(runner._lobby_full(bot)).is_true()
	bot.seen.erase(22)
	assert_bool(runner._lobby_full(bot)).override_failure_message("decided once").is_true()


func test_bot_1_waits_for_a_bot_it_knows_the_peer_of_until_that_bot_joined() -> void:
	var runner := BotsEnet.new(_scenario([[], [], []]), 1, NO_PORT, OUT)
	var bot := ScenarioBot.new(1, 1, [], runner.peers)
	runner.peers.set_peer(2, 22)
	runner.peers.set_peer(3, 33)
	bot.seen[22] = Vector3.ZERO
	assert_bool(runner._lobby_full(bot)).is_false()
	bot.seen[33] = Vector3.ZERO
	assert_bool(runner._lobby_full(bot)).is_true()


func test_a_remote_bot_whose_join_went_unanswered_joins_again() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var first: BotClient = runner.clients[2]
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("still joining").is_same(first)
	runner.now_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	first.end_reason = ClientSession.CONNECT_FAILED
	runner._join_again(bot)
	var second: BotClient = runner.clients[2]
	assert_object(second).is_not_same(first)
	assert_array(runner.failures).is_empty()
	second.leave()


## A remote bot's join, the first and one joined again, starts once its client is made (#950):
## making a ClientSession hashes the mode's level files, seconds on a PC with the house's assets,
## and a join started before it ran out its real-time limits meanwhile (over WebRTC every join
## ended at the signalling's 5 s cap).
func test_a_remote_bots_join_starts_once_its_client_is_made() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var first: BotClient = runner.clients[2]
	runner.now_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	first.end_reason = ClientSession.CONNECT_FAILED
	runner._join_again(bot)
	assert_object(runner.clients[2]).is_not_same(first)
	assert_array(runner.client_made_at_join).contains_exactly([true, true])
	(runner.clients[2] as BotClient).leave()


func test_a_join_the_host_refused_at_once_does_not_join_again() -> void:
	# EnetTransport refuses before the admission by disconnecting: connect_failed within a poll.
	var runner := RemoteBot.new(_scenario([[], []]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var client: BotClient = runner.clients[2]
	client.end_reason = ClientSession.CONNECT_FAILED
	runner.now_usec += FRAME_USEC
	runner._join_again(bot)
	assert_object(runner.clients[2]).is_same(client)
	runner.now_usec += 2 * EnetTransport.JOIN_TIMEOUT_MS * 1000
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("judged when first seen").is_same(
		client
	)


func test_a_remote_bot_the_host_refused_or_lost_does_not_join_again() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var client: BotClient = runner.clients[2]
	runner.now_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	# A Rejected Hello: the host admitted the join, then disconnected it.
	client.end_reason = ClientSession.HOST_LOST
	runner._join_again(bot)
	assert_object(runner.clients[2]).is_same(client)
	client.end_reason = ClientSession.CONNECT_FAILED
	bot.joined = true
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("it had joined").is_same(client)


func test_a_bot_that_joins_late_does_not_join_again() -> void:
	var runner := RemoteBot.new(_scenario([[], [StepJoin.new()]]))
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	var client: BotClient = runner.clients[2]
	runner.now_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	client.end_reason = ClientSession.CONNECT_FAILED
	runner._join_again(bot)
	assert_object(runner.clients[2]).override_failure_message("its Join step reads it").is_same(
		client
	)


func test_over_webrtc_a_join_that_found_no_room_joins_again_after_a_short_wait() -> void:
	# The host's process, or its signalling's room, is not up yet: the service answers at once.
	for reason: StringName in [NetTransport.JOIN_NO_ROOM, NetTransport.JOIN_SERVICE_UNREACHABLE]:
		var runner := RemoteBot.new(_scenario([[], []]))
		var bot := runner.add_bot()
		runner.now_usec = START_USEC
		runner._join_host(bot)
		var first: BotClient = runner.clients[2]
		first.end_reason = reason
		runner.now_usec += FRAME_USEC
		runner._join_again(bot)
		assert_object(runner.clients[2]).override_failure_message("waits first").is_same(first)
		assert_bool(runner._fail_lost_join(bot)).override_failure_message("not lost").is_false()
		assert_array(runner.failures).is_empty()
		runner.now_usec += JoinRetry.ROOM_RETRY_USEC
		runner._join_again(bot)
		var second: BotClient = runner.clients[2]
		assert_object(second).override_failure_message(String(reason)).is_not_same(first)
		second.leave()


func test_over_webrtc_a_join_that_reached_the_room_does_not_join_again() -> void:
	# The match has started, or the room is full: the host's own answer. host_unreachable: the
	# service answered and the connection never opened, a transport fault the run must not ride out.
	for reason: StringName in [
		NetTransport.JOIN_STARTED,
		NetTransport.JOIN_FULL,
		NetTransport.JOIN_UNREACHABLE,
		NetTransport.JOIN_FAILED,
	]:
		var runner := RtcRemoteBot.new(_scenario([[], []]))
		var bot := runner.add_bot()
		runner.now_usec = START_USEC
		runner._join_host(bot)
		var client: BotClient = runner.clients[2]
		runner.now_usec += WebRtcTransport.JOIN_TIMEOUT_MS * 1000
		client.end_reason = reason
		runner._join_again(bot)
		runner.now_usec += 2 * WebRtcTransport.JOIN_TIMEOUT_MS * 1000
		runner._join_again(bot)
		assert_object(runner.clients[2]).override_failure_message(String(reason)).is_same(client)
		client.leave()


## Bot 2's instance over WebRTC, its joins never started (no signalling).
class RtcRemoteBot:
	extends RemoteBot

	func _unjoined() -> NetTransport:
		return WebRtcTransport.new(schema.kind_table())


## A scenario of one script per bot in the base mode, each a list of steps.
func _scenario(scripts: Array) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = scripts.size()
	scenario.session_seed = 490_000_000_284
	scenario.expected_ends = [BotScenario.NONE]
	var made: Array[BotScript] = []
	for steps: Array in scripts:
		var script := BotScript.new()
		for step: ScenarioStep in steps:
			script.steps.append(step)
		made.append(script)
	scenario.scripts = made
	return scenario


func before_test() -> void:
	DirAccess.remove_absolute(OUT.path_join(BotsEnet.HOST_UP_FILE))


func after_test() -> void:
	DirAccess.remove_absolute(OUT.path_join(BotsEnet.HOST_UP_FILE))


## A remote bot's clock and its first join start once the host serves (#950): the host's start
## took seconds, and a clock started with the process ran the scenario's spacing out meanwhile.
func test_a_remote_bots_clock_and_join_start_once_the_host_is_up() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	assert_bool(runner.start(START_USEC)).is_true()
	assert_bool(runner.clients.has(2)).override_failure_message("joined before the host").is_false()
	var later := START_USEC + 2 * BotsEnet.PEERS_READ_USEC
	runner.step(later)
	assert_bool(runner.clients.has(2)).override_failure_message("joined before the host").is_false()
	runner._write_host_up()
	assert_bool(FileAccess.file_exists(OUT.path_join(BotsEnet.HOST_UP_FILE))).is_true()
	var up := later + BotsEnet.PEERS_READ_USEC
	runner.step(up)
	assert_bool(runner.clients.has(2)).override_failure_message("joined once up").is_true()
	assert_int(runner._start_usec).is_equal(up)
	assert_int(runner.tick_now).is_equal(0)
	assert_array(runner.failures).is_empty()
	(runner.clients[2] as BotClient).leave()


func test_a_remote_bot_whose_host_never_came_up_starts_after_the_wait() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	assert_bool(runner.start(START_USEC)).is_true()
	var just_before := START_USEC + BotsEnet.HOST_UP_WAIT_S * BotsEnet.USEC_PER_SECOND - 1
	runner.step(just_before)
	assert_bool(runner.clients.has(2)).is_false()
	runner.step(just_before + BotsEnet.PEERS_READ_USEC)
	assert_bool(runner.clients.has(2)).override_failure_message("joins as before").is_true()
	(runner.clients[2] as BotClient).leave()


func test_a_remote_bot_that_joins_late_starts_its_clock_without_joining() -> void:
	var late := StepJoin.new()
	late.at_s = 30.0
	var runner := RemoteBot.new(_scenario([[], [late]]))
	assert_bool(runner.start(START_USEC)).is_true()
	assert_bool(runner._clock_started).override_failure_message("before the host").is_false()
	runner._write_host_up()
	var up := START_USEC + BotsEnet.PEERS_READ_USEC
	runner.step(up)
	assert_bool(runner._clock_started).override_failure_message("host is up").is_true()
	assert_int(runner._start_usec).is_equal(up)
	assert_bool(runner.clients.has(2)).override_failure_message("its Join step joins").is_false()


## The join's retry clock starts with the join, after the client was made and hashed (#950).
func test_a_remote_bots_join_retry_clock_starts_with_the_join_not_before_its_client() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	runner.join_started_usec = START_USEC + 5_500_000
	runner._write_host_up()
	assert_bool(runner.start(START_USEC)).is_true()
	assert_int(runner._join_retry(2).started_usec).is_equal(START_USEC + 5_500_000)
	(runner.clients[2] as BotClient).leave()


## The host's clock starts at its first step, after its start (#950).
func test_the_hosts_clock_starts_at_its_first_step_after_its_start() -> void:
	var runner := BotsEnet.new(_scenario([[], []]), 1, NO_PORT, OUT)
	runner._start_usec = START_USEC
	runner._host_clock_pending = true
	var after_start := START_USEC + 6_000_000
	runner._sync_host_clock(after_start)
	assert_int(runner._start_usec).is_equal(after_start)
	runner._sync_host_clock(after_start + FRAME_USEC)
	assert_int(runner._start_usec).override_failure_message("once").is_equal(after_start)


func test_a_remote_bot_whose_join_was_lost_for_good_fails_at_once_and_writes_its_reason() -> void:
	var runner := RtcRemoteBot.new(_scenario([[], []]))
	runner._write_host_up()
	assert_bool(runner.start(START_USEC)).is_true()
	var client: BotClient = runner.clients[2]
	client.end_reason = NetTransport.JOIN_UNREACHABLE
	runner.step(START_USEC + FRAME_USEC)
	assert_bool(runner.done()).override_failure_message("waits for the time limit").is_true()
	var lost := Array(runner.failures).filter(
		func(line: String) -> bool:
			return line.contains("bot 2") and line.contains("lost for good (host_unreachable)")
	)
	assert_array(lost).has_size(1)
	var written := ViewFile.read(OUT, 2)
	DirAccess.remove_absolute(ViewFile.path_of(OUT, 2))
	var written_failures: PackedStringArray = written.get("failures", PackedStringArray())
	assert_array(Array(written_failures)).contains(lost)


func test_a_runner_that_never_joins_again_fails_a_lost_join_at_once() -> void:
	# PerfRun calls no _join_again: a join that went unanswered is lost for good, not a retry.
	var runner := NetPlay.new(_scenario([[], []]), ScenarioPeers.new())
	var bot := ScenarioBot.new(2, 0, [], runner.peers)
	runner.bots.append(bot)
	runner.now_usec = START_USEC
	var client := runner.add_client(bot, LoopbackTransport.new(runner.schema.kind_table(), null))
	runner.now_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	client.end_reason = ClientSession.CONNECT_FAILED
	runner.play_frame(0)
	assert_array(runner.failures).has_size(1)
	assert_str(runner.failures[0] if not runner.failures.is_empty() else "").contains(
		"lost for good (connect_failed)"
	)
	assert_bool(bot.gone).is_true()


func test_a_view_file_keeps_each_earlier_connection_and_an_old_file_has_none() -> void:
	var first := _view(70, [&"Welcome", &"PlayerJoined"])
	var last := _view(80, [&"Welcome"])
	var earlier: Array[Dictionary] = [{"peer": 70, "view": first, "order": {}}]
	assert_bool(ViewFile.write(OUT, 2, 80, last, PackedStringArray(), {}, earlier)).is_true()
	var written := ViewFile.read(OUT, 2)
	assert_int(written["peer"]).is_equal(80)
	assert_int((written["view"] as DecodedView).events.size()).is_equal(1)
	var lives: Array = written["earlier"]
	assert_int(lives.size()).is_equal(1)
	assert_int(lives[0]["peer"]).is_equal(70)
	var back: DecodedView = lives[0]["view"]
	assert_int(back.peer).is_equal(70)
	(
		assert_array(back.events.map(func(e: WireMessage) -> StringName: return e.name))
		. is_equal([&"Welcome", &"PlayerJoined"])
	)
	assert_dict(back.snapshots).is_equal(first.snapshots)
	# A file written before `earlier` existed reads with none.
	var raw := FileAccess.open(ViewFile.path_of(OUT, 2), FileAccess.READ)
	var data: Dictionary = raw.get_var(false)
	raw.close()
	data.erase("earlier")
	var old := FileAccess.open(ViewFile.path_of(OUT, 2), FileAccess.WRITE)
	old.store_var(data)
	old.close()
	var read_old := ViewFile.read(OUT, 2)
	DirAccess.remove_absolute(ViewFile.path_of(OUT, 2))
	assert_int(read_old["peer"]).is_equal(80)
	assert_array(read_old["earlier"]).is_empty()


func test_the_host_reads_only_whole_lines_of_a_peer_file_and_a_returning_bot_adds_a_line() -> void:
	var runner := BotsEnet.new(_scenario([[], []]), 1, NO_PORT, OUT)
	DirAccess.make_dir_recursive_absolute(OUT)
	var path := OUT.path_join("peer-2")
	# The second id is half written: only the first is known.
	_write_text(path, "70\n80")
	runner._read_peer_files()
	assert_int(runner.peers.peer_of(2)).is_equal(70)
	assert_array(runner.peers.peers_of(2)).is_equal([70])
	# Its newline arrived: 80 is the current peer, 70 the earlier one.
	_write_text(path, "70\n80\n")
	runner._read_peer_files()
	assert_int(runner.peers.peer_of(2)).is_equal(80)
	assert_array(runner.peers.peers_of(2)).is_equal([70, 80])
	# Read again, nothing changes.
	runner._read_peer_files()
	assert_array(runner.peers.peers_of(2)).is_equal([70, 80])
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(OUT.path_join(BotsEnet.PEERS_FILE))


func test_a_remote_bot_learns_the_new_peer_of_a_bot_that_returned() -> void:
	var runner := RemoteBot.new(_scenario([[], []]))
	DirAccess.make_dir_recursive_absolute(OUT)
	var path := OUT.path_join(BotsEnet.PEERS_FILE)
	_write_text(path, "1 11\n3 30")
	runner._read_peers(runner.peers)
	assert_int(runner.peers.peer_of(3)).is_equal(30)
	_write_text(path, "1 11\n3 30\n3 31")
	runner._read_peers(runner.peers)
	DirAccess.remove_absolute(path)
	assert_int(runner.peers.peer_of(3)).is_equal(31)
	assert_array(runner.peers.peers_of(3)).is_equal([30, 31])


func test_a_returned_bot_writes_its_view_at_the_end_of_its_script_another_waits_for_the_end(
) -> void:
	var scenario := _scenario([[], []])
	scenario.expected_ends = [&"dissidents"]
	var runner := RemoteBot.new(scenario)
	var bot := runner.add_bot()
	# Its script is over and the match has not ended (no MatchEnded decoded): it waits.
	assert_bool(runner._view_due(bot)).override_failure_message("did not wait").is_false()
	# It left and joined again: its last connection may have joined after the end, so it writes now.
	bot.lives.append({"peer": 70, "events": []})
	assert_bool(runner._view_due(bot)).override_failure_message("a returned bot waits").is_true()


func test_a_returned_bot_inside_a_match_waits_for_its_end_or_its_connection_to_close() -> void:
	var scenario := _scenario([[], []])
	scenario.expected_ends = [&"dissidents"]
	var runner := RemoteBot.new(scenario)
	var bot := runner.add_bot()
	runner.now_usec = START_USEC
	runner._join_host(bot)
	bot.lives.append({"peer": 70, "events": []})
	# Its script is over, its current connection plays a round, and no MatchEnded came yet (#918).
	bot.phase = &"round"
	assert_bool(runner._view_due(bot)).override_failure_message("wrote mid-match").is_false()
	# Its MatchEnded came: it writes.
	runner.ends.append(&"dissidents")
	assert_bool(runner._view_due(bot)).override_failure_message("waits past the end").is_true()
	# Without its MatchEnded, its connection's close also ends the wait.
	runner.ends.clear()
	assert_bool(runner._view_due(bot)).override_failure_message("ended too soon").is_false()
	var client: BotClient = runner.clients[2]
	client.leave()
	assert_bool(runner._view_due(bot)).override_failure_message("waits a closed one").is_true()


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _view(peer: int, names: Array[StringName]) -> DecodedView:
	var view := DecodedView.new()
	view.peer = peer
	for event_name: StringName in names:
		view.events.append(WireMessage.new(event_name, {}))
	view.snapshots[3] = {"avatars": {}}
	return view
