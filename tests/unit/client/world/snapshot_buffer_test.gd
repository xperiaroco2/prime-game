extends GdUnitTestSuite
## SnapshotBuffer (ARCHITECTURE §4.7 and §7, the M4 ADR's E23) on a simulated network: the host
## sends a snapshot every tick (20 Hz) of peer 2 walking along +X at WALK m/s; the client draws at
## 60 Hz. Under jitter, loss and a freeze's burst it draws no frame past the snapshots it has
## once the window has seen the jitter, interpolates on the line the player
## walked, holds still past the newest snapshot, snaps placements, and keeps every facing usable.
## A latency beyond any the window has seen can starve a frame under random jitter (at most 1 %).

const PEER := 2
const WALK := 4.5
const USEC_PER_TICK := 50000
const FRAME_USEC := 16667
## The first 2 s fill the window; frames before it are not judged.
const WARM_UP_USEC := 2000000

var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 143


func test_steady_arrivals_draw_two_ticks_behind_on_the_line_walked() -> void:
	var run := _run(4.0, func(_tick: int) -> int: return 30000)
	assert_float(run.buffer.delay_ticks()).is_equal_approx(SnapshotBuffer.MIN_DELAY_TICKS, 1e-6)
	assert_int(run.starved).is_equal(0)
	assert_float(run.off_line).is_less(0.001)
	# The estimate is the tick of the snapshot that arrives now: 30 ms of latency is 0.6 tick.
	var now := run.now
	assert_float(run.buffer.estimated_tick(now)).is_equal_approx(now / 50000.0 - 0.6, 0.01)


func test_jitter_raises_the_delay_and_no_frame_starves() -> void:
	# 0 to 100 ms of jitter, the M1 spike's case that starved 25 % of frames at a fixed 100 ms.
	var jittery := func(_tick: int) -> int: return 20000 + _rng.randi_range(0, 100000)
	var run := _run(10.0, jittery)
	# A latency beyond any the window has seen yet can still starve a frame (it then holds): at
	# most 1 % of them, against the spike's 25 %.
	assert_float(float(run.starved)).is_less_equal(run.frames_judged * 0.01)
	assert_float(run.off_line).is_less(0.001)
	assert_float(run.buffer.delay_ticks()).is_between(2.5, SnapshotBuffer.MAX_DELAY_TICKS)
	# A fixed 100 ms would have starved a tenth of the same frames or more.
	assert_float(float(run.starved_at_fixed_delay)).is_greater_equal(run.frames_judged * 0.1)


func test_lost_snapshots_are_bridged_on_the_line() -> void:
	# A lost snapshot never arrives; 30 % of them here.
	var lossy := func(_tick: int) -> int: return 30000 if _rng.randf() >= 0.3 else -1
	var run := _run(6.0, lossy)
	assert_float(run.off_line).is_less(0.001)
	assert_int(run.frames_judged).is_greater(200)


func test_a_freeze_holds_still_then_its_burst_neither_rewinds_nor_extrapolates() -> void:
	# The client stalls for 1 s from 3 s: the snapshots of that second arrive in one burst at 4 s.
	var stalled := func(tick: int) -> int:
		var sent := tick * USEC_PER_TICK
		return 4000000 - sent + 1000 if sent >= 3000000 and sent < 4000000 else 30000
	var run := _run(9.0, stalled)
	assert_bool(run.rewound).is_false()
	assert_float(run.extrapolated).is_less(0.001)
	assert_float(run.off_line).is_less(0.001)
	assert_float(run.max_delay).is_less_equal(SnapshotBuffer.MAX_DELAY_TICKS)
	assert_float(run.max_delay).is_greater(SnapshotBuffer.MIN_DELAY_TICKS)
	# The burst left the window 2 s later, and the delay shrank back.
	assert_float(run.buffer.delay_ticks()).is_equal_approx(SnapshotBuffer.MIN_DELAY_TICKS, 1e-6)


func test_the_estimate_follows_a_lasting_rise_of_the_latency() -> void:
	# From 4 s on every snapshot takes 200 ms instead of 20 ms: an all-time maximum of the offsets
	# would keep drawing 180 ms ahead of what has arrived, for good.
	var rising := func(tick: int) -> int: return 20000 if tick * USEC_PER_TICK < 4000000 else 200000
	var run := _run(10.0, rising, 7000000)
	assert_int(run.starved).is_equal(0)
	assert_float(run.buffer.delay_ticks()).is_equal_approx(SnapshotBuffer.MIN_DELAY_TICKS, 1e-6)


func test_past_the_newest_snapshot_a_player_holds_with_the_newest_velocity() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.add(10, {PEER: _avatar(Vector3(1, 0, 0), Vector3.RIGHT)}, 500000)
	var moving := _avatar(Vector3(2, 0, 0), Vector3.RIGHT)
	moving["velocity"] = Vector3(4.5, 0, 0)
	buffer.add(11, {PEER: moving}, 550000)
	var pose := buffer.pose_of(PEER, 15.0)
	assert_vector(pose.position).is_equal(Vector3(2, 0, 0))
	assert_vector(pose.velocity).is_equal(Vector3(4.5, 0, 0))
	assert_vector(buffer.pose_of(PEER, 10.5).position).is_equal_approx(
		Vector3(1.5, 0, 0), Vector3.ONE * 1e-5
	)
	assert_object(buffer.pose_of(9, 10.5)).is_null()


func test_a_placement_snaps() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.add(10, {PEER: _avatar(Vector3.ZERO, Vector3.FORWARD)}, 500000)
	buffer.add(11, {PEER: _avatar(Vector3(40, 0, 0), Vector3.FORWARD)}, 550000)
	# Farther than anyone moves in a tick: drawn where it was, then where it went, never between.
	assert_vector(buffer.pose_of(PEER, 10.9).position).is_equal(Vector3.ZERO)
	assert_vector(buffer.pose_of(PEER, 11.0).position).is_equal(Vector3(40, 0, 0))
	# A placement nearby is told by the event: 0.8 m in a tick would otherwise slide. The event's
	# tick is an estimate, so nothing within a tick of it is blended: it holds, then walks on.
	buffer.add(12, {PEER: _avatar(Vector3(40.8, 0, 0), Vector3.FORWARD)}, 600000)
	buffer.snap(PEER, 12)
	assert_vector(buffer.pose_of(PEER, 11.5).position).is_equal(Vector3(40, 0, 0))
	buffer.add(13, {PEER: _avatar(Vector3(41.0, 0, 0), Vector3.FORWARD)}, 650000)
	buffer.add(14, {PEER: _avatar(Vector3(41.2, 0, 0), Vector3.FORWARD)}, 700000)
	assert_vector(buffer.pose_of(PEER, 12.5).position).is_equal(Vector3(40.8, 0, 0))
	assert_vector(buffer.pose_of(PEER, 13.5).position).is_equal_approx(
		Vector3(41.1, 0, 0), Vector3.ONE * 1e-5
	)
	# The estimate may also be a tick early: the pair before the placement is not blended either.
	var early := SnapshotBuffer.new()
	early.add(1, {PEER: _avatar(Vector3.ZERO, Vector3.FORWARD)}, 50000)
	early.add(2, {PEER: _avatar(Vector3(0.8, 0, 0), Vector3.FORWARD)}, 100000)
	early.snap(PEER, 1)
	assert_vector(early.pose_of(PEER, 1.5).position).is_equal(Vector3.ZERO)


func test_a_snapshot_at_or_below_the_floor_is_not_kept_but_counts_for_the_jitter() -> void:
	# #251: End -> Lobby clears the buffer at the host tick estimated at the change (here 13). The
	# round's snapshot of tick 12, sent before the change, arrives after it: newer than every one
	# held, it would draw the player at its round spot in the lobby for the interpolation delay.
	var buffer := SnapshotBuffer.new()
	var round_spot := _avatar(Vector3(2, 0, 0), Vector3.FORWARD)
	var lobby_spot := _avatar(Vector3(-4, 0, 0), Vector3.FORWARD)
	for tick: int in range(8, 12):
		buffer.add(tick, {PEER: round_spot}, tick * USEC_PER_TICK)
	assert_float(buffer.jitter_ticks()).is_equal_approx(0.0, 1e-6)
	buffer.clear(13)
	buffer.add(12, {PEER: round_spot}, 14 * USEC_PER_TICK)
	buffer.add(13, {PEER: lobby_spot}, 14 * USEC_PER_TICK)
	assert_int(buffer.newest_tick()).is_equal(-1)
	assert_object(buffer.pose_of(PEER, 12.0)).is_null()
	# Both arrivals still count: the late one widened the jitter.
	assert_float(buffer.jitter_ticks()).is_equal_approx(2.0, 1e-6)
	buffer.add(14, {PEER: lobby_spot}, 15 * USEC_PER_TICK)
	assert_int(buffer.newest_tick()).is_equal(14)
	assert_vector(buffer.pose_of(PEER, 14.0).position).is_equal(Vector3(-4, 0, 0))
	# A clear with no floor given keeps the newest held as one, and a later match (the host's tick
	# runs on) adds again.
	buffer.clear()
	buffer.add(14, {PEER: round_spot}, 16 * USEC_PER_TICK)
	assert_int(buffer.newest_tick()).is_equal(-1)
	buffer.clear(300)
	buffer.add(301, {PEER: lobby_spot}, 301 * USEC_PER_TICK)
	assert_int(buffer.newest_tick()).is_equal(301)


func test_degenerate_facings_keep_a_unit_facing_and_the_last_turn() -> void:
	var buffer := SnapshotBuffer.new()
	var facings: Array[Vector3] = [
		Vector3(1, 0, 0),
		Vector3(0, -1, 0),
		Vector3.ZERO,
		Vector3(NAN, 0, 0),
		Vector3(0, 1, 0),
		Vector3(-1, 0, 0),
		Vector3(1, 0, 0),
	]
	for i: int in facings.size():
		buffer.add(10 + i, {PEER: _avatar(Vector3.ZERO, facings[i])}, 500000 + i * USEC_PER_TICK)
	# Looking along +X is a quarter turn to the right of -Z.
	var right := -PI / 2.0
	for step: int in 61:
		var pose := buffer.pose_of(PEER, 10.0 + step * 0.1)
		assert_bool(pose.facing.is_finite()).is_true()
		assert_float(pose.facing.length()).is_equal_approx(1.0, 1e-4)
		assert_bool(is_finite(pose.yaw) and is_finite(pose.pitch)).is_true()
		assert_float(absf(pose.pitch)).is_less_equal(SnapshotBuffer.MAX_PITCH + 1e-6)
	# Straight down: the turn it had, the head at the pitch limit.
	var down := buffer.pose_of(PEER, 11.0)
	assert_float(down.yaw).is_equal_approx(right, 1e-4)
	assert_float(down.pitch).is_equal_approx(-SnapshotBuffer.MAX_PITCH, 1e-4)
	# Zero and NaN keep the last usable facing and its angles.
	for at: float in [12.0, 13.0]:
		var kept := buffer.pose_of(PEER, at)
		assert_float(kept.pitch).is_equal_approx(-SnapshotBuffer.MAX_PITCH, 1e-4)
		assert_float(kept.yaw).is_equal_approx(right, 1e-4)
	# Halfway between opposite facings the blend is zero: still a usable facing.
	var between := buffer.pose_of(PEER, 15.5)
	assert_float(between.facing.length()).is_equal_approx(1.0, 1e-4)


func test_look_angles_guard_zero_vertical_and_non_finite_facings() -> void:
	var last := Vector2(0.5, 0.25)
	assert_vector(SnapshotBuffer.look_angles(Vector3.ZERO, last)).is_equal(last)
	assert_vector(SnapshotBuffer.look_angles(Vector3(INF, 0, 0), last)).is_equal(last)
	var up := SnapshotBuffer.look_angles(Vector3.UP, last)
	assert_float(up.x).is_equal(0.5)
	assert_float(up.y).is_equal_approx(SnapshotBuffer.MAX_PITCH, 1e-6)
	var ahead := SnapshotBuffer.look_angles(Vector3(0, 0, -2), last)
	assert_vector(ahead).is_equal_approx(Vector2.ZERO, Vector2.ONE * 1e-6)


func test_a_huge_but_finite_facing_still_gives_a_unit_facing() -> void:
	# A relayed (1e30, 0, 0) has a finite length whose square overflows: normalized() alone gives
	# zero (the netcode review of PR #154). Every pose keeps a unit facing and turns to +X.
	var buffer := SnapshotBuffer.new()
	var huge := Vector3(1e30, 0, 0)
	buffer.add(10, {PEER: _avatar(Vector3.ZERO, Vector3(0, 0, -1))}, 500000)
	buffer.add(11, {PEER: _avatar(Vector3.ZERO, huge)}, 500000 + USEC_PER_TICK)
	buffer.add(
		12, {PEER: _avatar(Vector3.ZERO, Vector3(-1e30, -1e30, 0))}, 500000 + 2 * USEC_PER_TICK
	)
	for at: float in [10.5, 11.0, 11.5, 12.0]:
		var pose := buffer.pose_of(PEER, at)
		assert_bool(pose.facing.is_normalized()).override_failure_message("at %s" % at).is_true()
	assert_float(buffer.pose_of(PEER, 11.0).yaw).is_equal_approx(-PI / 2.0, 1e-4)
	var angles := SnapshotBuffer.look_angles(huge, Vector2(0.5, 0.25))
	assert_vector(angles).is_equal_approx(Vector2(-PI / 2.0, 0.0), Vector2.ONE * 1e-4)
	assert_vector(SnapshotBuffer.unit_or(huge, Vector3.FORWARD)).is_equal(Vector3(1, 0, 0))
	assert_vector(SnapshotBuffer.unit_or(Vector3.ZERO, Vector3.BACK)).is_equal(Vector3.BACK)


## What one simulated run saw (frames from WARM_UP_USEC on, unless `judge_from` says later).
class Run:
	extends RefCounted
	var buffer := SnapshotBuffer.new()
	var now := 0
	var frames_judged := 0
	## Frames drawn past the newest snapshot that had arrived.
	var starved := 0
	## The same, had the delay been a fixed 100 ms.
	var starved_at_fixed_delay := 0
	## The furthest a drawn position was from the line walked, among frames not past the newest.
	var off_line := 0.0
	## The furthest a drawn position was ahead of the newest snapshot's.
	var extrapolated := 0.0
	var rewound := false
	var max_delay := 0.0


## Runs `seconds` of the host sending tick after tick, each arriving after `latency.call(tick)`
## microseconds (-1: lost), and the client drawing every frame.
func _run(seconds: float, latency: Callable, judge_from := WARM_UP_USEC) -> Run:
	var run := Run.new()
	var end := int(seconds * 1000000)
	var pending: Array[Vector2i] = []
	for tick: int in range(1, floori(float(end) / USEC_PER_TICK) + 1):
		var delay: int = latency.call(tick)
		if delay >= 0:
			pending.append(Vector2i(tick * USEC_PER_TICK + delay, tick))
	pending.sort()
	var next := 0
	var last_render := -INF
	run.now = FRAME_USEC
	while run.now <= end:
		while next < pending.size() and pending[next].x <= run.now:
			var tick := pending[next].y
			run.buffer.add(tick, {PEER: _walker(tick)}, pending[next].x)
			next += 1
		var render := run.buffer.render_tick(run.now)
		run.max_delay = maxf(run.max_delay, run.buffer.delay_ticks())
		if render < last_render:
			run.rewound = true
		last_render = render
		if run.now >= judge_from:
			_judge(run, render)
		run.now += FRAME_USEC
	return run


func _judge(run: Run, render: float) -> void:
	run.frames_judged += 1
	var newest := run.buffer.newest_tick()
	if render > newest:
		run.starved += 1
	if run.buffer.estimated_tick(run.now) - SnapshotBuffer.MIN_DELAY_TICKS > newest:
		run.starved_at_fixed_delay += 1
	var pose := run.buffer.pose_of(PEER, render)
	var newest_x := (_walker(newest)["position"] as Vector3).x
	run.extrapolated = maxf(run.extrapolated, pose.position.x - newest_x)
	if render <= newest:
		var expected := render * WALK / Ticks.RATE
		run.off_line = maxf(run.off_line, absf(pose.position.x - expected))


func _walker(tick: int) -> Dictionary:
	var avatar := _avatar(Vector3(tick * WALK / Ticks.RATE, 0, 0), Vector3(1, 0, 0))
	avatar["velocity"] = Vector3(WALK, 0, 0)
	return avatar


func _avatar(at: Vector3, facing: Vector3) -> Dictionary:
	return {
		"position": at,
		"velocity": Vector3.ZERO,
		"facing": facing,
		"downed": false,
		"held_item": -1,
	}
