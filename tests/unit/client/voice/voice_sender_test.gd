extends GdUnitTestSuite
## VoiceSender (the M5 ADR §1.1 and §1.2, E37; client/voice/): `may_speak` from the own life fold
## and the own mode's phase only; every captured chunk drained, encoded and fed every frame, also
## while `may_speak` is false, so nothing recorded while downed goes out after a revive (the
## manager's review of PR #234, item 5); voice activity and push-to-talk; nothing without the codec.
## Through FakeMicrophone and FakeVoiceCodec: no microphone, no addon. A planted widening of each
## rule (no life check, a skipped drain while unspeakable) was seen failing these tests.

const MODE := "res://content/modes/base_mode.tres"
const OWN := 1
const OTHER := 2
const LOUD := 0.5
const QUIET := 0.0

var _mode: GameMode
var _model: ClientModel
var _sent: Array[PackedByteArray] = []


func before() -> void:
	_mode = load(MODE) as GameMode


func before_test() -> void:
	_sent.clear()
	_model = ClientModel.new(_mode)
	_model.own_peer = OWN
	for peer: int in [OWN, OTHER]:
		var member := ClientModel.Member.new()
		member.name = "Player%d" % peer
		_model.roster[peer] = member
	_model.phase = &"lobby"


func test_may_speak_only_living_in_a_phase_that_hears_someone() -> void:
	assert_bool(VoiceSender.may_speak_of(_model, _mode)).is_true()
	_model.phase = &"round"
	assert_bool(VoiceSender.may_speak_of(_model, _mode)).is_true()
	for life: ClientModel.Life in [
		ClientModel.Life.DOWNED, ClientModel.Life.DEAD, ClientModel.Life.LEFT
	]:
		_model.lives[OWN] = life
		assert_bool(VoiceSender.may_speak_of(_model, _mode)).is_false()
	# Another player's life is not the own.
	_model.lives.erase(OWN)
	_model.lives[OTHER] = ClientModel.Life.DEAD
	assert_bool(VoiceSender.may_speak_of(_model, _mode)).is_true()
	# Phases whose rule hears nobody (Loading and End, SilentVoice), and one the mode lacks.
	for silent: StringName in [&"loading", &"end", &"no_such_phase"]:
		_model.phase = silent
		assert_bool(VoiceSender.may_speak_of(_model, _mode)).is_false()


func test_may_speak_needs_a_welcome_and_both_inputs() -> void:
	var fresh := ClientModel.new(_mode)
	assert_bool(VoiceSender.may_speak_of(fresh, _mode)).is_false()
	assert_bool(VoiceSender.may_speak_of(null, _mode)).is_false()
	assert_bool(VoiceSender.may_speak_of(_model, null)).is_false()


func test_voice_activity_sends_speech_and_nothing_in_silence() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	mic.capture_chunks(10, QUIET)
	sender.step()
	assert_array(_sent).is_empty()
	mic.capture_chunks(1, LOUD)
	sender.step()
	# The pre-roll (the two quiet chunks before) and the loud one.
	assert_int(_sent.size()).is_equal(VoiceGate.PREROLL + 1)
	for frame: PackedByteArray in _sent:
		assert_int(frame.size()).is_equal(FakeVoiceCodec.FRAME_SAMPLES)
	assert_int(sender.sent).is_equal(3)
	assert_float(sender.peak).is_equal_approx(LOUD, 0.001)


func test_every_chunk_is_drained_and_fed_while_may_speak_is_false() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	_model.lives[OWN] = ClientModel.Life.DOWNED
	# Whispering while downed: each frame drains everything captured, and sends nothing.
	for frame: int in 3:
		mic.capture_chunks(2, LOUD)
		sender.step()
		assert_int(mic.frames_available()).is_equal(0)
		assert_float(sender.peak).is_equal_approx(LOUD, 0.001)
	assert_array(_sent).is_empty()
	# The revive lands: nothing recorded before it goes out, neither as a backlog nor as pre-roll.
	_model.lives.erase(OWN)
	sender.step()
	assert_array(_sent).is_empty()
	mic.capture_chunks(1, LOUD)
	sender.step()
	assert_int(_sent.size()).is_equal(1)


func test_a_backlog_recorded_before_a_revive_is_not_sent_after_a_long_frame() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	_model.phase = &"round"
	_model.lives[OWN] = ClientModel.Life.DOWNED
	sender.step()
	# A 300 ms hitch: fifteen chunks of a downed whisper wait when the revive is folded, at the start
	# of the same frame that drains them.
	mic.capture_chunks(15, LOUD)
	_model.lives.erase(OWN)
	sender.step()
	assert_int(mic.frames_available()).is_equal(0)
	assert_array(_sent).is_empty()
	# Speech after the revive goes out, with no pre-roll from before it.
	mic.capture_chunks(1, LOUD)
	sender.step()
	assert_int(_sent.size()).is_equal(1)


func test_a_backlog_recorded_in_loading_does_not_open_the_round() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	_model.phase = &"loading"
	sender.step()
	# Half a chunk more than ten: the part chunk is recorded before the Round too.
	mic.capture(10 * int(mic.rate / 50.0) + int(mic.rate / 100.0), LOUD)
	_model.phase = &"round"
	sender.step()
	assert_array(_sent).is_empty()
	mic.capture(int(mic.rate / 100.0), LOUD)
	sender.step()
	assert_array(_sent).is_empty()
	mic.capture_chunks(1, LOUD)
	sender.step()
	assert_int(_sent.size()).is_equal(1)


func test_a_frame_with_no_chunk_while_unspeakable_empties_the_pre_roll() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	_model.phase = &"round"
	# Two quiet chunks wait in the pre-roll; then the device delivers nothing while downed.
	mic.capture_chunks(VoiceGate.PREROLL, QUIET)
	sender.step()
	_model.lives[OWN] = ClientModel.Life.DOWNED
	sender.step()
	_model.lives.erase(OWN)
	sender.step()
	mic.capture_chunks(1, LOUD)
	sender.step()
	assert_int(_sent.size()).is_equal(1)


func test_a_phase_that_hears_nobody_sends_nothing_and_keeps_nothing() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	_model.phase = &"loading"
	mic.capture_chunks(5, LOUD)
	sender.step()
	assert_array(_sent).is_empty()
	# The Round's first frame; what waits then was recorded in Loading (the backlog tests above).
	_model.phase = &"round"
	sender.step()
	mic.capture_chunks(1, LOUD)
	sender.step()
	assert_int(_sent.size()).is_equal(1)


func test_push_to_talk_sends_only_while_the_key_is_held_with_no_menu() -> void:
	var sender := _sender()
	sender.gate.set_mode(VoiceGate.Mode.PUSH_TO_TALK)
	var mic := sender.capture.microphone as FakeMicrophone
	mic.capture_chunks(3, LOUD)
	sender.step()
	assert_array(_sent).is_empty()
	sender.talk_held = true
	sender.listening = false
	mic.capture_chunks(1, LOUD)
	sender.step()
	assert_array(_sent).is_empty()
	sender.listening = true
	mic.capture_chunks(1, QUIET)
	sender.step()
	# Held: the pre-roll and the frame, quiet or not.
	assert_int(_sent.size()).is_equal(VoiceGate.PREROLL + 1)


func test_between_sessions_the_microphone_is_drained_and_nothing_is_sent() -> void:
	var sender := _sender()
	sender.reset()
	var mic := sender.capture.microphone as FakeMicrophone
	mic.capture_chunks(4, LOUD)
	sender.step()
	assert_int(mic.frames_available()).is_equal(0)
	assert_int(sender.sent).is_equal(0)
	assert_array(_sent).is_empty()


func test_nothing_opens_or_is_sent_without_the_codec() -> void:
	var sender: VoiceSender = auto_free(VoiceSender.new())
	var mic := FakeMicrophone.new()
	sender.capture.microphone = mic
	var codec := FakeVoiceCodec.new()
	codec.is_available = false
	sender.codec = codec
	assert_bool(sender.open("Default", true)).is_false()
	assert_str(sender.error).is_equal(VoiceSender.UNAVAILABLE)
	assert_int(mic.opens).is_equal(0)
	assert_bool(sender.is_open()).is_false()
	sender.step()
	assert_array(_sent).is_empty()


func test_the_encoder_starts_at_the_device_rate_with_rnnoise_for_a_microphone_only() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	mic.rate = 44100
	assert_bool(sender.open("Headset Microphone", true)).is_true()
	var encoder := sender.encoder() as FakeVoiceEncoder
	assert_int(encoder.input_rate).is_equal(44100)
	assert_bool(encoder.denoise).is_true()
	assert_bool(sender.open("Headset Microphone", false)).is_true()
	assert_bool((sender.encoder() as FakeVoiceEncoder).denoise).is_false()
	# The test tone is no speech: RNNoise would remove it.
	sender.capture.microphone = VoiceToneMicrophone.new()
	assert_bool(sender.open("test tone", true)).is_true()
	assert_bool((sender.encoder() as FakeVoiceEncoder).denoise).is_false()


func test_closing_stops_the_capture_and_empties_the_pre_roll() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	mic.capture_chunks(2, QUIET)
	sender.step()
	sender.close()
	assert_bool(sender.is_open()).is_false()
	assert_bool(mic.is_open).is_false()
	assert_bool(sender.open("Default", true)).is_true()
	mic.capture_chunks(1, LOUD)
	sender.step()
	# No pre-roll from before the close.
	assert_int(_sent.size()).is_equal(1)


func test_a_failed_device_is_an_error_and_nothing_is_open() -> void:
	var sender: VoiceSender = auto_free(VoiceSender.new())
	var mic := FakeMicrophone.new()
	mic.open_result = ERR_UNAUTHORIZED
	sender.capture.microphone = mic
	sender.codec = FakeVoiceCodec.new()
	assert_bool(sender.open("Default", true)).is_false()
	assert_str(sender.error).contains("privacy")
	assert_bool(sender.is_open()).is_false()


func test_the_overlay_numbers_follow_the_latest_chunk() -> void:
	var sender := _sender()
	var mic := sender.capture.microphone as FakeMicrophone
	mic.capture_chunks(3, LOUD)
	sender.step()
	# The last chunk read waited one chunk: 20 ms.
	assert_int(sender.frame_age_usec).is_equal(20000)
	assert_int(sender.encode_usec).is_greater_equal(0)


## A sender over a FakeMicrophone and the fake codec, open on the Windows default, speaking into
## `_sent` for the own model in the lobby, the talk key set by hand.
func _sender() -> VoiceSender:
	var sender: VoiceSender = auto_free(VoiceSender.new())
	sender.capture.microphone = FakeMicrophone.new()
	sender.codec = FakeVoiceCodec.new()
	sender.reads_device_input = false
	sender.model = _model
	sender.mode = _mode
	sender.send = _record
	assert_bool(sender.open("Default", true)).is_true()
	return sender


func _record(frame: PackedByteArray) -> Error:
	_sent.append(frame)
	return OK
