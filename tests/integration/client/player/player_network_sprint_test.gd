extends GdUnitTestSuite
## The end of a sprint on the network (#155, ARCHITECTURE §7.1): the real PlayerController of a
## joined Game claims through its ClientSession over a LoopbackHub to the host's HostSession and
## its MovementRule. A human who lets go of sprint (or of the movement keys) at any physics step of
## a claim's tick, or who sprints until stamina runs out, gets no Correction: the session latches
## the claim's flags over its tick, and the controller's PredictedStamina settles the same ticks as
## the host's ledger (claim by claim) and follows SelfStatus without going back to a number the
## claims in flight already spent. The same runs with the host's messages and the claims held back
## a few physics frames each way, as over a real network; before #155 the client was corrected
## there when its stamina ran out. With jitter on top, the LATEST lane merges two claims that land
## in one poll, and the host's "sprint's last tick" covers the merged claim that ends a sprint:
## without it the jitter test gets Corrections (#155 kept it, the engineer to decide).
##
## The joined player runs in a circle away from the host's player (no push allowance applies):
## a walk of 1.5 s along -Z from its lobby spot, then turning left every frame.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## Radians the player turns per physics frame while it runs in a circle: about 4 m across at the
## sprint speed of FixtureModes, out of the host's player's push reach.
const TURN := 0.03
## Physics frames each way the delayed tests hold every packet back (about 67 ms each way).
const DELAY_FRAMES := 4
## The jitter test: every packet held back 1 physics frame and up to this many more, in order, so
## two claims often land in one poll.
const JITTER_FRAMES := 8
## Times the jitter test lets stamina run out and sprints again while sprint stays held.
const CYCLES := 3

var _pair: NetPair


func before_test() -> void:
	_pair = NetPair.new()
	add_child(_pair)


func after_test() -> void:
	_pair.free()


func test_letting_go_of_sprint_at_any_step_of_a_tick_is_never_corrected() -> void:
	await _lets_go_at_every_step()


func test_letting_go_of_sprint_with_delay_is_never_corrected() -> void:
	_pair.delay_frames = DELAY_FRAMES
	await _lets_go_at_every_step()


func test_sprinting_until_stamina_runs_out_is_never_corrected() -> void:
	await _sprint_until_empty()


func test_sprinting_until_stamina_runs_out_with_delay_is_never_corrected() -> void:
	_pair.delay_frames = DELAY_FRAMES
	await _sprint_until_empty()


func test_holding_sprint_through_running_out_with_jitter_is_never_corrected() -> void:
	_pair.delay_frames = 1
	_pair.jitter_frames = JITTER_FRAMES
	await _hold_sprint_through_cycles()


## Holds sprint and the movement keys until stamina has run out and come back to a sprint
## CYCLES times: the resumed sprint starts no earlier than the host's ledger allows.
func _hold_sprint_through_cycles() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	var session := _pair.client.client()
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
	player.sprint_held = false
	player.move_input = Vector2.ZERO
	await _pair.frames(30)
	assert_int(session.corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	await _pair.stop()


## Six sprints that let go of sprint and keep walking, then six that let go of every key, each
## one physics frame longer than the one before, so the release falls on every step of a claim's
## three twice.
func _lets_go_at_every_step() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	var session := _pair.client.client()
	await _walk_away(player)
	var sprinted := 0
	for release_all: bool in [false, true]:
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
	player.move_input = Vector2.ZERO
	await _pair.frames(30)
	# Every sprint ran at sprint speed on most of its frames: stamina never ran out here.
	assert_int(sprinted).is_greater(200)
	assert_int(session.corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	await _pair.stop()


## Sprints in a circle until the predicted stamina runs out, holds sprint a second longer (walking
## at 0 stamina), then lets go.
func _sprint_until_empty() -> void:
	assert_bool(await _pair.start()).is_true()
	var player := _pair.client.player()
	var session := _pair.client.client()
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
	player.sprint_held = false
	player.move_input = Vector2.ZERO
	await _pair.frames(30)
	assert_int(session.corrections).is_equal(0)
	assert_int(_pair.host.client().corrections).is_equal(0)
	await _pair.stop()


## Walks 1.5 s along -Z from the lobby spot, away from the host's player.
func _walk_away(player: PlayerController) -> void:
	player.move_input = Vector2(0.0, 1.0)
	await _pair.frames(90)


## One physics frame of running in a circle.
func _run(player: PlayerController) -> void:
	player.look(TURN, 0.0)
	await _pair.frames(1)
