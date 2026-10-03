extends GdUnitTestSuite
## VoiceViews' rules over a hand-folded ClientModel (the M5 ADR §3 items 1 to 3 and 5, §5's M5-5
## row): real RemotePlayerBodies, real VoiceSpeakers with the fake codec, the voices' clock driven
## here. Each rule is seen failing on a plant: the dead check, the flush at an event, the late
## frame stamped before a KnockedDown and delivered after it (and after a revive), the body, the
## phase's radius and the ears' distance.

const World := preload("res://tests/integration/client/world/voice_test_world.gd")
const OWN := World.OWN
const TALKER := World.TALKER
const OTHER := World.OTHER
const STEP_USEC := 20000

var _world: World
var _voices: VoiceViews


func before_test() -> void:
	AudioBuses.ensure()
	_world = World.new()
	add_child(_world)
	_voices = _world.voices


func after_test() -> void:
	_world.free()


func test_a_living_speaker_with_a_body_plays_at_its_mouth_on_the_voice_bus() -> void:
	_world.place({TALKER: Vector3(0, 0, -3)})
	await _drawn()
	_world.speak(TALKER, 3, 5)
	var speaker := _voices.speaker_of(TALKER)
	assert_object(speaker).is_not_null()
	var body := _world.avatars.body_of(TALKER)
	assert_object(speaker.get_parent()).is_same(body.mouth_point())
	var eye := _world.mode.player_rules.eye_height_m
	var mouth_y := eye - RemotePlayerBody.MOUTH_BELOW_EYE_M
	assert_float(speaker.global_position.y).is_equal_approx(mouth_y, 1e-4)
	assert_str(String(speaker.bus)).is_equal(String(AudioBuses.VOICE))
	assert_int(speaker.attenuation_model).is_equal(AudioStreamPlayer3D.ATTENUATION_DISABLED)
	# The cutoff is the lobby's hearing radius from the own mode (E41), not a copy.
	var lobby := VoiceRule.radius_of(_world.mode.find_phase(&"lobby").voice_rule)
	assert_float(lobby).is_greater(0.0)
	assert_float(speaker.max_distance).is_equal(lobby)
	await _step()
	assert_int(_voices.played).is_equal(3)
	assert_int(speaker.jitter.starts).is_equal(1)
	assert_bool(speaker.is_active()).is_true()


func test_nothing_plays_for_a_speaker_without_a_body() -> void:
	await _drawn()
	_world.speak(TALKER, 3, 5)
	assert_object(_voices.speaker_of(TALKER)).is_null()
	assert_int(_voices.played).is_equal(0)
	assert_int(_voices.dropped).is_equal(3)


func test_a_dead_listener_plays_nothing_and_its_death_flushes_every_speaker() -> void:
	var speaker := await _talking()
	_world.event(&"Died", {"peer": OWN, "position": Vector3.ZERO})
	# Flushed at once: nothing held, nothing queued.
	assert_bool(speaker.is_active()).is_false()
	var heard := speaker.jitter.received
	_world.speak(TALKER, 5, 40)
	await _step()
	assert_int(speaker.jitter.received).is_equal(heard)
	assert_bool(speaker.is_active()).is_false()


func test_a_knocked_down_speaker_is_faded_and_flushed_and_its_late_frames_dropped() -> void:
	var speaker := await _talking()
	_world.event(&"KnockedDown", {"peer": TALKER, "position": Vector3(0, 0, -3)})
	assert_bool(speaker.fading()).is_true()
	# Recorded: the newest host tick seen (the snapshots' and the frames').
	var recorded := _voices.flushed_at(TALKER)
	assert_int(recorded).is_greater_equal(10)
	await _step(VoiceJitter.FADE_USEC + STEP_USEC)
	assert_bool(speaker.is_active()).is_false()
	var heard := speaker.jitter.received
	# A frame stamped before the knockdown, delivered after it (ENet orders nothing across lanes).
	_world.speak(TALKER, 1, 10)
	assert_int(speaker.jitter.received).is_equal(heard)
	# Raised: living again, but frames stamped at or before the flush still never play.
	_world.event(&"Revived", {"peer": TALKER})
	_world.speak(TALKER, 3, recorded)
	assert_int(speaker.jitter.received).is_equal(heard)
	_world.speak(TALKER, 3, recorded + 1)
	assert_int(speaker.jitter.received).is_equal(heard + 3)


func test_a_dying_speaker_is_faded_and_flushed() -> void:
	var speaker := await _talking()
	_world.event(&"Died", {"peer": TALKER, "position": Vector3(0, 0, -3)})
	assert_bool(speaker.fading()).is_true()
	var heard := speaker.jitter.received
	_world.speak(TALKER, 3, 99)
	assert_int(speaker.jitter.received).is_equal(heard)


func test_a_downed_listener_still_hears_the_living_and_its_knockdown_flushes_nobody() -> void:
	# Vision revision 1: the downed hear the living, from where they lie.
	var speaker := await _talking()
	_world.event(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO})
	assert_bool(speaker.fading()).is_false()
	assert_bool(speaker.is_active()).is_true()
	assert_int(_voices.flushed_at(TALKER)).is_equal(-1)
	var heard := speaker.jitter.received
	var played := _voices.played
	_world.speak(TALKER, 3, 20)
	assert_int(speaker.jitter.received).is_equal(heard + 3)
	assert_int(_voices.played).is_equal(played + 3)


func test_the_own_death_records_the_flush_of_a_speaker_not_heard_yet() -> void:
	# OTHER has a body but no frame yet, so no speaker: its frames stamped before the own death and
	# delivered after the respawn never play all the same (the M5 ADR §3 item 3).
	_world.place({TALKER: Vector3(0, 0, -3), OTHER: Vector3(2, 0, -3)})
	await _drawn()
	_world.speak(TALKER, 3, 10)
	assert_object(_voices.speaker_of(OTHER)).is_null()
	_world.event(&"Died", {"peer": OWN, "position": Vector3.ZERO})
	assert_int(_voices.flushed_at(OTHER)).is_equal(10)
	_world.event(&"Respawned", {"peer": OWN, "position": Vector3.ZERO})
	_world.speak(OTHER, 3, 10)
	assert_object(_voices.speaker_of(OTHER)).is_null()
	_world.speak(OTHER, 3, 11)
	assert_int(_voices.speaker_of(OTHER).jitter.received).is_equal(3)


func test_frames_reaching_a_fading_speaker_count_as_dropped_not_played() -> void:
	var speaker := await _talking()
	_world.ears_at = Vector3(0, 0, 20)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(speaker.fading()).is_true()
	# Back within the cutoff while the fade still runs: the fade discards them, so none played.
	_world.ears_at = Vector3.ZERO
	var played := _voices.played
	var dropped := _voices.dropped
	_world.speak(TALKER, 3, 20)
	assert_int(_voices.played).is_equal(played)
	assert_int(_voices.dropped).is_equal(dropped + 3)


func test_a_reset_forgets_the_flushes_so_a_new_session_hears_low_ticks() -> void:
	var speaker := await _talking()
	_world.event(&"KnockedDown", {"peer": TALKER, "position": Vector3(0, 0, -3)})
	assert_int(_voices.flushed_at(TALKER)).is_greater_equal(10)
	_voices.reset()
	assert_int(_voices.flushed_at(TALKER)).is_equal(-1)
	assert_bool(is_instance_valid(speaker) and not speaker.is_queued_for_deletion()).is_false()


func test_a_phase_that_hears_nobody_flushes_every_speaker_and_the_cutoff_follows_the_phase(
) -> void:
	var speaker := await _talking()
	_world.event(&"PhaseChanged", {"phase": &"loading", "end_tick": -1})
	assert_float(_voices.cutoff()).is_equal(0.0)
	assert_bool(speaker.is_active()).is_false()
	assert_float(speaker.max_distance).is_equal_approx(VoiceSpeaker.SILENT_DISTANCE_M, 1e-6)
	var heard := speaker.jitter.received
	_world.speak(TALKER, 3, 50)
	assert_int(speaker.jitter.received).is_equal(heard)
	_world.event(&"PhaseChanged", {"phase": &"round", "end_tick": -1})
	var round_m := VoiceRule.radius_of(_world.mode.find_phase(&"round").voice_rule)
	assert_float(speaker.max_distance).is_equal(round_m)
	_world.speak(TALKER, 3, 60)
	assert_int(speaker.jitter.received).is_equal(heard + 3)


func test_a_speaker_past_the_cutoff_from_the_ears_is_faded_and_its_frames_dropped() -> void:
	var speaker := await _talking()
	# The ears walk away: the talker at (0, 0, -3) is now 23 m from them.
	_world.ears_at = Vector3(0, 0, 20)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(speaker.fading()).is_true()
	await _step(VoiceJitter.FADE_USEC + STEP_USEC)
	assert_bool(speaker.is_active()).is_false()
	var heard := speaker.jitter.received
	_world.speak(TALKER, 3, 80)
	assert_int(speaker.jitter.received).is_equal(heard)
	# Back within the cutoff, newer frames play again.
	_world.ears_at = Vector3.ZERO
	_world.speak(TALKER, 3, 81)
	assert_int(speaker.jitter.received).is_equal(heard + 3)


func test_a_speaker_who_leaves_is_flushed_and_freed() -> void:
	var speaker := await _talking()
	_world.event(&"PlayerLeft", {"peer": TALKER})
	assert_bool(speaker.is_queued_for_deletion()).is_true()
	assert_object(_voices.speaker_of(TALKER)).is_null()
	var dropped := _voices.dropped
	_world.speak(TALKER, 3, 99)
	assert_int(_voices.dropped).is_equal(dropped + 3)


func test_the_own_peer_and_an_unavailable_codec_play_nothing() -> void:
	_world.place({TALKER: Vector3(0, 0, -3), OWN: Vector3(1, 0, 0)})
	await _drawn()
	_world.speak(OWN, 3, 5)
	assert_int(_voices.played).is_equal(0)
	_world.codec.is_available = false
	_world.speak(TALKER, 3, 5)
	assert_int(_voices.played).is_equal(0)
	assert_object(_voices.speaker_of(TALKER)).is_null()


func test_the_overlay_lines_number_the_speakers_by_first_arrival() -> void:
	_world.place({TALKER: Vector3(0, 0, -3), OTHER: Vector3(2, 0, -3)})
	await _drawn()
	_world.speak(OTHER, 4, 5)
	_world.speak(TALKER, 3, 5)
	var stats := _voices.stats()
	assert_int(stats.size()).is_equal(2)
	assert_int(stats[0].index).is_equal(1)
	assert_int(stats[0].received).is_equal(4)
	assert_int(stats[1].index).is_equal(2)
	assert_int(stats[1].received).is_equal(3)
	var text := DebugOverlay.voice_text(stats)
	assert_str(text).contains("#1 ").contains("#2 ")
	assert_str(text).not_contains("Player")


func test_the_cutoff_follows_the_models_phase_without_a_phase_change() -> void:
	# A Welcome sets the model's phase with no PhaseChanged: the cutoff must follow it all the same.
	_world.place({TALKER: Vector3(0, 0, -3)})
	await _drawn()
	_world.model.phase = &"loading"
	_voices.on_event(&"Welcome", {})
	assert_float(_voices.cutoff()).is_equal(0.0)
	_world.speak(TALKER, 3, 5)
	assert_int(_voices.played).is_equal(0)
	_world.model.phase = &"lobby"
	_world.speak(TALKER, 3, 6)
	assert_float(_voices.cutoff()).is_greater(0.0)
	assert_int(_voices.played).is_equal(3)


func test_a_speaker_freed_with_its_body_is_forgotten_and_made_again() -> void:
	var speaker := await _talking()
	# The avatar leaves the snapshots: AvatarViews frees the body, and the speaker with it.
	_world.place({OTHER: Vector3(3, 0, 0)})
	await _drawn()
	await _drawn()
	assert_bool(is_instance_valid(speaker)).is_false()
	assert_object(_voices.speaker_of(TALKER)).is_null()
	assert_array(_voices.stats()).is_empty()
	await _step()
	_world.place({TALKER: Vector3(0, 0, -3), OTHER: Vector3(3, 0, 0)})
	await _drawn()
	_world.speak(TALKER, 3, 90)
	var again := _voices.speaker_of(TALKER)
	assert_object(again).is_not_null()
	assert_int(again.jitter.received).is_equal(3)


## TALKER's body 3 m from the ears, and a spurt of 5 frames at tick 10 started.
func _talking() -> VoiceSpeaker:
	_world.place({TALKER: Vector3(0, 0, -3)})
	await _drawn()
	_world.speak(TALKER, 5, 10)
	await _step()
	var speaker := _voices.speaker_of(TALKER)
	assert_bool(speaker.is_active()).is_true()
	assert_int(speaker.jitter.starts).is_equal(1)
	return speaker


## Moves the voices' clock on by `usec`, then lets every speaker step. A coroutine resumes on
## process_frame before that frame's _process runs, so two frames make sure one step saw it.
func _step(usec := STEP_USEC) -> void:
	_world.voice_now += usec
	await get_tree().process_frame
	await get_tree().process_frame


func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
