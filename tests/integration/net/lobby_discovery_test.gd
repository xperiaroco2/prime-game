extends GdUnitTestSuite
## The lobbies nearby over real UDP on this machine (#1316, LobbyFinder and LobbyResponder,
## ARCHITECTURE §4.9): a responder on a test port answers a finder asking 127.0.0.1 there. The
## finder and the responder run on a stepped clock (the queries' timing, the answers' gap, the
## forgetting); only the datagrams' delivery waits for frames. The finder lists the lobby once with
## the address it came from and the round trip, keeps it while heard, forgets it gone quiet, lists
## none while the responder stays silent or speaks another protocol, finds one that opens after it
## started asking, and keeps a flood of hosts to MOST_LOBBIES.

const PORT := 47316
## Frames a datagram may take to arrive (no wall clock in the logic: only the OS's delivery).
const MAX_FRAMES := 120

var _responder: LobbyResponder
var _finder: LobbyFinder
var _answer: LobbyBeacon.Answer
var _now := 100000
## How many times the responder asked for its answer.
var _asked := 0


func before_test() -> void:
	_now = 100000
	_asked = 0
	_responder = LobbyResponder.new()
	_responder.port = PORT
	_responder.bind_address = "127.0.0.1"
	_responder.now_ms = func() -> int: return _now
	_finder = LobbyFinder.new()
	_finder.port = PORT
	_finder.targets = PackedStringArray(["127.0.0.1"])
	_finder.now_ms = func() -> int: return _now
	_answer = LobbyBeacon.Answer.new()
	_answer.protocol = WireSchema.VERSION
	_answer.port = 24600
	_answer.players = 3
	_answer.most = 10
	_answer.host_name = "Olena"


func after_test() -> void:
	_responder.stop()
	_finder.stop()


func _describe() -> LobbyBeacon.Answer:
	_asked += 1
	if _answer == null:
		return null
	return LobbyBeacon.read_answer(LobbyBeacon.answer(_answer))


## Polls both until `done`, at most MAX_FRAMES frames (the clock stands still meanwhile).
func _until(done: Callable) -> bool:
	for i: int in MAX_FRAMES:
		_responder.poll(_describe)
		_finder.poll()
		if done.call():
			return true
		await get_tree().process_frame
	return done.call()


## The next query is due: the clock moves one QUERY_MS on.
func _next_query() -> void:
	_now += LobbyFinder.QUERY_MS


func test_a_finder_lists_the_lobby_that_answers_and_keeps_it_while_heard() -> void:
	assert_bool(_responder.start()).is_true()
	assert_bool(_finder.start()).is_true()
	assert_bool(await _until(func() -> bool: return _finder.lobbies().size() == 1)).is_true()
	var found := _finder.lobbies()[0]
	assert_str(found.address).is_equal("127.0.0.1")
	assert_int(found.answer.host).is_equal(_responder.host_number)
	assert_int(found.answer.port).is_equal(24600)
	assert_int(found.answer.players).is_equal(3)
	assert_str(found.answer.host_name).is_equal("Olena")
	assert_int(found.ping_ms).is_equal(0)
	# Heard again at each query: still one lobby, kept past FORGET_MS from its first answer.
	for step: int in 4:
		_next_query()
		var heard := _now
		assert_bool(await _until(func() -> bool: return found.heard_ms == heard)).is_true()
	assert_int(_now - 100000).is_greater(LobbyFinder.FORGET_MS)
	assert_int(_finder.lobbies().size()).is_equal(1)


func test_a_silent_host_or_another_build_is_not_listed() -> void:
	assert_bool(_responder.start()).is_true()
	assert_bool(_finder.start()).is_true()
	_answer = null
	assert_bool(await _until(func() -> bool: return _asked > 0)).is_true()
	assert_bool(_finder.lobbies().is_empty()).is_true()
	_answer = LobbyBeacon.Answer.new()
	_answer.protocol = WireSchema.VERSION + 1
	_answer.most = 10
	_next_query()
	var asked := _asked
	var refused := _finder.rejected
	# The other build's answer arrived and was refused, not merely never sent.
	assert_bool(await _until(func() -> bool: return _finder.rejected > refused)).is_true()
	assert_int(_asked).is_greater(asked)
	assert_bool(_finder.lobbies().is_empty()).is_true()


func test_a_lobby_gone_quiet_is_forgotten() -> void:
	assert_bool(_responder.start()).is_true()
	assert_bool(_finder.start()).is_true()
	assert_bool(await _until(func() -> bool: return _finder.lobbies().size() == 1)).is_true()
	_responder.stop()
	_now += LobbyFinder.FORGET_MS + 1
	_finder.poll()
	assert_bool(_finder.lobbies().is_empty()).is_true()


func test_a_lobby_that_opens_after_the_finder_started_asking_is_found() -> void:
	# The finder's queries met a closed port first (on Windows an ICMP "unreachable" can break the
	# next read of a UDP socket): the lobby opening later is still found.
	assert_bool(_finder.start()).is_true()
	for step: int in 3:
		_next_query()
		for frame: int in 5:
			_finder.poll()
			await get_tree().process_frame
	assert_bool(_responder.start()).is_true()
	_next_query()
	assert_bool(await _until(func() -> bool: return _finder.lobbies().size() == 1)).is_true()


func test_one_asker_is_answered_once_per_gap() -> void:
	assert_bool(_responder.start()).is_true()
	assert_bool(_finder.start()).is_true()
	assert_bool(await _until(func() -> bool: return _asked == 1)).is_true()
	# A second query within ANSWER_GAP_MS (the clock still) is refused; past it, answered.
	_finder.call(&"_ask", _now)
	var refused := _responder.rejected
	assert_bool(await _until(func() -> bool: return _responder.rejected > refused)).is_true()
	assert_int(_asked).is_equal(1)
	_now += LobbyResponder.ANSWER_GAP_MS
	_finder.call(&"_ask", _now)
	assert_bool(await _until(func() -> bool: return _asked == 2)).is_true()


func test_only_nearby_askers_are_answered() -> void:
	for nearby: String in ["127.0.0.1", "10.1.2.3", "172.16.0.9", "172.31.255.1", "192.168.1.20"]:
		assert_bool(LobbyResponder.is_nearby(nearby)).override_failure_message(nearby).is_true()
	assert_bool(LobbyResponder.is_nearby("169.254.3.4")).is_true()
	for far: String in ["8.8.8.8", "172.32.0.1", "192.169.1.1", "::1", "fe80::1", "", "nonsense"]:
		assert_bool(LobbyResponder.is_nearby(far)).override_failure_message(far).is_false()
