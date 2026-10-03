extends GdUnitTestSuite
## Esc's menu as data (client/ui/esc_menu_state.gd, #169): its tabs per screen, the selected tab,
## open or closed, the host's questions before Leave and Quit, who may change the settings, and the
## Voice tab in every screen (M5-6).

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const S := GameFlow.Screen
const TAB := EscMenuState.Tab
const ACT := EscMenuState.Action

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_it_starts_closed_and_opens_on_the_lobby_tab_in_the_lobby() -> void:
	var menu := EscMenuState.new()
	assert_bool(menu.is_open).is_false()
	menu.open(S.LOBBY, Preview.fake_model(_mode, false), false)
	assert_bool(menu.is_open).is_true()
	assert_array(menu.tabs()).is_equal([TAB.RESUME, TAB.LOBBY, TAB.VOICE, TAB.LEAVE, TAB.QUIT])
	assert_int(menu.selected).is_equal(TAB.LOBBY)
	menu.close()
	assert_bool(menu.is_open).is_false()


func test_outside_the_lobby_there_is_no_lobby_tab_and_it_opens_on_resume() -> void:
	for screen: S in [S.CONNECTING, S.LOADING, S.ROUND, S.END]:
		var menu := EscMenuState.new()
		menu.open(screen, null, true)
		assert_array(menu.tabs()).is_equal([TAB.RESUME, TAB.VOICE, TAB.LEAVE, TAB.QUIT])
		assert_int(menu.selected).is_equal(TAB.RESUME)
		assert_bool(menu.has_tab(TAB.LOBBY)).is_false()
		assert_int(menu.press(TAB.LOBBY)).is_equal(ACT.NONE)
		assert_int(menu.selected).is_equal(TAB.RESUME)


func test_the_voice_tab_is_in_every_screen_and_stays_selected_across_them() -> void:
	# The M5 ADR §1.7: the microphone, the mode and the volumes, wherever Esc opens.
	var model := Preview.fake_model(_mode, true)
	for screen: S in [S.CONNECTING, S.LOBBY, S.LOADING, S.ROUND, S.END]:
		for hosting: bool in [false, true]:
			var menu := EscMenuState.new()
			menu.open(screen, model, hosting)
			assert_bool(menu.has_tab(TAB.VOICE)).is_true()
			# A press selects it and acts on nothing, also on the host.
			assert_int(menu.press(TAB.VOICE)).is_equal(ACT.NONE)
			assert_int(menu.selected).is_equal(TAB.VOICE)
			assert_bool(menu.asking()).is_false()
			assert_bool(menu.is_open).is_true()
	var menu := EscMenuState.new()
	menu.open(S.LOBBY, model, true)
	menu.press(TAB.VOICE)
	menu.follow(S.LOADING, model, true)
	menu.follow(S.ROUND, model, true)
	assert_int(menu.selected).is_equal(TAB.VOICE)


func test_the_lobby_tab_gives_way_when_the_round_starts_under_the_open_menu() -> void:
	var menu := EscMenuState.new()
	var model := Preview.fake_model(_mode, true)
	menu.open(S.LOBBY, model, true)
	assert_int(menu.selected).is_equal(TAB.LOBBY)
	menu.follow(S.LOADING, model, true)
	assert_bool(menu.is_open).is_true()
	assert_int(menu.selected).is_equal(TAB.RESUME)


func test_resume_closes_the_menu() -> void:
	var menu := EscMenuState.new()
	menu.open(S.ROUND, null, false)
	assert_int(menu.press(TAB.RESUME)).is_equal(ACT.RESUME)
	assert_bool(menu.is_open).is_false()
	# A closed menu does nothing.
	assert_int(menu.press(TAB.LEAVE)).is_equal(ACT.NONE)


func test_a_clients_leave_and_quit_act_at_once() -> void:
	var menu := EscMenuState.new()
	menu.open(S.LOBBY, Preview.fake_model(_mode, false), false)
	assert_int(menu.press(TAB.LEAVE)).is_equal(ACT.LEAVE)
	assert_int(menu.press(TAB.QUIT)).is_equal(ACT.QUIT)
	assert_bool(menu.asking()).is_false()


func test_the_hosts_leave_and_quit_ask_first() -> void:
	var menu := EscMenuState.new()
	menu.open(S.LOBBY, Preview.fake_model(_mode, true), true)
	assert_int(menu.press(TAB.LEAVE)).is_equal(ACT.NONE)
	assert_int(menu.selected).is_equal(TAB.LEAVE)
	assert_bool(menu.asking()).is_true()
	menu.cancel()
	assert_int(menu.selected).is_equal(TAB.LOBBY)
	assert_bool(menu.asking()).is_false()
	assert_int(menu.confirm()).is_equal(ACT.NONE)
	assert_int(menu.press(TAB.QUIT)).is_equal(ACT.NONE)
	assert_int(menu.confirm()).is_equal(ACT.QUIT)
	menu.press(TAB.LEAVE)
	assert_int(menu.confirm()).is_equal(ACT.LEAVE)


func test_closing_the_hosts_window_opens_the_quit_question() -> void:
	var menu := EscMenuState.new()
	menu.ask_quit(S.ROUND, null)
	assert_bool(menu.is_open).is_true()
	assert_int(menu.selected).is_equal(TAB.QUIT)
	assert_bool(menu.asking()).is_true()
	assert_int(menu.confirm()).is_equal(ACT.QUIT)


func test_only_the_host_changes_the_settings_and_only_in_the_lobby_phase() -> void:
	var menu := EscMenuState.new()
	var host := Preview.fake_model(_mode, true)
	menu.open(S.LOBBY, host, true)
	assert_bool(menu.may_change_settings).is_true()
	# Another player reads them.
	menu.open(S.LOBBY, Preview.fake_model(_mode, false), false)
	assert_bool(menu.may_change_settings).is_false()
	# The countdown accepts no ChangeSettings: the host reads them too.
	host.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": 160})
	menu.open(S.LOBBY, host, true)
	assert_bool(menu.has_tab(TAB.LOBBY)).is_true()
	assert_bool(menu.may_change_settings).is_false()
	# No model yet (connecting): nobody changes anything.
	menu.open(S.CONNECTING, null, true)
	assert_bool(menu.may_change_settings).is_false()
