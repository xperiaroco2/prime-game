extends GdUnitTestSuite
## SfxSet (#525): every sound id's files exist and load (in CI the LFS stand-in), each id is one
## AudioStreamRandomizer of them with a small random pitch and volume, every surface has its five
## footsteps, and an id whose files do not load has no stream (nothing plays).


func test_every_file_of_every_id_exists_and_loads() -> void:
	for id: StringName in SfxSet.ids():
		var paths := SfxSet.paths_for(id)
		assert_int(paths.size()).is_greater(0)
		for path: String in paths:
			assert_str(path).starts_with("res://assets/audio/kenney_")
			assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
			assert_object(load(path) as AudioStreamOggVorbis).is_not_null()


func test_each_id_is_one_randomizer_of_its_files() -> void:
	var sfx := SfxSet.new()
	for id: StringName in SfxSet.ids():
		var stream := sfx.stream_for(id)
		assert_object(stream).is_not_null()
		assert_object(sfx.stream_for(id)).is_same(stream)
		assert_int(stream.streams_count).is_equal(SfxSet.paths_for(id).size())
		assert_float(stream.random_pitch).is_greater(1.0)
		assert_float(stream.random_volume_offset_db).is_greater(0.0)
		assert_int(stream.playback_mode).is_equal(AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS)


func test_every_surface_has_its_five_footsteps() -> void:
	for surface: StringName in FootstepSurface.SURFACES:
		var paths := SfxSet.paths_for(SfxSet.footstep(surface))
		assert_int(paths.size()).is_equal(SfxSet.FOOTSTEP_VARIANTS)
		for path: String in paths:
			assert_str(path).contains("/footstep_%s_" % surface)


func test_an_id_with_no_file_that_loads_has_no_stream() -> void:
	assert_int(SfxSet.paths_for(&"door_open").size()).is_equal(0)
	assert_object(SfxSet.new().stream_for(&"door_open")).is_null()
	var missing := PackedStringArray(["res://assets/audio/nothing/here.ogg"])
	var stream := SfxSet.randomizer(missing)
	assert_int(stream.streams_count).is_equal(0)
	assert_int(stream.playback_mode).is_equal(AudioStreamRandomizer.PLAYBACK_RANDOM)
