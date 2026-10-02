extends GdUnitTestSuite
## The codec boundary (E34, the M5 ADR §1.3): TwoVoipCodec without its addon classes is
## unavailable and hands out nothing, on any machine; and the fake codec that headless tests use in
## its place encodes 20 ms as 160 µ-law bytes and plays them through a real AudioStreamPlayer3D.
## No test here loads the addon.

const MISSING := &"NoSuchVoiceAddonClass"


func test_twovoip_codec_names_twovoip_classes_by_default() -> void:
	assert_str(String(TwoVoipCodec.ENCODER_CLASS)).is_equal("TwovoipOpusEncoder")
	assert_str(String(TwoVoipCodec.STREAM_CLASS)).is_equal("AudioStreamOpus")
	assert_str(String(TwoVoipCodec.PLAYBACK_CLASS)).is_equal("AudioStreamPlaybackOpus")
	# Available exactly where the addon's classes are registered.
	var installed := ClassDB.class_exists(TwoVoipCodec.ENCODER_CLASS)
	assert_bool(TwoVoipCodec.new().available()).is_equal(installed)


func test_a_missing_encoder_class_makes_the_codec_unavailable() -> void:
	var codec := TwoVoipCodec.new(MISSING)
	assert_bool(codec.available()).is_false()
	assert_object(codec.new_encoder()).is_null()
	assert_object(codec.new_stream()).is_null()


func test_a_missing_stream_or_playback_class_makes_the_codec_unavailable() -> void:
	# Engine classes stand in for the addon's encoder and stream, so only the named one is absent.
	assert_bool(TwoVoipCodec.new(&"RefCounted", MISSING).available()).is_false()
	var no_playback := TwoVoipCodec.new(&"RefCounted", &"AudioStreamGenerator", MISSING)
	assert_bool(no_playback.available()).is_false()
	assert_object(no_playback.new_stream()).is_null()


func test_an_unavailable_codec_gives_no_playback_for_a_player() -> void:
	var player := _player(AudioStreamGenerator.new())
	assert_object(TwoVoipCodec.new(MISSING).playback_of(player)).is_null()
	assert_object(VoiceCodec.new().playback_of(player)).is_null()


func test_the_base_codec_is_never_available() -> void:
	var codec := VoiceCodec.new()
	assert_bool(codec.available()).is_false()
	assert_object(codec.new_encoder()).is_null()
	assert_object(codec.new_stream()).is_null()
	assert_str(VoiceEncoder.new().start(48000, true)).is_not_empty()


func test_the_twovoip_encoder_reports_an_object_without_the_addons_constants() -> void:
	var encoder := TwoVoipEncoder.new(RefCounted.new(), &"RefCounted")
	assert_str(encoder.start(48000, true)).contains("DENOISER_RNNOISE")
	assert_str(encoder.start(48000, false)).contains("DENOISER_DISABLED")
	assert_int(encoder.chunk_frames()).is_equal(0)
	assert_array(Array(encoder.encode(PackedVector2Array()))).is_empty()


func test_the_twovoip_playback_holds_nothing_of_another_class() -> void:
	var player := _player(AudioStreamGenerator.new())
	var playback := TwoVoipPlayback.new(player, MISSING)
	assert_bool(playback.bound()).is_false()
	assert_int(playback.queued_frames()).is_equal(0)
	assert_int(playback.free_frames()).is_equal(0)
	assert_int(playback.sample_rate()).is_equal(48000)


func test_the_fake_encoder_makes_160_bytes_of_20_ms() -> void:
	var encoder := FakeVoiceCodec.new().new_encoder()
	assert_str(encoder.start(44123, true)).is_not_empty()
	assert_str(encoder.start(44100, false)).is_empty()
	assert_int(encoder.chunk_frames()).is_equal(882)
	assert_str(encoder.start(48000, true)).is_empty()
	assert_int(encoder.chunk_frames()).is_equal(960)
	var chunk := PackedVector2Array()
	chunk.resize(960)
	assert_int(encoder.encode(chunk).size()).is_equal(FakeVoiceCodec.FRAME_SAMPLES)
	chunk.resize(959)
	assert_array(Array(encoder.encode(chunk))).is_empty()


func test_mu_law_round_trips_within_its_error() -> void:
	var worst := 0.0
	for i: int in 201:
		var v := -1.0 + i * 0.01
		var back := FakeMuLaw.decode_sample(FakeMuLaw.encode_sample(v))
		worst = maxf(worst, absf(back - v))
	assert_float(worst).is_less(0.03)
	assert_float(absf(FakeMuLaw.decode_sample(FakeMuLaw.encode_sample(0.0)))).is_less(0.001)


func test_the_fake_codec_unavailable_hands_out_nothing() -> void:
	var codec := FakeVoiceCodec.new()
	codec.is_available = false
	assert_object(codec.new_encoder()).is_null()
	assert_object(codec.new_stream()).is_null()


func test_the_fake_playback_queues_while_held_and_flush_empties_it() -> void:
	var codec := FakeVoiceCodec.new()
	var player := _player(codec.new_stream())
	var playback := codec.playback_of(player)
	assert_object(playback).is_not_null()
	assert_int(playback.sample_rate()).is_equal(FakeVoiceCodec.RATE)
	assert_int(playback.queued_frames()).is_equal(0)
	var room := playback.free_frames()
	assert_int(room).is_greater_equal(10 * FakeVoiceCodec.FRAME_SAMPLES)
	var frame := PackedByteArray()
	frame.resize(FakeVoiceCodec.FRAME_SAMPLES)
	frame.fill(FakeMuLaw.encode_sample(0.25))
	for i: int in 3:
		playback.push(frame, false)
	playback.push(frame, true)
	assert_int(playback.queued_frames()).is_equal(4 * FakeVoiceCodec.FRAME_SAMPLES)
	assert_int(playback.queued_usec()).is_equal(80000)
	assert_int(playback.free_frames()).is_equal(room - 4 * FakeVoiceCodec.FRAME_SAMPLES)
	assert_int((playback as FakeVoicePlayback).concealed).is_equal(1)
	playback.flush()
	assert_int(playback.queued_frames()).is_equal(0)
	assert_bool((playback as FakeVoicePlayback).running).is_false()


func test_the_fake_playback_hands_its_queue_to_the_player_when_running() -> void:
	var codec := FakeVoiceCodec.new()
	var player := _player(codec.new_stream())
	var playback := codec.playback_of(player)
	var frame := PackedByteArray()
	frame.resize(FakeVoiceCodec.FRAME_SAMPLES)
	frame.fill(FakeMuLaw.encode_sample(0.25))
	playback.push(frame, false)
	playback.push(frame, false)
	playback.set_running(true)
	# Now in the generator, which the audio driver may already be mixing.
	assert_int(playback.queued_frames()).is_less_equal(2 * FakeVoiceCodec.FRAME_SAMPLES)
	assert_bool(player.playing).is_true()
	playback.flush()
	assert_int(playback.queued_frames()).is_equal(0)


func test_the_fake_codec_plays_only_its_own_stream() -> void:
	var player := _player(AudioStreamWAV.new())
	assert_object(FakeVoiceCodec.new().playback_of(player)).is_null()


func test_no_playback_for_a_player_outside_the_tree() -> void:
	var codec := FakeVoiceCodec.new()
	var player: AudioStreamPlayer3D = auto_free(AudioStreamPlayer3D.new())
	player.stream = codec.new_stream()
	assert_object(codec.playback_of(player)).is_null()
	assert_object(TwoVoipCodec.new().playback_of(player)).is_null()


func _player(stream: AudioStream) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = auto_free(AudioStreamPlayer3D.new())
	player.stream = stream
	add_child(player)
	return player
