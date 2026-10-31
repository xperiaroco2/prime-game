extends GdUnitTestSuite
## VoiceViews' drunk voice (#1392; ARCHITECTURE §4.7.15, §6) on the real AudioServer, with the
## base mode's own copy (its lobby's provisional pitch wobble): a played frame with a strength puts
## its speaker on its own bus holding the effect, whose parameter follows the strength and the
## clock, sending to Voice, or VoiceMuffled behind a wall (the muffle on top); a frame at strength 0
## puts it back on Voice and removes the bus; a sober speaker never gets one, nor the own peer nor a
## dropped frame; the bus goes with the body, at reset() and in a phase with no effect. The sound
## itself is not checked here: that is a listening test on two machines.

const World := preload("res://tests/integration/client/world/voice_test_world.gd")
const OWN := World.OWN
const TALKER := World.TALKER
const OTHER := World.OTHER
const EARS := Vector3(0, 1.5, 0)
const WALL_AT := Vector3(0, 1.5, -1.5)
const WALL_SIZE := Vector3(4, 3, 0.2)
## Frames held ahead (2 s): the speaker stays audible through every physics frame of a test.
const HELD := 100

var _world: World
var _voices: VoiceViews
var _buses := 0


func before_test() -> void:
	AudioBuses.ensure()
	_buses = AudioServer.bus_count
	_world = World.new()
	_world.ears_at = EARS
	add_child(_world)
	_voices = _world.voices


func after_test() -> void:
	_world.free()
	# Freed with the world: no bus of it is left behind.
	assert_int(AudioServer.bus_count).is_equal(_buses)


func test_a_drunk_speaker_plays_on_its_own_bus_with_the_effect() -> void:
	var speaker := await _talking(255)
	var drunk := _voices.drunk_bus_of(TALKER)
	assert_object(drunk).is_not_null()
	assert_str(String(speaker.bus)).is_equal(String(drunk.name))
	assert_int(AudioServer.bus_count).is_equal(_buses + 1)
	var index := drunk.index()
	assert_str(String(AudioServer.get_bus_send(index))).is_equal(String(AudioBuses.VOICE))
	assert_int(AudioServer.get_bus_effect_count(index)).is_equal(1)
	var shift := AudioServer.get_bus_effect(index, 0) as AudioEffectPitchShift
	assert_object(shift).is_not_null()
	assert_object(shift).is_same(drunk.made())
	# The mode's settings are set on it.
	assert_int(shift.fft_size).is_equal(AudioEffectPitchShift.FFT_SIZE_1024)
	# The parameter follows the strength and the clock.
	var effect := _world.mode.find_phase(&"lobby").voice_rule.drunk_effect
	var first := shift.pitch_scale
	assert_float(first).is_equal_approx(effect.value_at(255, _world.voice_now / 1e6), 1e-5)
	_world.voice_now += 400000
	await _physics(2)
	assert_float(shift.pitch_scale).is_equal_approx(
		effect.value_at(255, _world.voice_now / 1e6), 1e-5
	)
	assert_float(absf(shift.pitch_scale - first)).is_greater(1e-3)
	# The effect never drops a frame.
	assert_int(_voices.played).is_equal(HELD)
	assert_int(_voices.dropped).is_equal(0)


func test_the_strength_scales_the_swing() -> void:
	await _talking(51)
	var shift := _voices.drunk_bus_of(TALKER).made() as AudioEffectPitchShift
	var effect := _world.mode.find_phase(&"lobby").voice_rule.drunk_effect
	var expected := effect.value_at(51, _world.voice_now / 1e6)
	assert_float(shift.pitch_scale).is_equal_approx(expected, 1e-5)
	assert_float(absf(shift.pitch_scale - 1.0)).is_less_equal(effect.swing * 51 / 255.0 + 1e-5)


func test_behind_a_wall_the_drunk_bus_sends_to_the_muffled_bus() -> void:
	_world.add_box(WALL_AT, WALL_SIZE)
	var speaker := await _talking(200)
	var drunk := _voices.drunk_bus_of(TALKER)
	assert_str(String(speaker.bus)).is_equal(String(drunk.name))
	var send := AudioServer.get_bus_send(drunk.index())
	assert_str(String(send)).is_equal(String(AudioBuses.VOICE_MUFFLED))
	assert_float(speaker.extra_db).is_equal(Muffle.QUIET_DB)


func test_a_sober_frame_puts_the_speaker_back_on_voice_and_removes_the_bus() -> void:
	var speaker := await _talking(128)
	assert_int(AudioServer.bus_count).is_equal(_buses + 1)
	_world.speak(TALKER, 1, 11, 0.5, 0)
	await _physics(2)
	assert_object(_voices.drunk_bus_of(TALKER)).is_null()
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))
	assert_int(AudioServer.bus_count).is_equal(_buses)


func test_an_idle_drunk_speaker_keeps_no_bus() -> void:
	var speaker := await _talking(255)
	assert_int(AudioServer.bus_count).is_equal(_buses + 1)
	# It stops talking: nothing playing or waiting any more.
	speaker.flush_now()
	await _physics(2)
	assert_bool(speaker.is_active()).is_false()
	assert_object(_voices.drunk_bus_of(TALKER)).is_null()
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))
	assert_int(AudioServer.bus_count).is_equal(_buses)
	# Its next words make the bus again.
	_world.speak(TALKER, 5, 200, 0.5, 255)
	await _physics(2)
	assert_object(_voices.drunk_bus_of(TALKER)).is_not_null()
	assert_int(AudioServer.bus_count).is_equal(_buses + 1)


func test_an_unusable_effect_plays_the_voice_unchanged() -> void:
	# A mode whose drunk effect names no engine class: one warning, no bus, the voice on Voice.
	var bad := _world.mode.duplicate(true) as GameMode
	for phase: StringName in [&"lobby", &"countdown"]:
		var effect := bad.find_phase(phase).voice_rule.drunk_effect
		effect.bus_effect = &"NoSuchAudioEffect"
	_voices.mode = bad
	_world.event(&"PhaseChanged", {"phase": &"countdown", "end_tick": -1})
	await _physics(2)
	var speaker := await _talking(255)
	await _physics(3)
	assert_object(_voices.drunk_bus_of(TALKER)).is_null()
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))
	assert_int(AudioServer.bus_count).is_equal(_buses)
	assert_int(_voices.dropped).is_equal(0)


func test_a_sober_speaker_never_gets_a_bus() -> void:
	var speaker := await _talking(0)
	assert_object(_voices.drunk_bus_of(TALKER)).is_null()
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))
	assert_int(AudioServer.bus_count).is_equal(_buses)


func test_the_own_peer_s_frames_make_no_bus() -> void:
	# The own voice is never played (the host sends none; one that came would be dropped): its own
	# player never hears its change.
	_world.place({TALKER: Vector3(0, 0, -3)})
	await _physics(2)
	_world.speak(OWN, 5, 10, 0.5, 255)
	await _physics(2)
	assert_int(_voices.played).is_equal(0)
	assert_object(_voices.drunk_bus_of(OWN)).is_null()
	assert_int(AudioServer.bus_count).is_equal(_buses)


func test_a_dropped_frame_sets_no_strength() -> void:
	# Past the radius (8 m): the frames are dropped, and so is their strength.
	_world.place({TALKER: Vector3(0, 0, -20)})
	await _physics(2)
	_world.speak(TALKER, 5, 10, 0.5, 255)
	await _physics(2)
	assert_int(_voices.played).is_equal(0)
	assert_object(_voices.drunk_bus_of(TALKER)).is_null()
	assert_int(AudioServer.bus_count).is_equal(_buses)


func test_the_bus_goes_with_the_body() -> void:
	# The bodies go (a level swapped): the speaker goes with its body, and its bus with it.
	await _talking(255)
	_world.avatars.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(_voices.speaker_of(TALKER)).is_null()
	assert_object(_voices.drunk_bus_of(TALKER)).is_null()
	assert_int(AudioServer.bus_count).is_equal(_buses)


func test_the_bus_goes_when_the_speaker_leaves() -> void:
	await _talking(255)
	_world.event(&"PlayerLeft", {"peer": TALKER})
	assert_object(_voices.drunk_bus_of(TALKER)).is_null()
	assert_int(AudioServer.bus_count).is_equal(_buses)
	await get_tree().process_frame
	await get_tree().process_frame


func test_reset_removes_every_bus() -> void:
	_world.place({TALKER: Vector3(0, 0, -3), OTHER: Vector3(2, 0, -3)})
	await _physics(2)
	_world.speak(TALKER, HELD, 10, 0.5, 255)
	_world.speak(OTHER, HELD, 10, 0.5, 90)
	await _physics(2)
	assert_int(AudioServer.bus_count).is_equal(_buses + 2)
	_voices.reset()
	assert_int(AudioServer.bus_count).is_equal(_buses)


func test_a_phase_with_no_effect_plays_the_voice_unchanged() -> void:
	var speaker := await _talking(255)
	assert_object(_voices.drunk_bus_of(TALKER)).is_not_null()
	# The base mode's round has no drunk effect (nobody is drunk there).
	_world.event(&"PhaseChanged", {"phase": &"round", "end_tick": -1})
	await _physics(2)
	assert_object(_voices.drunk_bus_of(TALKER)).is_null()
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))
	assert_int(AudioServer.bus_count).is_equal(_buses)


## TALKER 3 m ahead, talking HELD frames of `strength`, audible.
func _talking(strength: int) -> VoiceSpeaker:
	_world.place({TALKER: Vector3(0, 0, -3)})
	await _physics(2)
	_world.speak(TALKER, HELD, 10, 0.5, strength)
	await _physics(2)
	var speaker := _voices.speaker_of(TALKER)
	assert_object(speaker).is_not_null()
	assert_bool(speaker.is_active()).is_true()
	return speaker


func _physics(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
