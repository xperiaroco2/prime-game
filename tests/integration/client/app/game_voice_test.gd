extends GdUnitTestSuite
## Speaking in the game (client/app/game.gd, M5-6; the M5 ADR §1.1, §1.2, §1.7): a host and a
## client, two Game roots over a LoopbackHub on a simulated clock, each with the fake codec, a
## FakeMicrophone and settings in a file of its own. The settings apply at the start; the Esc
## menu's Voice tab shows them and its changes are saved; the talk key counts only without the
## menu; the lobby hints at the tab until a pick; a word into the client's microphone reaches the
## host as a delivered frame; and a session's end leaves the sender with no session. The main
## menu's Voice page (#301), before any session, saves a pick and opens it under the mark as the
## tab does, and its meter runs while nothing is sent. Headless runs open no microphone by
## themselves (VoiceControl.can_capture), so each test opens the fake.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7340
const STEP_USEC := 50000
const MAX_FRAMES := 400
const S := GameFlow.Screen
const PATHS: Array[String] = ["user://game_voice_test_1.cfg", "user://game_voice_test_2.cfg"]

var _hub: LoopbackHub
var _now := 1000000
## The mark as the settings file held it each time the fake microphone opened.
var _marks: Array[String] = []
## The frames a test's own send callable was given.
var _sent_frames := 0


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000
	_marks.clear()
	_sent_frames = 0


func after_test() -> void:
	for path: String in PATHS:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	for bus: StringName in UserSettings.VOLUMES:
		var index := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(index, UserSettings.default_db(bus))
		AudioServer.set_bus_mute(index, false)


## A Game with no command line (a test, a playcheck window) never reads nor writes the player's
## settings file: the developer's own volumes must not reach the buses of a test run.
func test_a_game_with_no_command_line_keeps_its_settings_in_memory() -> void:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.voice_codec = FakeVoiceCodec.new()
	var machine := SubViewport.new()
	machine.own_world_3d = true
	machine.render_target_update_mode = SubViewport.UPDATE_DISABLED
	machine.add_child(game)
	add_child(machine)
	auto_free(game)
	auto_free(machine)
	assert_str(game.settings.path).is_empty()
	await get_tree().process_frame


func test_the_saved_settings_apply_and_the_voice_tab_changes_them() -> void:
	var saved := UserSettings.new(PATHS[0])
	saved.mode = UserSettings.Mode.PUSH_TO_TALK
	saved.threshold = 0.3
	saved.set_volume_db(AudioBuses.MUSIC, -20.0)
	saved.write()
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % PORT], 0)
	assert_object(host.sender().get_parent()).is_same(host)
	assert_int(host.sender().gate.mode).is_equal(VoiceGate.Mode.PUSH_TO_TALK)
	assert_float(host.sender().gate.threshold).is_equal_approx(0.3, 0.0001)
	assert_float(AudioServer.get_bus_volume_db(AudioBuses.index_of(AudioBuses.MUSIC))).is_equal(
		-20.0
	)
	assert_bool(await _until(func() -> bool: return host.screen() == S.LOBBY)).is_true()
	# The lobby hints at the Voice tab until a microphone is picked.
	await get_tree().process_frame
	assert_bool(host.ui.lobby_hud.voice_label.visible).is_true()
	# The Voice tab shows the settings; the talk key does not count under the menu.
	host.open_esc()
	host.ui.esc.press(EscMenuState.Tab.VOICE)
	await get_tree().process_frame
	assert_bool(host.ui.esc.voice.visible).is_true()
	assert_bool(host.sender().listening).is_false()
	var panel := host.ui.esc.voice
	assert_int(panel.mode_button.get_selected_id()).is_equal(UserSettings.Mode.PUSH_TO_TALK)
	assert_bool(panel.microphone_box.visible).is_true()
	# A change in the tab is applied and saved at once.
	panel.mode_picked.emit(UserSettings.Mode.VOICE_ACTIVITY)
	panel.device_picked.emit("Headset Microphone")
	assert_int(host.sender().gate.mode).is_equal(VoiceGate.Mode.VOICE_ACTIVITY)
	var back := UserSettings.new(PATHS[0])
	back.read()
	assert_int(back.mode).is_equal(UserSettings.Mode.VOICE_ACTIVITY)
	assert_str(back.device).is_equal("Headset Microphone")
	await get_tree().process_frame
	assert_bool(host.ui.lobby_hud.voice_label.visible).is_false()
	host.close_esc()
	await get_tree().process_frame
	assert_bool(host.sender().listening).is_true()
	host.leave()
	await get_tree().process_frame


func test_a_word_into_the_clients_microphone_reaches_the_host() -> void:
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % (PORT + 1)], 0)
	var client := _game(["--join=127.0.0.1", "--port=%d" % (PORT + 1)], 1)
	var both := func() -> bool:
		return host.client().model.roster.size() == 2 and client.screen() == S.LOBBY
	assert_bool(await _until(both)).is_true()
	assert_object(client.sender().model).is_same(client.client().model)
	assert_bool(client.sender().may_speak()).is_true()
	_open_fake(client)
	var mic := client.sender().capture.microphone as FakeMicrophone
	# Silence first: nothing is sent.
	mic.capture_chunks(10, 0.0)
	assert_bool(await _until(func() -> bool: return mic.frames_available() == 0)).is_true()
	assert_int(client.sender().sent).is_equal(0)
	mic.capture_chunks(5, 0.5)
	var heard := func() -> bool: return host.voices().received > 0
	assert_bool(await _until(heard)).is_true()
	assert_int(client.sender().sent).is_greater(0)
	# The session ends: the sender speaks into none.
	client.leave()
	assert_bool(await _until(func() -> bool: return client.client() == null)).is_true()
	assert_object(client.sender().model).is_null()
	assert_bool(client.sender().send.is_valid()).is_false()
	host.leave()
	await get_tree().process_frame


func test_the_main_menus_voice_page_saves_a_pick_and_opens_it_under_the_mark() -> void:
	var game := _game([], 0)
	await get_tree().process_frame
	assert_int(game.screen()).is_equal(S.MENU)
	assert_object(game.client()).is_null()
	var mic := game.sender().capture.microphone as FakeMicrophone
	mic.on_open = func() -> void: _marks.append(_saved(0).opening)
	game.voice_control().can_capture = true
	# The menu's Voice entry shows the same panel class as the Esc tab, fed by the game.
	(game.ui.menu.voice_button.face as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := game.ui.menu.voice
	assert_object(game.shown_voice_panel()).is_same(panel)
	assert_bool(panel.is_visible_in_tree()).is_true()
	assert_bool(panel.microphone_box.visible).is_true()
	# The device list was read as the page opened: the fake's microphones (its first the Windows
	# default) are there to pick.
	assert_int(panel.device_button.item_count).is_equal(mic.names.size())
	panel.device_picked.emit("Headset Microphone")
	panel.mode_picked.emit(UserSettings.Mode.PUSH_TO_TALK)
	# Opened as the Esc tab opens it: the mark in the file before the device opened.
	assert_bool(game.sender().is_open()).is_true()
	assert_str(mic.opened_device).is_equal("Headset Microphone")
	assert_array(_marks).contains_exactly(["Headset Microphone"])
	var back := _saved(0)
	assert_str(back.device).is_equal("Headset Microphone")
	assert_str(back.opening).is_equal("Headset Microphone")
	assert_int(back.mode).is_equal(UserSettings.Mode.PUSH_TO_TALK)
	assert_int(game.sender().gate.mode).is_equal(VoiceGate.Mode.PUSH_TO_TALK)
	# The page shows the pick and the mode the next frame.
	await get_tree().process_frame
	assert_int(panel.mode_button.get_selected_id()).is_equal(UserSettings.Mode.PUSH_TO_TALK)
	assert_str(panel.device_button.get_item_text(panel.device_button.selected)).is_equal(
		"Headset Microphone"
	)


func test_the_main_menus_meter_runs_with_no_session_and_nothing_is_sent() -> void:
	var game := _game([], 1)
	await get_tree().process_frame
	_open_fake(game)
	game.ui.menu.open_voice()
	# No ClientSession: the sender has nowhere to send. A send of the test's own catches any frame
	# the gate would let out with no session.
	assert_object(game.client()).is_null()
	assert_bool(game.sender().send.is_valid()).is_false()
	game.sender().send = func(_frame: PackedByteArray) -> Error:
		_sent_frames += 1
		return OK
	var mic := game.sender().capture.microphone as FakeMicrophone
	mic.capture_chunks(10, 0.5)
	var metered := func() -> bool:
		return mic.frames_available() == 0 and game.ui.menu.voice.meter.value > 0.4
	assert_bool(await _until(metered)).is_true()
	assert_float(game.sender().peak).is_equal_approx(0.5, 0.01)
	assert_bool(game.sender().gate.is_open()).is_false()
	assert_int(_sent_frames).is_equal(0)
	assert_int(game.sender().sent).is_equal(0)


## The settings file PATHS[`which`] as written now.
func _saved(which: int) -> UserSettings:
	var saved := UserSettings.new(PATHS[which])
	saved.read()
	return saved


## A Game with the fake codec, a FakeMicrophone and the settings file PATHS[`which`], in its own
## SubViewport world (several Games in one tree, client/CLAUDE.md).
func _game(args: Array[String], which: int) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	game.clock = func() -> int: return _now
	game.make_transport = func() -> NetTransport:
		return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)
	game.voice_codec = FakeVoiceCodec.new()
	game.sender().capture.microphone = FakeMicrophone.new()
	game.device_input = false
	var settings := UserSettings.new(PATHS[which])
	settings.read()
	game.settings = settings
	var machine := SubViewport.new()
	machine.own_world_3d = true
	machine.render_target_update_mode = SubViewport.UPDATE_DISABLED
	machine.add_child(game)
	add_child(machine)
	auto_free(game)
	auto_free(machine)
	return game


## Opens the fake microphone as a windowed run would at its start.
func _open_fake(game: Game) -> void:
	game.voice_control().can_capture = true
	game.voice_control().apply_microphone()
	assert_bool(game.sender().is_open()).is_true()


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()
