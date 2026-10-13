extends GdUnitTestSuite
## SoundStopper (#891): stop() stops every sound player under a root, of each kind, and keeps only a
## weak reference to each playback it stopped (one not playing gives none); held() says whether
## any of them is not freed yet, and released() of none returns at once.


func test_stop_stops_every_kind_of_player_under_the_root() -> void:
	var root: Node = auto_free(Node.new())
	var flat := AudioStreamPlayer.new()
	var deep := Node.new()
	var three := AudioStreamPlayer3D.new()
	var two := AudioStreamPlayer2D.new()
	root.add_child(flat)
	root.add_child(deep)
	deep.add_child(three)
	deep.add_child(two)
	add_child(root)
	for player: Node in [flat, three, two]:
		player.set(&"stream", _tone())
		player.call(&"play")
	assert_bool(flat.playing).is_true()
	var playbacks := SoundStopper.stop(root)
	assert_int(playbacks.size()).is_equal(3)
	assert_bool(flat.playing).is_false()
	assert_bool(three.playing).is_false()
	assert_bool(two.playing).is_false()
	assert_bool(flat.has_stream_playback()).is_false()


func test_a_player_not_playing_gives_no_playback() -> void:
	var root: Node = auto_free(Node.new())
	var idle := AudioStreamPlayer.new()
	idle.stream = _tone()
	root.add_child(idle)
	add_child(root)
	assert_int(SoundStopper.stop(root).size()).is_equal(0)


func test_held_while_a_playback_lives_and_not_once_freed() -> void:
	var playback: AudioStreamPlayback = _tone().instantiate_playback()
	var playbacks: Array[WeakRef] = [weakref(playback) as WeakRef]
	assert_bool(SoundStopper.held(playbacks)).is_true()
	playback = null
	assert_bool(SoundStopper.held(playbacks)).is_false()


func test_released_of_none_returns_at_once() -> void:
	var playbacks: Array[WeakRef] = []
	var frame := Engine.get_process_frames()
	await SoundStopper.released(get_tree(), playbacks)
	assert_int(Engine.get_process_frames()).is_equal(frame)


## A second of 16-bit mono silence.
func _tone() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(22050 * 2)
	stream.data = data
	return stream
