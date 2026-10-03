extends GdUnitTestSuite
## VoiceViews' occlusion (the M5 ADR §1.6 and §3 item 8, E42 (a), D13 (a); M5-7) against fixture
## walls in the listener's own physics space: one ray per audible speaker per physics frame from
## the ears to the mouth, on the world layer only (a box on the LIVING or DOWNED layer, as a
## player's capsule is, muffles nothing, nor does a railing below the mouth); a hit muffles (8 dB
## on the speaker, the muffled Voice bus), eased in and back out over 100 ms; a speaker heard
## again after a silence starts at its ray's answer, and a speaker freed with its body takes its
## muffle along; the muffle never drops a frame. The voices' clock stays still, so the frames held
## keep each speaker audible; the physics frames are the engine's.

const World := preload("res://tests/integration/client/world/voice_test_world.gd")
const TALKER := World.TALKER
const OTHER := World.OTHER
## The ears at a standing listener's mouth height, so the rays run level.
const EARS := Vector3(0, 1.5, 0)
## A wall between the ears and a talker 3 m ahead.
const WALL_AT := Vector3(0, 1.5, -1.5)
const WALL_SIZE := Vector3(4, 3, 0.2)
## Frames held ahead (2 s): the speaker stays audible through every physics frame of a test.
const HELD := 100

var _world: World
var _voices: VoiceViews


func before_test() -> void:
	AudioBuses.ensure()
	_world = World.new()
	_world.ears_at = EARS
	add_child(_world)
	_voices = _world.voices


func after_test() -> void:
	_world.free()


func test_a_speaker_behind_a_wall_is_muffled_from_its_first_audible_frame() -> void:
	_world.add_box(WALL_AT, WALL_SIZE)
	var speaker := await _talking({TALKER: Vector3(0, 0, -3)})
	var muffle := _voices.muffle_of(TALKER)
	assert_object(muffle).is_not_null()
	assert_float(muffle.amount).is_equal(1.0)
	assert_float(speaker.extra_db).is_equal(Muffle.QUIET_DB)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE_MUFFLED))
	# The fade's volume and the muffle add up on the player. A coroutine resumes on process_frame
	# before that frame's _process runs, and a slow frame runs several physics steps before one,
	# so two process frames make sure a step saw the muffle.
	await _physics(2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(speaker.volume_db).is_less_equal(Muffle.QUIET_DB + 0.01)
	# Muffled, never dropped: every frame was handed to the speaker.
	assert_int(_voices.played).is_equal(HELD)
	assert_int(_voices.dropped).is_equal(0)


func test_a_speaker_in_the_open_is_not_muffled() -> void:
	# The wall stands aside, not between.
	_world.add_box(Vector3(3, 1.5, -1.5), WALL_SIZE)
	var speaker := await _talking({TALKER: Vector3(0, 0, -3)})
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(0.0)
	assert_float(speaker.extra_db).is_equal(0.0)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))


func test_a_railing_below_the_mouth_muffles_nothing() -> void:
	# A waist-high railing between: it hides the talker's feet from the ears, not its mouth, where
	# the ray aims.
	_world.add_box(Vector3(0, 0.5, -1.5), Vector3(4, 1.0, 0.2))
	var speaker := await _talking({TALKER: Vector3(0, 0, -3)})
	var space := _world.get_world_3d().direct_space_state
	var feet := _world.avatars.body_of(TALKER).global_position
	assert_bool(Muffle.blocked(space, EARS, feet)).is_true()
	await _physics(3)
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(0.0)
	assert_float(speaker.extra_db).is_equal(0.0)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))


func test_a_players_capsule_between_muffles_nothing() -> void:
	# OTHER's living body stands between the ears and TALKER's mouth, and boxes on the LIVING and
	# DOWNED layers (a capsule standing or lying, the own one at the ears) block the line too.
	_world.add_box(Vector3(0, 1.5, -2.2), Vector3(1, 1, 0.2), PhysicsLayers.LIVING)
	_world.add_box(Vector3(0, 1.5, -0.8), Vector3(1, 1, 0.2), PhysicsLayers.DOWNED)
	_world.add_box(EARS, Vector3(0.8, 1.8, 0.8), PhysicsLayers.LIVING)
	var speaker := await _talking({TALKER: Vector3(0, 0, -3), OTHER: Vector3(0, 0, -1.5)})
	var space := _world.get_world_3d().direct_space_state
	var mouth := speaker.global_position
	for mask: int in [PhysicsLayers.LIVING, PhysicsLayers.DOWNED]:
		# The line does cross them: a ray that also looked at those layers would hit.
		var query := PhysicsRayQueryParameters3D.create(EARS + Vector3(0, 0, -0.5), mouth, mask)
		assert_dict(space.intersect_ray(query)).is_not_empty()
	var other := _world.avatars.body_of(OTHER)
	assert_int(other.collision_layer).is_equal(PhysicsLayers.LIVING)
	await _physics(3)
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(0.0)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))


func test_one_ray_per_audible_speaker_per_physics_frame_and_none_for_the_silent() -> void:
	await _talking({TALKER: Vector3(0, 0, -3), OTHER: Vector3(2, 0, -3)})
	assert_object(_voices.speaker_of(OTHER)).is_not_null()
	await get_tree().physics_frame
	var before := _voices.rays
	await _physics(5)
	# Two audible speakers, five physics frames.
	assert_int(_voices.rays - before).is_equal(10)
	# OTHER falls silent (flushed, nothing held): its ray stops, TALKER's goes on.
	_voices.speaker_of(OTHER).flush_now()
	await get_tree().physics_frame
	before = _voices.rays
	await _physics(5)
	assert_int(_voices.rays - before).is_equal(5)


func test_no_ray_for_a_speaker_past_the_cutoff() -> void:
	var speaker := await _talking({TALKER: Vector3(0, 0, -3)})
	_world.ears_at = Vector3(0, 1.5, 20)
	await get_tree().physics_frame
	var before := _voices.rays
	await _physics(3)
	assert_int(_voices.rays).is_equal(before)
	assert_bool(speaker.fading() or not speaker.is_active()).is_true()


func test_the_muffle_eases_in_when_a_wall_comes_between_and_back_out_when_it_goes() -> void:
	var speaker := await _talking({TALKER: Vector3(0, 0, -3)})
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(0.0)
	var wall := _world.add_box(WALL_AT, WALL_SIZE)
	var first := await _until_moved(0.0)
	# Eased, not jumped: one physics frame moves it by its share of 100 ms.
	var share := 1.0 / (Engine.physics_ticks_per_second * Muffle.EASE_SEC)
	assert_float(first).is_equal_approx(share, 1e-4)
	assert_float(speaker.extra_db).is_between(Muffle.QUIET_DB + 0.01, -0.01)
	await _physics(ceili(1.0 / share) + 1)
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(1.0)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE_MUFFLED))
	# The wall goes: back out over the same ease, all the way to clear.
	wall.free()
	var back := await _until_moved(1.0)
	assert_float(back).is_equal_approx(1.0 - share, 1e-4)
	await _physics(ceili(1.0 / share) + 1)
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(0.0)
	assert_float(speaker.extra_db).is_equal(0.0)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))


func test_a_speaker_heard_again_after_a_silence_starts_at_its_rays_answer() -> void:
	var wall := _world.add_box(WALL_AT, WALL_SIZE)
	var speaker := await _talking({TALKER: Vector3(0, 0, -3)})
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(1.0)
	speaker.flush_now()
	await _physics(2)
	wall.free()
	await _physics(2)
	# Silent meanwhile: still at its last answer.
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(1.0)
	_world.speak(TALKER, HELD, 200)
	await _physics(2)
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(0.0)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))


func test_a_speaker_freed_with_its_body_takes_its_muffle_along() -> void:
	_world.add_box(WALL_AT, WALL_SIZE)
	var speaker := await _talking({TALKER: Vector3(0, 0, -3)})
	assert_object(_voices.muffle_of(TALKER)).is_not_null()
	_world.event(&"PlayerLeft", {"peer": TALKER})
	assert_object(_voices.muffle_of(TALKER)).is_null()
	_voices.reset()
	assert_object(_voices.muffle_of(OTHER)).is_null()
	# The speaker is gone by the next idle frame: the test ends with nothing left queued.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(speaker)).is_false()


func test_a_body_freed_without_player_left_takes_its_muffle_along() -> void:
	# The bodies go (a level swapped): the speaker goes with its body, and its muffle with it.
	var wall := _world.add_box(WALL_AT, WALL_SIZE)
	await _talking({TALKER: Vector3(0, 0, -3)})
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(1.0)
	_world.avatars.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(_voices.speaker_of(TALKER)).is_null()
	assert_object(_voices.muffle_of(TALKER)).is_null()
	# A new body in the open starts clear at its first audible frame, not eased from behind the wall.
	wall.free()
	await _physics(2)
	var speaker := await _talking({TALKER: Vector3(0, 0, -3)})
	assert_float(_voices.muffle_of(TALKER).amount).is_equal(0.0)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))


## The talkers' bodies at `at`, each with HELD frames at tick 10, after two physics frames (each
## speaker audible in both); returns TALKER's speaker.
func _talking(at: Dictionary[int, Vector3]) -> VoiceSpeaker:
	_world.place(at)
	await _physics(2)
	for peer: int in at:
		_world.speak(peer, HELD, 10)
	await _physics(2)
	var speaker := _voices.speaker_of(TALKER)
	assert_object(speaker).is_not_null()
	assert_bool(speaker.is_active()).is_true()
	return speaker


func _physics(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## TALKER's muffle once it has moved off `from` (within a bounded number of physics frames: the
## physics server may take a step to see a box come or go).
func _until_moved(from: float) -> float:
	for i: int in 5:
		await get_tree().physics_frame
		var amount := _voices.muffle_of(TALKER).amount
		if amount != from:
			return amount
	return from
