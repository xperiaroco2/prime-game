extends GdUnitTestSuite
## The bots' synthetic voice (tests/harness/bots/bot_voice.gd, ARCHITECTURE §4.6, the M5 ADR §5):
## one frame per 20 ms of the runner's clock, 30 to 60 B with the peer id and the counter first, in
## talk spurts by default (a pattern per bot) or continuously (BotScenario.voice); and two bots
## talking through the network: every frame relayed unchanged, the seqs running on across silence.

const BASE_MODE := "res://content/modes/base_mode.tres"
const SPURTS := BotScenario.Voice.SPURTS
const CONTINUOUS := BotScenario.Voice.CONTINUOUS
## Frames a second: one per 20 ms (E38).
const PER_SECOND := 50
## Host ticks a second (Ticks.RATE): a silence of 0.3 s or more leaves 5 ticks or more unheard.
const SILENT_TICKS := 5


func test_one_frame_per_20_ms_of_the_clock() -> void:
	assert_int(BotVoice.frame_at(0)).is_equal(0)
	assert_int(BotVoice.frame_at(19_999)).is_equal(0)
	assert_int(BotVoice.frame_at(20_000)).is_equal(1)
	assert_int(BotVoice.frame_at(1_000_000)).is_equal(PER_SECOND)
	# The clock of the one-process runner moves 16 667 us a frame: at most one voice frame a step.
	var sent := 0
	var last := BotVoice.frame_at(BotsRunner.START_USEC)
	for step in 60:
		var now := BotVoice.frame_at(BotsRunner.START_USEC + (step + 1) * BotsRunner.FRAME_USEC)
		var due := BotVoice.frames_due(1, last, now, CONTINUOUS)
		assert_int(due.size()).is_less_equal(1)
		sent += due.size()
		last = now
	assert_int(sent).is_equal(PER_SECOND)


func test_continuously_every_frame_and_after_a_hitch_only_the_newest_five() -> void:
	assert_array(BotVoice.frames_due(3, 99, 104, CONTINUOUS)).is_equal([100, 101, 102, 103, 104])
	assert_array(BotVoice.frames_due(3, 104, 104, CONTINUOUS)).is_empty()
	assert_array(BotVoice.frames_due(3, 0, 1000, CONTINUOUS)).is_equal([996, 997, 998, 999, 1000])


func test_spurts_alternate_per_bot_with_lengths_of_their_own() -> void:
	var patterns: Array[String] = []
	for bot in range(1, 7):
		var runs := _runs(bot, 0, 20 * PER_SECOND)
		var spurt := BotVoice.SPURT_FRAMES + BotVoice.SPURT_STEP * (bot % 4)
		var silence := BotVoice.SILENCE_FRAMES + BotVoice.SILENCE_STEP * (bot % 3)
		# Whole runs only: the first and the last may be cut by the window.
		var talking: Array[int] = []
		var quiet: Array[int] = []
		for i in range(1, runs.size() - 1):
			if runs[i].x == 1:
				talking.append(runs[i].y)
			else:
				quiet.append(runs[i].y)
		assert_int(talking.size()).is_greater_equal(5)
		assert_int(quiet.size()).is_greater_equal(5)
		for length: int in talking:
			assert_int(length).override_failure_message("bot %d" % bot).is_equal(spurt)
		for length: int in quiet:
			assert_int(length).override_failure_message("bot %d" % bot).is_equal(silence)
		# Each silence is longer than two host ticks (50 ms each), so a listener sees a new spurt.
		assert_int(silence * BotVoice.FRAME_USEC).is_greater(2 * 50_000)
		patterns.append(str(runs))
	# No two bots of the six start and stop alike.
	for i in patterns.size():
		for j in range(i + 1, patterns.size()):
			(
				assert_str(patterns[i])
				. override_failure_message("bots %d, %d" % [i + 1, j + 1])
				. is_not_equal(patterns[j])
			)


func test_a_frame_is_30_to_60_bytes_with_the_peer_and_counter_first() -> void:
	var sizes: Dictionary[int, bool] = {}
	for counter in 200:
		var frame := LeakCheck.voice_frame(7, counter)
		assert_int(frame.size()).is_between(LeakCheck.MIN_FRAME_BYTES, LeakCheck.MAX_FRAME_BYTES)
		assert_int(frame.decode_u32(0)).is_equal(7)
		assert_int(frame.decode_u32(4)).is_equal(counter)
		assert_str(LeakCheck.frame_problem(7, frame)).is_empty()
		sizes[frame.size()] = true
	assert_int(LeakCheck.MIN_FRAME_BYTES).is_equal(30)
	assert_int(LeakCheck.MAX_FRAME_BYTES).is_equal(60)
	assert_int(sizes.size()).is_equal(31)
	assert_str(LeakCheck.frame_problem(8, LeakCheck.voice_frame(7, 3))).contains(
		"relayed as peer 8"
	)


func test_two_bots_in_the_lobby_hear_every_frame_of_each_other_s_spurts() -> void:
	var runner := BotsRunner.play(_scenario(SPURTS, 10.0))
	assert_array(Array(runner.failures)).is_empty()
	for listener: int in [1, 2]:
		var speaker := 3 - listener
		var heard := _heard(runner, listener, speaker)
		# About 10 s at 50 a second, in spurts (bots 1 and 2 talk 1.1 and 1.4 s, silent 0.6 and
		# 0.9 s): every frame sent in the lobby, its counters without a gap, and silences.
		var counters: Array[int] = heard["counters"]
		assert_int(counters.size()).is_greater(PER_SECOND * 3)
		for i in range(1, counters.size()):
			assert_int(counters[i]).is_equal(counters[i - 1] + 1)
		assert_int(heard["gaps"] as int).is_greater_equal(3)
		assert_int(heard["sizes"] as int).is_greater(20)


func test_continuous_bots_are_heard_on_every_tick() -> void:
	var runner := BotsRunner.play(_scenario(CONTINUOUS, 4.0))
	assert_array(Array(runner.failures)).is_empty()
	var heard := _heard(runner, 2, 1)
	var counters: Array[int] = heard["counters"]
	var ticks: Array[int] = heard["ticks"]
	assert_int(heard["gaps"] as int).is_equal(0)
	var first_tick: int = ticks.front()
	var last_tick: int = ticks.back()
	assert_int(last_tick - first_tick).is_greater(Ticks.RATE * 3)
	# 50 frames a second, 2.5 a host tick, every one relayed.
	var seconds := float(last_tick - first_tick + 1) / Ticks.RATE
	assert_float(counters.size() / seconds).is_between(PER_SECOND - 3.0, PER_SECOND + 3.0)
	var first_counter: int = counters.front()
	var last_counter: int = counters.back()
	assert_int(last_counter - first_counter + 1).is_equal(counters.size())


## Bot `bot`'s frames from `first` to `last` as runs: Vector2i(1 talking or 0 silent, length).
func _runs(bot: int, first: int, last: int) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	for frame in range(first, last):
		var on := 1 if BotVoice.talks(bot, frame, SPURTS) else 0
		var tail: Vector2i = runs.back() if not runs.is_empty() else Vector2i(-1, 0)
		if tail.x == on:
			runs[runs.size() - 1] = Vector2i(on, tail.y + 1)
		else:
			runs.append(Vector2i(on, 1))
	return runs


## What bot `listener` decoded of bot `speaker`: the frames' counters and ticks in order, the gaps
## of at least SILENT_TICKS ticks between two heard ticks, and how many frame lengths it saw.
func _heard(runner: BotsRunner, listener: int, speaker: int) -> Dictionary:
	var view := runner.clients[listener].view
	var peer := runner.peers.peer_of(speaker)
	var ticks: Array[int] = []
	for key: Vector2i in view.voice:
		if key.x == peer:
			ticks.append(key.y)
	ticks.sort()
	var counters: Array[int] = []
	var sizes: Dictionary[int, bool] = {}
	var gaps := 0
	for i in ticks.size():
		if i > 0 and ticks[i] - ticks[i - 1] > SILENT_TICKS:
			gaps += 1
		for frame: PackedByteArray in view.frames(peer, ticks[i]):
			counters.append(frame.decode_u32(4))
			sizes[frame.size()] = true
	return {"counters": counters, "ticks": ticks, "gaps": gaps, "sizes": sizes.size()}


## Two bots that stay in the lobby (2 m apart, within its 8 m) for `seconds`, talking by `voice`.
func _scenario(voice: BotScenario.Voice, seconds: float) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(BASE_MODE) as GameMode
	scenario.bots = 2
	scenario.session_seed = 215_000_000_001
	scenario.expected_ends = [BotScenario.NONE]
	scenario.time_limit_s = seconds + 10.0
	scenario.voice = voice
	var made: Array[BotScript] = []
	for bot in 2:
		var wait := StepWait.new()
		wait.seconds = seconds
		var script := BotScript.new()
		script.steps.append(wait)
		made.append(script)
	scenario.scripts = made
	return scenario
