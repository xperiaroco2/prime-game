extends GdUnitTestSuite
## The flipper keys (#1400, ARCHITECTURE §4.7.63): the held state goes as one Flippers intent per
## change, only while the own player is seated; the Esc menu (listening off) and a lost focus
## release a held flipper; the gap defers a change and never drops one; a host state left
## different from the last sent is sent again after RECONCILE_MSEC; the actions read are the
## rebindable ones.

const OWN := 2

var _keys: PinballKeys
var _model: ClientModel
var _sent: Array[Dictionary] = []
var _focus := true


func before_test() -> void:
	_sent.clear()
	_focus = true
	_model = ClientModel.new(FixturePinball.mode())
	_model.own_peer = OWN
	_model.pinball.player = OWN
	_keys = auto_free(PinballKeys.new())
	_keys.model = _model
	_keys.listening = true
	_keys.focused = func() -> bool: return _focus
	_keys.send = func(intent: StringName, args: Dictionary) -> int:
		assert_str(String(intent)).is_equal(String(Intents.FLIPPERS))
		_sent.append(args)
		return _sent.size()


func test_a_press_and_a_release_each_send_the_held_state() -> void:
	_keys.update(true, false, 1000)
	_keys.update(true, false, 1100)
	_keys.update(false, false, 1200)
	assert_array(_sent).is_equal([{"left": true, "right": false}, {"left": false, "right": false}])


func test_the_same_state_sends_nothing() -> void:
	_keys.update(false, false, 1000)
	_keys.update(false, false, 2000)
	assert_array(_sent).is_empty()


func test_nothing_is_sent_while_another_player_or_nobody_is_seated() -> void:
	_model.pinball.player = 3
	_keys.update(true, true, 1000)
	_model.pinball.player = -1
	_keys.update(true, true, 1100)
	assert_array(_sent).is_empty()


func test_the_esc_menu_releases_a_held_flipper() -> void:
	_keys.update(true, true, 1000)
	_keys.listening = false
	# The keys are still down under the menu: the release goes all the same (no stuck flipper).
	_keys.update(true, true, 1100)
	assert_array(_sent).is_equal([{"left": true, "right": true}, {"left": false, "right": false}])


func test_a_lost_focus_releases_a_held_flipper() -> void:
	_keys.update(false, true, 1000)
	_focus = false
	_keys.update(false, true, 1100)
	assert_array(_sent).is_equal([{"left": false, "right": true}, {"left": false, "right": false}])


func test_a_tap_inside_the_gap_sends_both_edges_in_order() -> void:
	_keys.update(true, false, 1000)
	_keys.update(false, false, 1010)
	assert_int(_sent.size()).is_equal(1)
	_keys.update(false, false, 1000 + PinballKeys.SEND_GAP_MSEC - 1)
	assert_int(_sent.size()).is_equal(1)
	_keys.update(false, false, 1000 + PinballKeys.SEND_GAP_MSEC)
	assert_array(_sent).is_equal([{"left": true, "right": false}, {"left": false, "right": false}])


func test_changes_inside_one_gap_merge_into_the_newest_state() -> void:
	_keys.update(true, false, 1000)
	_keys.update(false, false, 1010)
	_keys.update(false, true, 1020)
	_keys.update(true, true, 1030)
	_keys.update(true, true, 1060)
	_keys.update(true, true, 1120)
	(
		assert_array(_sent)
		. is_equal(
			[
				{"left": true, "right": false},
				{"left": false, "right": false},
				{"left": true, "right": true},
			]
		)
	)


func test_a_host_state_left_behind_is_sent_again_after_the_reconcile_time() -> void:
	_keys.update(true, false, 1000)
	# The host's PinballState still shows the flipper down (in flight, or lost).
	_keys.update(true, false, 1000 + PinballKeys.RECONCILE_MSEC - 1)
	assert_int(_sent.size()).is_equal(1)
	_keys.update(true, false, 1000 + PinballKeys.RECONCILE_MSEC)
	assert_int(_sent.size()).is_equal(2)
	assert_dict(_sent[1]).is_equal({"left": true, "right": false})
	# Once the host has it, nothing more.
	_model.pinball.left = true
	_keys.update(true, false, 3000)
	assert_int(_sent.size()).is_equal(2)


func test_a_new_seat_starts_from_the_host_s_state() -> void:
	_model.pinball.player = -1
	_keys.update(false, false, 1000)
	_model.pinball.player = OWN
	_keys.update(false, false, 1100)
	assert_array(_sent).is_empty()


func test_the_physics_step_reads_the_lobby_actions_controls_keeps_free() -> void:
	# No Settings row until the deck has `control.flipper_*` (#150): Controls.UNLISTED keeps Z and
	# Slash for them in the lobby, so no lobby action is bound onto a flipper.
	assert_bool(InputMap.has_action(PinballKeys.LEFT)).is_true()
	assert_bool(InputMap.has_action(PinballKeys.RIGHT)).is_true()
	(
		assert_bool(Controls.UNLISTED.get(PinballKeys.LEFT, 0) == Controls.ControlContext.LOBBY)
		. is_true()
	)
	(
		assert_bool(Controls.UNLISTED.get(PinballKeys.RIGHT, 0) == Controls.ControlContext.LOBBY)
		. is_true()
	)


func test_a_rebound_key_is_the_one_the_physics_step_reads() -> void:
	var saved := InputMap.action_get_events(PinballKeys.LEFT)
	InputMap.action_erase_events(PinballKeys.LEFT)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	InputMap.action_add_event(PinballKeys.LEFT, key)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_K
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	_keys._physics_process(0.0)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	InputMap.action_erase_events(PinballKeys.LEFT)
	for event: InputEvent in saved:
		InputMap.action_add_event(PinballKeys.LEFT, event)
	assert_array(_sent).is_equal([{"left": true, "right": false}])
