extends GdUnitTestSuite
## Muffle (the M5 ADR §1.6, D13 (a); M5-7), pure: behind the level 8 dB quieter and on the muffled
## bus, eased over 100 ms both ways, jumping to the ray's answer after a rest, never louder than
## clear, and a ray flickering at an edge does not flip the bus.

const FRAME := 1.0 / 60.0


func test_the_first_ray_sets_the_muffle_without_easing() -> void:
	var muffle := Muffle.new()
	muffle.follow(true, FRAME)
	assert_float(muffle.amount).is_equal(1.0)
	assert_float(muffle.volume_db()).is_equal(Muffle.QUIET_DB)
	assert_float(Muffle.QUIET_DB).is_equal(-8.0)
	assert_bool(muffle.dulled()).is_true()
	assert_str(String(muffle.bus_for(AudioBuses.VOICE))).is_equal(String(AudioBuses.VOICE_MUFFLED))
	var clear := Muffle.new()
	clear.follow(false, FRAME)
	assert_float(clear.amount).is_equal(0.0)
	assert_float(clear.volume_db()).is_equal(0.0)
	assert_str(String(clear.bus_for(AudioBuses.VOICE))).is_equal(String(AudioBuses.VOICE))


func test_it_eases_in_over_100_ms_and_back_out_as_long() -> void:
	var muffle := Muffle.new()
	muffle.follow(false, FRAME)
	muffle.follow(true, 0.025)
	assert_float(muffle.amount).is_equal_approx(0.25, 1e-6)
	assert_float(muffle.volume_db()).is_equal_approx(-2.0, 1e-6)
	assert_bool(muffle.dulled()).is_false()
	muffle.follow(true, 0.025)
	assert_bool(muffle.dulled()).is_false()
	muffle.follow(true, 0.025)
	assert_bool(muffle.dulled()).is_true()
	assert_str(String(muffle.bus_for(AudioBuses.EFFECTS))).is_equal(
		String(AudioBuses.EFFECTS_MUFFLED)
	)
	muffle.follow(true, 0.025)
	assert_float(muffle.amount).is_equal(1.0)
	muffle.follow(true, 1.0)
	assert_float(muffle.amount).is_equal(1.0)
	# Back out: the same ease, not a jump, and all the way; dulled until a quarter.
	muffle.follow(false, 0.025)
	assert_float(muffle.amount).is_equal_approx(0.75, 1e-6)
	muffle.follow(false, 0.025)
	assert_bool(muffle.dulled()).is_true()
	muffle.follow(false, 0.026)
	assert_bool(muffle.dulled()).is_false()
	muffle.follow(false, 0.08)
	assert_float(muffle.amount).is_equal(0.0)
	assert_float(muffle.volume_db()).is_equal(0.0)
	assert_str(String(muffle.bus_for(AudioBuses.EFFECTS))).is_equal(String(AudioBuses.EFFECTS))


func test_after_a_rest_the_next_ray_jumps() -> void:
	var muffle := Muffle.new()
	muffle.follow(true, FRAME)
	muffle.rest()
	muffle.follow(false, FRAME)
	assert_float(muffle.amount).is_equal(0.0)
	muffle.follow(true, FRAME)
	assert_float(muffle.amount).is_equal_approx(FRAME / Muffle.EASE_SEC, 1e-6)


func test_it_never_raises_the_volume() -> void:
	var muffle := Muffle.new()
	for step: int in 20:
		muffle.follow(step % 7 < 4, FRAME)
		assert_float(muffle.volume_db()).is_between(Muffle.QUIET_DB, 0.0)
	# A sound with no muffled bus keeps its own.
	muffle.follow(true, 1.0)
	assert_str(String(muffle.bus_for(AudioBuses.MUSIC))).is_equal(String(AudioBuses.MUSIC))


func test_a_ray_flickering_at_an_edge_does_not_flip_the_bus() -> void:
	var muffle := Muffle.new()
	muffle.follow(false, FRAME)
	# Three frames in: half way, still clear.
	for i: int in 3:
		muffle.follow(true, FRAME)
	assert_float(muffle.amount).is_equal_approx(0.5, 1e-6)
	var flips := 0
	var was := muffle.dulled()
	for i: int in 30:
		muffle.follow(i % 2 == 0, FRAME)
		if muffle.dulled() != was:
			flips += 1
			was = muffle.dulled()
	assert_int(flips).is_equal(0)
