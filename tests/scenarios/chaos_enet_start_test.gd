extends GdUnitTestSuite
## The chaos run's start over ENet (ChaosRun, ARCHITECTURE §4.6 "Chaos bots", #318): as BotsEnet
## after #284, the bots play once every bot that joins at the start is in bot 1's lobby, and a bot
## whose join went unanswered joins again, judged on the real clock. Built in code, no ENet socket:
## `tools\run.cmd bots --chaos --enet` runs the real thing.

const NO_PORT := 9
const FRAME_USEC := 16_667
const START_USEC := 1_000_000


## The chaos run over ENet with its bots' joins on a LoopbackTransport of an empty hub (no host:
## connect_failed at the first poll), on a join clock the test sets.
class UnhostedChaos:
	extends ChaosRun

	var clock_usec := START_USEC

	func _init() -> void:
		super(false, ChaosRun.Mode.CHAOS, 1, NO_PORT)

	func add_bots() -> void:
		for number in range(1, scenario.bots + 1):
			bots.append(ScenarioBot.new(number, 0, scenario.steps_of(number), peers))

	func _joining() -> NetTransport:
		var transport := LoopbackTransport.new(schema.kind_table(), LoopbackHub.new())
		transport.join("loopback", NO_PORT)
		return transport

	func _chaos_joining() -> Dictionary:
		var loopback := ChaosLoopback.new(schema.kind_table(), LoopbackHub.new())
		loopback.join("loopback", NO_PORT)
		return {"transport": loopback, "take": loopback.take_outbox, "send_raw": loopback.send_raw}

	func _join_clock_usec() -> int:
		return clock_usec

	## Bot 1 joined (the host's own client in a real run), the others joining, the malformed peer
	## made: what play_frame needs, without a host.
	func join_without_host() -> void:
		add_bots()
		bots[0].connected = true
		bots[0].joined = true
		add_client(bots[0], _joining())
		for bot: ScenarioBot in bots.slice(1):
			_connect(bot)
		var joined := _chaos_joining()
		malformed = ChaosMalformed.new(
			joined["transport"] as NetTransport, joined["send_raw"] as Callable, schema, 2
		)


func test_over_enet_the_bots_play_once_every_bot_is_in_bot_1s_lobby() -> void:
	var run := UnhostedChaos.new()
	run.add_bots()
	var host := run.bots[0]
	for number in range(1, run.scenario.bots + 1):
		run.peers.set_peer(number, 10 * number)
	# Every peer id is known (each bot `connected`), but no Hello was admitted yet.
	assert_bool(run._may_play()).override_failure_message("peer ids alone").is_false()
	host.seen[20] = Vector3.ZERO
	host.seen[30] = Vector3.ZERO
	assert_bool(run._may_play()).override_failure_message("the hostile not joined").is_false()
	host.seen[40] = Vector3.ZERO
	assert_bool(run._may_play()).is_true()
	host.seen.clear()
	assert_bool(run._may_play()).override_failure_message("decided once").is_true()


func test_over_the_loopback_the_bots_play_at_once() -> void:
	var run := ChaosRun.new()
	for number in range(1, run.scenario.bots + 1):
		run.bots.append(ScenarioBot.new(number, 0, run.scenario.steps_of(number), run.peers))
	assert_bool(run._may_play()).is_true()


func test_a_bot_whose_join_went_unanswered_joins_again() -> void:
	var run := UnhostedChaos.new()
	run.add_bots()
	var bot := run.bots[1]
	run._connect(bot)
	var first: BotClient = run.clients[2]
	first.step(START_USEC)
	assert_str(first.end_reason).is_equal(ClientSession.CONNECT_FAILED)
	run.clock_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	run._join_again(bot)
	var second: BotClient = run.clients[2]
	assert_object(second).is_not_same(first)
	assert_bool(second.is_ended()).is_false()
	assert_bool(run._may_play()).override_failure_message("it is joining again").is_false()
	assert_array(run.failures).is_empty()
	second.leave()


func test_a_join_refused_at_once_does_not_join_again_and_ends_the_wait() -> void:
	var run := UnhostedChaos.new()
	run.add_bots()
	var bot := run.bots[1]
	run._connect(bot)
	var client: BotClient = run.clients[2]
	client.step(START_USEC)
	run.clock_usec += FRAME_USEC
	run._join_again(bot)
	assert_object(run.clients[2]).is_same(client)
	run.clock_usec += 2 * EnetTransport.JOIN_TIMEOUT_MS * 1000
	run._join_again(bot)
	assert_object(run.clients[2]).override_failure_message("judged when first seen").is_same(client)
	# The bots play, so that its lost join fails the run at once (_lost), not at the time limit.
	assert_bool(run._may_play()).is_true()


func test_play_frame_joins_again_and_holds_bot_1_until_the_lobby_is_full() -> void:
	var run := UnhostedChaos.new()
	run.join_without_host()
	var first: BotClient = run.clients[2]
	first.step(START_USEC)
	assert_str(first.end_reason).is_equal(ClientSession.CONNECT_FAILED)
	run.clock_usec += EnetTransport.JOIN_TIMEOUT_MS * 1000
	run.play_frame(0)
	assert_object(run.clients[2]).override_failure_message("joined again").is_not_same(first)
	# Bot 1's first step (Ready) waits for the full lobby.
	assert_int(run.bots[0].step_index).override_failure_message("bot 1 acted").is_equal(0)
	assert_array(run.failures).is_empty()
	run.close()


func test_a_run_out_of_time_names_the_lobby_bot_1_waited_for() -> void:
	var run := UnhostedChaos.new()
	run.join_without_host()
	run._fail_time_limit()
	var waited := Array(run.failures).filter(
		func(line: String) -> bool: return line.begins_with("bot 1 waited for the lobby")
	)
	assert_array(waited).has_size(1)
	run.close()


func test_over_enet_a_join_is_judged_on_the_real_clock() -> void:
	var run := ChaosRun.new(false, ChaosRun.Mode.CHAOS, 1, NO_PORT)
	# Behind any real clock: the simulated one starts at BotsRunner.START_USEC.
	run.now_usec = -1
	var started := Time.get_ticks_usec()
	assert_int(run._join_clock_usec()).is_greater_equal(started)
	var loopback := ChaosRun.new()
	loopback.now_usec = START_USEC
	assert_int(loopback._join_clock_usec()).is_equal(START_USEC)


func test_a_join_lost_for_good_fails_the_run_at_once_naming_its_reason() -> void:
	# The connection never opened, the match started, the room is full, the host dropped the join
	# before its Welcome, the host refused it at once: none joins again (#483).
	for reason: StringName in [
		NetTransport.JOIN_UNREACHABLE,
		NetTransport.JOIN_STARTED,
		NetTransport.JOIN_FULL,
		ClientSession.HOST_LOST,
		ClientSession.CONNECT_FAILED,
	]:
		var run := UnhostedChaos.new()
		run.join_without_host()
		run.clients[2].end_reason = reason
		run.play_frame(0)
		assert_array(run.failures).override_failure_message(String(reason)).has_size(1)
		var line := run.failures[0] if not run.failures.is_empty() else ""
		assert_str(line).contains("bot 2").contains("lost for good").contains(String(reason))
		assert_str(line).not_contains("earlier joins")
		assert_bool(run.bots[1].gone).is_true()
		assert_int(run.bots[0].step_index).override_failure_message("bot 1 acted").is_equal(0)
		run.close()


func test_a_join_that_found_no_room_joins_again_without_starting_play() -> void:
	for reason: StringName in [NetTransport.JOIN_NO_ROOM, NetTransport.JOIN_SERVICE_UNREACHABLE]:
		var run := UnhostedChaos.new()
		run.join_without_host()
		var first: BotClient = run.clients[2]
		first.end_reason = reason
		run.play_frame(0)
		assert_array(run.failures).override_failure_message(String(reason)).is_empty()
		assert_bool(run.bots[1].gone).override_failure_message(String(reason)).is_false()
		assert_bool(run._may_play()).override_failure_message("it waits to join again").is_false()
		assert_int(run.bots[0].step_index).override_failure_message("bot 1 acted").is_equal(0)
		run.clock_usec += NetPlay.ROOM_RETRY_USEC
		run.play_frame(1)
		assert_object(run.clients[2]).override_failure_message("joined again").is_not_same(first)
		assert_array(run.failures).is_empty()
		# Lost for good, its line names the join before it too.
		run.clients[2].end_reason = NetTransport.JOIN_UNREACHABLE
		run.play_frame(2)
		assert_array(run.failures).has_size(1)
		var line := run.failures[0] if not run.failures.is_empty() else ""
		assert_str(line).contains("(host_unreachable); earlier joins ended %s" % reason)
		run.close()


func test_a_join_retried_max_joins_times_fails_naming_every_reason() -> void:
	var run := UnhostedChaos.new()
	run.join_without_host()
	for i in ChaosRun.MAX_JOINS - 1:
		run.clients[2].end_reason = NetTransport.JOIN_SERVICE_UNREACHABLE
		run.play_frame(2 * i)
		run.clock_usec += NetPlay.ROOM_RETRY_USEC
		run.play_frame(2 * i + 1)
	assert_array(run.failures).is_empty()
	var last: BotClient = run.clients[2]
	last.end_reason = NetTransport.JOIN_SERVICE_UNREACHABLE
	run.play_frame(10)
	assert_array(run.failures).has_size(1)
	var line := run.failures[0] if not run.failures.is_empty() else ""
	assert_str(line).contains(
		"(service_unreachable); earlier joins ended service_unreachable, service_unreachable"
	)
	run.clock_usec += NetPlay.ROOM_RETRY_USEC
	run.play_frame(11)
	assert_object(run.clients[2]).override_failure_message("joined a 4th time").is_same(last)
	run.close()
