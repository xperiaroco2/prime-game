extends GdUnitTestSuite
## Esc's menu as data (client/ui/esc_menu_state.gd, #169; the Toy menu of #491): its tabs per
## screen (Game, Role in the round, Guide, Lobby in the lobby, Settings; the tutorial's three), the
## selected and the remembered tab, the host's question before Leave and Quit, who may change the
## settings.

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
	assert_array(menu.tabs()).is_equal([TAB.GAME, TAB.GUIDE, TAB.LOBBY, TAB.SETTINGS])
	assert_int(menu.selected).is_equal(TAB.LOBBY)
	menu.close()
	assert_bool(menu.is_open).is_false()


func test_the_round_has_the_role_tab_and_opens_on_game() -> void:
	var menu := EscMenuState.new()
	menu.open(S.ROUND, null, false)
	assert_array(menu.tabs()).is_equal([TAB.GAME, TAB.ROLE, TAB.GUIDE, TAB.SETTINGS])
	assert_int(menu.selected).is_equal(TAB.GAME)
	# Loading, the pregame and the end: no Role, no Lobby.
	for screen: S in [S.LOADING, S.PREGAME, S.END, S.CONNECTING]:
		menu.open(screen, null, false)
		assert_array(menu.tabs()).is_equal([TAB.GAME, TAB.GUIDE, TAB.SETTINGS])
		assert_int(menu.selected).is_equal(TAB.GAME)


func test_the_tutorial_shows_game_guide_and_settings_and_leaves_at_once() -> void:
	var menu := EscMenuState.new()
	menu.tutorial = true
	for screen: S in [S.LOBBY, S.ROUND, S.LOADING]:
		menu.open(screen, null, true)
		assert_array(menu.tabs()).is_equal([TAB.GAME, TAB.GUIDE, TAB.SETTINGS])
		assert_int(menu.selected).is_equal(TAB.GAME)
	# Even when its window hosts: no question.
	assert_int(menu.press_leave()).is_equal(ACT.LEAVE)
	assert_bool(menu.asking()).is_false()
	assert_int(menu.press_quit()).is_equal(ACT.QUIT)


func test_a_tab_that_goes_away_gives_way_to_the_default() -> void:
	var menu := EscMenuState.new()
	var model := Preview.fake_model(_mode, true)
	menu.open(S.LOBBY, model, true)
	menu.press(TAB.LOBBY)
	assert_int(menu.selected).is_equal(TAB.LOBBY)
	menu.follow(S.ROUND, model, true)
	assert_bool(menu.has_tab(TAB.LOBBY)).is_false()
	assert_int(menu.selected).is_equal(TAB.GAME)
	# A tab the screen lacks cannot be pressed.
	menu.press(TAB.LOBBY)
	assert_int(menu.selected).is_equal(TAB.GAME)


func test_the_last_tab_is_kept_on_the_same_kind_of_screen() -> void:
	var menu := EscMenuState.new()
	menu.open(S.ROUND, null, false)
	menu.press(TAB.SETTINGS)
	menu.close()
	menu.open(S.ROUND, null, false)
	assert_int(menu.selected).is_equal(TAB.SETTINGS)
	menu.press(TAB.ROLE)
	menu.close()
	# The end screen has no Role tab: the default.
	menu.open(S.END, null, false)
	assert_int(menu.selected).is_equal(TAB.GAME)
	# Back in the lobby, a tab chosen in the round does not carry over.
	menu.open(S.LOBBY, null, false)
	assert_int(menu.selected).is_equal(TAB.LOBBY)
	menu.press(TAB.GUIDE)
	menu.open(S.LOBBY, null, false)
	assert_int(menu.selected).is_equal(TAB.GUIDE)


func test_a_players_leave_and_quit_act_at_once_and_resume_closes() -> void:
	var menu := EscMenuState.new()
	menu.open(S.ROUND, null, false)
	assert_int(menu.press_leave()).is_equal(ACT.LEAVE)
	assert_int(menu.press_quit()).is_equal(ACT.QUIT)
	assert_bool(menu.asking()).is_false()
	assert_int(menu.resume()).is_equal(ACT.RESUME)
	assert_bool(menu.is_open).is_false()
	# Closed, nothing acts.
	assert_int(menu.press_leave()).is_equal(ACT.NONE)
	assert_int(menu.resume()).is_equal(ACT.NONE)


func test_the_hosts_leave_and_quit_ask_first() -> void:
	var menu := EscMenuState.new()
	menu.open(S.ROUND, null, true)
	assert_int(menu.press_leave()).is_equal(ACT.NONE)
	assert_bool(menu.asking()).is_true()
	assert_int(menu.question).is_equal(ACT.LEAVE)
	# Under the question the tabs and the other buttons do nothing.
	assert_int(menu.press_quit()).is_equal(ACT.NONE)
	menu.press(TAB.SETTINGS)
	assert_int(menu.selected).is_equal(TAB.GAME)
	menu.cancel()
	assert_bool(menu.asking()).is_false()
	assert_bool(menu.is_open).is_true()
	assert_int(menu.confirm()).is_equal(ACT.NONE)
	assert_int(menu.press_quit()).is_equal(ACT.NONE)
	assert_int(menu.question).is_equal(ACT.QUIT)
	assert_int(menu.confirm()).is_equal(ACT.QUIT)
	assert_bool(menu.asking()).is_false()
	# Closing drops an open question; opening never starts with one.
	menu.press_leave()
	menu.close()
	assert_bool(menu.asking()).is_false()
	menu.open(S.ROUND, null, true)
	assert_bool(menu.asking()).is_false()


func test_closing_the_window_asks_the_host_to_quit_on_the_game_tab() -> void:
	var menu := EscMenuState.new()
	menu.open(S.LOBBY, null, true)
	menu.press(TAB.SETTINGS)
	menu.ask_quit(S.LOBBY, null)
	assert_bool(menu.is_open).is_true()
	assert_int(menu.selected).is_equal(TAB.GAME)
	assert_int(menu.question).is_equal(ACT.QUIT)
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
