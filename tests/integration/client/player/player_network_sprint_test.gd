extends GdUnitTestSuite
## The end of a sprint on the network (#155, ARCHITECTURE §7.1): the real PlayerController of a
## joined Game claims through its ClientSession over a LoopbackHub to the host's HostSession and
## its MovementRule, which grants no tick of sprint beyond what a claim's masks and the stamina
## pay for. A human who lets go of sprint (or of every key) at any physics step of a claim's
## tick, who sprints until stamina runs out, or who holds sprint through running out and sprints
## again once it came back, gets no Correction: the session latches a claim's flags over its tick
## and repeats them per tick in its masks, and the controller's PredictedStamina settles the same
## ticks as the host's ledger and follows each SelfStatus from the claim it names. The same runs
## with every packet held back a few physics frames each way, as over a real network, and with
## jitter on top (each packet 1 to 9 frames, in order), where the LATEST lane merges claims that
## land in one poll: each jitter test checks that the host's transport merged some. One more holds
## the joiner's packets for three claims while it lets go of sprint, so the claim of the walk
## after the release reaches the host merged with the sprint's last ticks.
##
## The joined player runs in a circle away from the host's player (no push allowance applies):
## a walk of 1.5 s along -Z from its lobby spot, then turning left every frame.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## Radians the player turns per physics frame while it runs in a circle: about 4 m across at the
## sprint speed of FixtureModes, out of the host's player's push reach.
const TURN := 0.03
## Physics frames each way the delayed tests hold every packet back (about 67 ms each way).
const DELAY_FRAMES := 4
## The jitter tests: every packet held back 1 physics frame and up to this many more, in order, so
## two claims or more often land in one poll.
const JITTER_FRAMES := 8
## Times the cycle tests let stamina run out and sprint again while sprint stays held.
const CYCLES := 3
## Physics frames the merge test holds the joiner's packets: three claims at 20 Hz. It lets go of
## sprint RELEASE_FRAME frames in, so the newest held claim walks and the older ones sprinted.
const HOLD_FRAMES := 9
const RELEASE_FRAME := 3

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_letting_go_of_sprint_at_any_step_of_a_tick_is_never_corrected() -> void:
	await _lets_go_at_every_step([false, true])


func test_letting_go_of_sprint_with_delay_is_never_corrected() -> void:
	_pair.delay_frames = DELAY_FRAMES
	await _lets_go_at_every_step([false, true])


func test_letting_go_of_sprint_with_jitter_is_never_corrected() -> void:
	_jitter()
	await _lets_go_at_every_step([false])


func test_letting_go_of_every_key_with_jitter_is_never_corrected() -> void:
	_jitter()
	await _lets_go_at_every_step([true])


func test_sprinting_until_stamina_runs_out_is_never_corrected() -> void:
	await _sprint_until_empty()


func test_sprinting_until_stamina_runs_out_with_delay_is_never_corrected() -> void:
	_pair.delay_frames = DELAY_FRAMES
	await _sprint_until_empty()


func test_sprinting_until_stamina_runs_out_with_jitter_is_never_corrected() -> void:
	_jitter()
	await _sprint_until_empty()


func test_holding_sprint_through_running_out_with_jitter_is_never_corrected() -> void:
	_jitter()
	await _hold_sprint_through_cycles()


func test_three_claims_merged_at_a_sprints_end_are_never_corrected() -> void:
	# No jitter here: a held packet arrives exactly when the hold ends, so the three merge.
	_pair.delay_frames = 1
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	await _walk_away(player)
	for offset: int in 3:
		player.move_input = Vector2(0.0, 1.0)
		player.sprint_held = true
		for i: int in 30 + offset:
			await _run(player)
		# The claims of the sprint's last ticks, of the release and of the walk after it reach the
		# host in one poll, merged into the walk's.
		var merged := _pair.host_transport.latest_superseded
		_pair.hold_at_host(HOLD_FRAMES)
		for i: int in RELEASE_FRAME:
			await _run(player)
		player.sprint_held = false
		for i: int in 30 + HOLD_FRAMES - RELEASE_FRAME:
			await _run(player)
		assert_int(_pair.host_transport.latest_superseded - merged).is_greater_equal(2)
	await _stop_and_assert_no_correction(player)


## Every packet held back 1 physics frame and up to JITTER_FRAMES more, in order.
func _jitter() -> void:
	_pair.delay_frames = 1
	_pair.jitter_frames = JITTER_FRAMES


## Holds sprint and the movement keys until stamina has run out and come back to a sprint
## CYCLES times: the resumed sprint starts no earlier than the host's ledger allows.
func _hold_sprint_through_cycles() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	await _walk_away(player)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var resumed := 0
	var was_sprinting := false
	for i: int in 1500:
		await _run(player)
		if player.is_sprinting() and not was_sprinting and i > 10:
			resumed += 1
		was_sprinting = player.is_sprinting()
		if resumed >= CYCLES and not was_sprinting:
			break
	assert_int(resumed).is_greater_equal(CYCLES)
	await _stop_and_assert_no_correction(player)


## For each of `releases`, six sprints that let go of sprint and walk on (false) or of every key
## (true), each one physics frame longer than the one before, so the release falls on every step
## of a claim's three twice.
func _lets_go_at_every_step(releases: Array[bool]) -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	await _walk_away(player)
	var sprinted := 0
	for release_all: bool in releases:
		for offset: int in 6:
			player.move_input = Vector2(0.0, 1.0)
			player.sprint_held = true
			for i: int in 20 + offset:
				await _run(player)
				sprinted += 1 if player.is_sprinting() else 0
			player.sprint_held = false
			if release_all:
				player.move_input = Vector2.ZERO
			for i: int in 25:
				await _run(player)
	# Every sprint ran at sprint speed on most of its frames: stamina never ran out here.
	assert_int(sprinted).is_greater(100 * releases.size())
	await _stop_and_assert_no_correction(player)


## Sprints in a circle until the predicted stamina runs out, holds sprint a second longer (walking
## at 0 stamina), then lets go.
func _sprint_until_empty() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	await _walk_away(player)
	player.move_input = Vector2(0.0, 1.0)
	player.sprint_held = true
	var ran_out := false
	for i: int in 900:
		await _run(player)
		if i > 10 and not player.is_sprinting():
			ran_out = true
			break
	assert_bool(ran_out).is_true()
	assert_float(player.stamina.get_stamina()).is_less(1.0)
	for i: int in 60:
		await _run(player)
	assert_bool(player.is_sprinting()).is_false()
	await _stop_and_assert_no_correction(player)


## Lets go of every key, waits for the last claims, and checks that neither player got a
## Correction; with jitter, also that the host's transport merged claims on the LATEST lane.
func _stop_and_assert_no_correction(player: PlayerController) -> void:
	player.sprint_held = false
	player.move_input = Vector2.ZERO
	await _pair.frames(30)
	assert_int(_pair.client.client().corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	if _pair.jitter_frames > 0:
		assert_int(_pair.host_transport.latest_superseded).is_greater(0)
	await _pair.stop()


## Walks 1.5 s along -Z from the lobby spot, away from the host's player.
func _walk_away(player: PlayerController) -> void:
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(90)


## One physics frame of running in a circle.
func _run(player: PlayerController) -> void:
	player.look(TURN, 0.0)
	await _pair.frames(1)
