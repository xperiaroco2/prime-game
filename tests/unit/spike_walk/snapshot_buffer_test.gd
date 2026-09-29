extends GdUnitTestSuite
## Spike (#14): remote players are interpolated between snapshots, a delay behind the host clock.

const ID := 4

var _buffer: SpikeSnapshotBuffer


func before_test() -> void:
	_buffer = SpikeSnapshotBuffer.new()
	_buffer.tick_hz = 20.0
	_buffer.delay = 0.1


func _push(local_time: float, tick: int, x: float, yaw: float = 0.0) -> void:
	_buffer.push(
		local_time,
		tick,
		PackedInt32Array([ID]),
		PackedVector3Array([Vector3(x, 0, 0)]),
		PackedFloat32Array([yaw])
	)


func _x_at(local_time: float) -> float:
	var s := _buffer.sample(ID, local_time)
	return (s[0] as Vector3).x


func test_interpolates_between_snapshots() -> void:
	# Host ticks 0..4 at 20 Hz arrive with a constant latency: host time = local time.
	for tick in 5:
		_push(tick / 20.0, tick, float(tick))
	# Local 0.225 renders host time 0.125: halfway between tick 2 (x=2) and tick 3 (x=3).
	assert_float(_x_at(0.225)).is_equal_approx(2.5, 0.001)
	assert_int(_buffer.starved).is_equal(0)


func test_holds_and_counts_when_starved() -> void:
	_push(0.0, 0, 0.0)
	_push(0.05, 1, 1.0)
	# Local 0.5 renders host time 0.4, long after the newest sample.
	assert_float(_x_at(0.5)).is_equal(1.0)
	assert_int(_buffer.starved).is_equal(1)


func test_a_late_packet_does_not_pull_the_clock_back() -> void:
	_push(0.0, 0, 0.0)
	_push(0.05, 1, 1.0)
	# Tick 2 arrives 80 ms late; the clock estimate stays with the earliest arrivals.
	_push(0.18, 2, 2.0)
	assert_float(_buffer.render_time(0.18)).is_equal_approx(0.08, 0.001)


func test_recovers_after_host_time_falls_behind() -> void:
	# Half a second of host time is lost (a host hitch): from tick 10 on every snapshot arrives
	# 0.5 s later than its tick says. Within the offset window rendering must stop starving.
	for tick in 10:
		_push(tick / 20.0, tick, float(tick))
	var starved_at_end := 0
	for tick in range(10, 70):
		var local_time := tick / 20.0 + 0.5
		_push(local_time, tick, float(tick))
		var before := _buffer.starved
		_buffer.sample(ID, local_time + 0.02)
		if tick >= 60:
			starved_at_end += _buffer.starved - before
	assert_int(starved_at_end).is_equal(0)


func test_ignores_old_ticks() -> void:
	_push(0.0, 3, 3.0)
	_push(0.01, 2, 99.0)
	assert_float(_x_at(0.2)).is_equal(3.0)


func test_interpolates_yaw_the_short_way() -> void:
	_push(0.0, 0, 0.0, PI - 0.1)
	_push(0.05, 1, 0.0, -PI + 0.1)
	var s := _buffer.sample(ID, 0.125)
	assert_float(absf(s[1] as float)).is_greater(PI - 0.11)


func test_drops_players_missing_from_a_snapshot() -> void:
	_push(0.0, 0, 0.0)
	_buffer.push(0.05, 1, PackedInt32Array(), PackedVector3Array(), PackedFloat32Array())
	assert_array(_buffer.ids()).is_empty()
	assert_array(_buffer.sample(ID, 0.1)).is_empty()
