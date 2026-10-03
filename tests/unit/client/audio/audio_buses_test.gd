extends GdUnitTestSuite
## The buses (AudioBuses; the M5 ADR §1.7, E43 (a), D15): Voice, Effects and Music, made in code,
## each sending to Master at its default volume, made once however often the game starts; the
## voices play on Voice, the world sounds on Effects and the lift music on Music.


func test_the_three_buses_send_to_master_at_their_defaults() -> void:
	AudioBuses.ensure()
	for bus: StringName in [AudioBuses.VOICE, AudioBuses.EFFECTS, AudioBuses.MUSIC]:
		var index := AudioBuses.index_of(bus)
		assert_int(index).is_greater(0)
		assert_str(String(AudioServer.get_bus_send(index))).is_equal(String(AudioBuses.MASTER))
	assert_float(AudioServer.get_bus_volume_db(AudioBuses.index_of(AudioBuses.VOICE))).is_equal(0.0)
	assert_float(AudioServer.get_bus_volume_db(AudioBuses.index_of(AudioBuses.EFFECTS))).is_equal(
		-6.0
	)
	assert_float(AudioServer.get_bus_volume_db(AudioBuses.index_of(AudioBuses.MUSIC))).is_equal(
		-14.0
	)


func test_ensure_makes_each_bus_once_and_keeps_a_moved_volume() -> void:
	AudioBuses.ensure()
	var count := AudioServer.bus_count
	var music := AudioBuses.index_of(AudioBuses.MUSIC)
	AudioServer.set_bus_volume_db(music, -3.0)
	AudioBuses.ensure()
	assert_int(AudioServer.bus_count).is_equal(count)
	assert_float(AudioServer.get_bus_volume_db(music)).is_equal(-3.0)
	AudioServer.set_bus_volume_db(music, AudioBuses.DEFAULT_DB[AudioBuses.MUSIC])


func test_each_sound_plays_on_its_bus() -> void:
	AudioBuses.ensure()
	assert_str(String(AudioBuses.VOICE)).is_equal(String(VoiceSpeaker.BUS))
	var speaker: VoiceSpeaker = auto_free(VoiceSpeaker.new(FakeVoiceCodec.new()))
	assert_str(String(speaker.bus)).is_equal("Voice")
	var music: LiftMusic = auto_free(LiftMusic.new())
	assert_str(String(music.bus)).is_equal("Music")
	# The music's quiet is the bus's default now, not the player's.
	assert_float(music.volume_db).is_equal(0.0)
	var model := ClientModel.new(FixtureBaseMode.mode())
	var sounds: WorldSounds = auto_free(WorldSounds.new())
	add_child(sounds)
	sounds.model = model
	sounds.listener = func() -> Variant: return Vector3.ZERO
	sounds.on_event(&"ItemPlaced", {"item": 5, "position": Vector3(0, 0, 2), "cause": &"put_down"})
	var players := sounds.find_children("*", "AudioStreamPlayer3D", false, false)
	assert_int(players.size()).is_equal(1)
	assert_str(String((players[0] as AudioStreamPlayer3D).bus)).is_equal("Effects")
