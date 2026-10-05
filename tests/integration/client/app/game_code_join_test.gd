extends GdUnitTestSuite
## Joining with a code in the game (client/app/game.gd; the M6 design §2.3, §3): a Game hosting a
## room with a code over WebRTC, its signalling served here (--signal=lan, LanSignalling on a free
## port of 127.0.0.1), a Game joining with that code; and a code no room holds. The lobby shows the
## code to both, Copy holds it, and no screen names the other side's address. Real WebRTC on
## 127.0.0.1, so the waits are bounded in wall-clock time, as webrtc_transport_test's.

const GAME := preload("res://client/app/game.tscn")
const CODE := "K7M2QX"
const MAX_WAIT_MS := 15000


func test_a_code_joiner_reaches_the_lobby_and_both_see_the_code() -> void:
	var host := _lan_host()
	assert_bool(host.host_with_code(0, LaunchOptions.LOCALHOST)).is_true()
	var service := "ws://127.0.0.1:%d" % host.room().lan.port()
	assert_bool(await _until(func() -> bool: return host.room().code() == CODE)).is_true()
	var joiner := _game(["--signal=%s" % service])
	joiner.ui.menu.code_edit.text = "k7m-2qx"
	joiner.ui.menu.code_join_requested.emit(joiner.ui.menu.code_edit.text)
	assert_object(joiner.client()).is_not_null()
	assert_str(joiner.ui.connecting.label.text).is_equal("Joining the game with code K7M2QX")
	var in_lobby := func() -> bool: return joiner.screen() == GameFlow.Screen.LOBBY
	assert_bool(await _until(in_lobby)).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	for game: Game in [host, joiner]:
		assert_str(game.ui.lobby_hud.code_label.text).is_equal("Code: K7M2QX")
		assert_bool(game.ui.lobby_hud.code_label.visible).is_true()
		assert_bool(game.ui.esc.lobby.copy_button.visible).is_true()
		for text: String in _texts(game.ui):
			assert_str(text).override_failure_message(text).not_contains("127.0.0.1")
	joiner.leave()
	host.leave()
	await get_tree().process_frame


func test_a_found_of_another_version_ends_the_join_before_any_offer() -> void:
	var service := LanSignalling.new([], func() -> String: return CODE)
	assert_int(service.listen(0, LaunchOptions.LOCALHOST)).is_equal(OK)
	var url := "ws://127.0.0.1:%d" % service.port()
	var other := WebRtcTransport.new(NetKindTable.game())
	other.signal_url = url
	other.local_candidates = true
	other.room_protocol = WireSchema.VERSION + 1
	assert_int(other.host(0, 4)).is_equal(OK)
	var room_open := func() -> bool:
		service.poll()
		other.poll()
		return other.room_code() == CODE
	assert_bool(await _until(room_open)).is_true()
	var joiner := _game(["--signal=%s" % url])
	joiner.join_code(CODE)
	var ended := func() -> bool:
		service.poll()
		other.poll()
		return joiner.client() == null
	assert_bool(await _until(ended)).is_true()
	assert_str(String(joiner.last_reason)).is_equal("wrong_version")
	assert_str(joiner.ui.menu.reason_label.text).contains(
		"the host runs protocol %d, this game %d" % [WireSchema.VERSION + 1, WireSchema.VERSION]
	)
	other.close()
	service.stop()


func test_a_host_without_a_code_service_says_to_host_direct() -> void:
	var host := _game(["--signal="])
	assert_bool(host.host_with_code(0, LaunchOptions.LOCALHOST)).is_false()
	assert_str(host.ui.menu.reason_label.text).contains("use Host Direct")


func test_the_host_lobby_says_when_its_code_service_is_gone() -> void:
	var host := _lan_host()
	assert_bool(host.host_with_code(0, LaunchOptions.LOCALHOST)).is_true()
	assert_bool(await _until(func() -> bool: return host.room().code() == CODE)).is_true()
	host.room().lan.stop()
	var gone := func() -> bool: return host.ui.lobby_hud.code_label.text == JoinProgress.CODE_GONE
	assert_bool(await _until(gone)).is_true()
	host.leave()
	await get_tree().process_frame


func test_a_code_no_room_holds_returns_to_the_menu_and_keeps_the_code() -> void:
	var service := LanSignalling.new()
	assert_int(service.listen(0, LaunchOptions.LOCALHOST)).is_equal(OK)
	var joiner := _game(["--signal=ws://127.0.0.1:%d" % service.port()])
	joiner.ui.menu.code_edit.text = "ABCDEF"
	joiner.join_code(joiner.ui.menu.code_edit.text)
	var back := func() -> bool:
		service.poll()
		return joiner.client() == null
	assert_bool(await _until(back)).is_true()
	assert_str(String(joiner.last_reason)).is_equal(String(NetTransport.JOIN_NO_ROOM))
	assert_str(joiner.ui.menu.reason_label.text).contains("no game has that code")
	assert_str(joiner.ui.menu.code_edit.text).is_equal("ABCDEF")
	service.stop()


func test_a_mistyped_code_stays_on_the_menu_and_says_why() -> void:
	var joiner := _game([])
	joiner.join_code("K7M2Q0")
	assert_object(joiner.client()).is_null()
	assert_str(joiner.ui.menu.reason_label.text).contains("without 0, O, 1, I or L")


func test_a_code_join_without_a_service_says_to_use_direct() -> void:
	var joiner := _game(["--signal="])
	joiner.join_code("K7M2QX")
	assert_object(joiner.client()).is_null()
	assert_str(String(joiner.last_reason)).is_equal(String(NetTransport.JOIN_SERVICE_UNREACHABLE))
	assert_str(joiner.ui.menu.reason_label.text).contains("Direct (LAN or VPN)")


## A Game set to host a room with CODE whose signalling it serves (as --code --signal=lan
## --room=CODE), on a free port: host_with_code(0, ...) takes one the command line cannot.
func _lan_host() -> Game:
	var host := _game(["--no-replay"])
	host.options.signal_url = LaunchOptions.LAN_SIGNAL
	host.options.room = CODE
	return host


func _game(args: Array[String]) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.launch_args = PackedStringArray(args)
	var machine := SubViewport.new()
	machine.own_world_3d = true
	machine.render_target_update_mode = SubViewport.UPDATE_DISABLED
	machine.add_child(game)
	add_child(machine)
	auto_free(game)
	auto_free(machine)
	return game


## Every Label's text under `ui`.
func _texts(ui: Node) -> Array[String]:
	var texts: Array[String] = []
	for node: Node in ui.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return texts


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()
