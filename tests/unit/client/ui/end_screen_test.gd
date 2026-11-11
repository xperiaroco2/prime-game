extends GdUnitTestSuite
## The post game screen (#498; prime-game-ui docs/handoff/s10-post-game.md at ui-0.4.0): the tree
## node for node, the pack's variations only, `win` and `lose` from each team's view, every
## reason, the countdown, the language switch, no focus or input, and Night's fade. How it looks:
## the `shot`s of client/dev/end_*preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const PACK := "res://client/ui/theme/pack/toy.pack.json"

var _locale := ""
var _reduced := false
var _mode: GameMode
var _stage: Control


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	_reduced = UiPrefs.reduced_motion
	TranslationServer.set_locale("en")
	_mode = load(MODE) as GameMode
	_stage = auto_free(Control.new())
	_stage.theme = GameUi.THEME
	add_child(_stage)


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	UiPrefs.reduced_motion = _reduced
	_free_outro_player()


func test_the_tree_matches_the_handoff_node_for_node() -> void:
	# prime-game-ui's s10 at ui-2.5.4 (#1572), state `aliens`: the texts sit on Night.
	var screen := _screen()
	assert_array(_anchors(screen)).is_equal([0.0, 0.0, 1.0, 1.0])
	# [path, class, variation, children's names in order]
	var rows: Array[Array] = [
		[".", "Control", &"", ["Night"]],
		["Night", "Panel", &"ToyBackdropFullScreen", ["Band", "Lines", "Back"]],
		["Night/Band", "PanelContainer", &"ToyBand", ["Title"]],
		["Night/Band/Title", "Label", &"ToyTitleHero", []],
		["Night/Lines", "VBoxContainer", &"ToyColumnTwentyFour", ["Won", "Reason"]],
		["Night/Lines/Won", "Label", &"ToyTitleOnDark", []],
		["Night/Lines/Reason", "Label", &"ToyTextMutedOnDark", []],
		["Night/Back", "Label", &"ToyTextMutedOnDark", []],
	]
	for row: Array in rows:
		var node := screen.get_node_or_null(NodePath(row[0] as String)) as Control
		assert_object(node).override_failure_message(row[0] as String).is_not_null()
		assert_str(node.get_class()).is_equal(row[1])
		assert_str(node.theme_type_variation).override_failure_message(row[0] as String).is_equal(
			row[2]
		)
		if not (row[3] as Array).is_empty():
			var names: Array = node.get_children().map(
				func(child: Node) -> String: return child.name
			)
			assert_array(names).is_equal(row[3])
	assert_array(_anchors(screen.night)).is_equal([0.0, 0.0, 1.0, 1.0])
	# The band across the whole width, 300 to 615 px down; the lines 672 px down; Back 72 px up.
	assert_array(_anchors(screen.band)).is_equal([0.0, 0.0, 1.0, 0.0])
	assert_array([screen.band.offset_top, screen.band.offset_bottom]).is_equal([300.0, 615.0])
	assert_array(_anchors(screen.lines)).is_equal([0.0, 0.0, 1.0, 0.0])
	assert_float(screen.lines.offset_top).is_equal(672.0)
	assert_int(screen.lines.grow_vertical).is_equal(Control.GROW_DIRECTION_END)
	assert_array(_anchors(screen.countdown_label)).is_equal([0.0, 1.0, 1.0, 1.0])
	assert_float(screen.countdown_label.offset_top).is_equal(-72.0)
	assert_int(screen.countdown_label.grow_vertical).is_equal(Control.GROW_DIRECTION_BEGIN)
	assert_int(screen.lines.get_theme_constant(&"separation")).is_equal(24)
	assert_int(screen.title_label.vertical_alignment).is_equal(VERTICAL_ALIGNMENT_CENTER)
	assert_int(screen.reason_label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	for label: Label in [
		screen.title_label, screen.winner_label, screen.reason_label, screen.countdown_label
	]:
		assert_int(label.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_str(screen.title_label.text).is_equal("end.title")
	# Keys with placeholders are set from code, never translated a second time.
	assert_int(screen.reason_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_int(screen.countdown_label.auto_translate_mode).is_equal(
		Node.AUTO_TRANSLATE_MODE_DISABLED
	)


func test_it_names_only_the_packs_variations() -> void:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	var variations: Dictionary = pack["variations"]
	var screen := _screen()
	var used := PackedStringArray()
	for control: Control in screen.find_children("*", "Control", true, false):
		if not control.theme_type_variation.is_empty():
			used.append(control.theme_type_variation)
	assert_int(used.size()).is_equal(7)
	for variation: String in used:
		assert_bool(variations.has(variation)).override_failure_message(variation).is_true()


func test_the_winning_side_reads_the_same_for_everyone_on_its_band() -> void:
	# s10 at ui-2.5.4: no plate for a win or a loss (ui-2.0.0); the band is the accent for the
	# crew's win, the danger colour for the dissidents' (the handoff's aliens and humans).
	# [own role, winning side, band, title, the key]
	var cases: Array[Array] = [
		[&"crew", &"crew", &"ToyBand", &"ToyTitleHero", "end.won_engineers"],
		[&"dissident", &"crew", &"ToyBand", &"ToyTitleHero", "end.won_engineers"],
		[&"dissident", &"dissidents", &"ToyBandAlert", &"ToyTitleHeroAlert", "end.won_dissidents"],
		[&"crew", &"dissidents", &"ToyBandAlert", &"ToyTitleHeroAlert", "end.won_dissidents"],
		[&"", &"dissidents", &"ToyBandAlert", &"ToyTitleHeroAlert", "end.won_dissidents"],
	]
	for each: Array in cases:
		var screen := _screen()
		screen.refresh(_ended(each[0] as StringName, each[1] as StringName), _mode, 100)
		assert_str(screen.band.theme_type_variation).is_equal(each[2])
		assert_str(screen.title_label.theme_type_variation).is_equal(each[3])
		assert_object(screen.winner_shown()).is_same(screen.winner_label)
		assert_str(screen.winner_shown().text).is_equal(each[4])
		assert_str(screen.winner_label.theme_type_variation).is_equal(&"ToyTitleOnDark")
		assert_bool(screen.winner_shown().is_visible_in_tree()).is_true()
	assert_str(tr("end.won_dissidents")).is_equal("The Dissidents won")


func test_a_side_with_no_key_or_no_winner_hides_the_winner_line() -> void:
	for side: StringName in [&"", &"robots"]:
		var screen := _screen()
		screen.refresh(_ended(&"crew", side), _mode, 100)
		assert_bool(screen.winner_label.visible).is_false()
		assert_bool(screen.title_label.visible).is_true()
		assert_str(screen.band.theme_type_variation).is_equal(&"ToyBand")


func test_each_reason_and_an_unknown_one_hides_the_line() -> void:
	var screen := _screen()
	screen.refresh(_ended(&"crew", &"crew"), _mode, 100)
	# A MatchEnded without a reason (a `won` no win condition reported): no line.
	assert_bool(screen.reason_label.visible).is_false()
	screen.show_reason(&"every_task_done", 461)
	assert_bool(screen.reason_label.visible).is_true()
	assert_str(screen.reason_label.text).is_equal("All tasks done in 7:41.")
	assert_str(screen.title_label.text).is_equal("end.title.party")
	screen.show_reason(&"every_task_done", 65)
	assert_str(screen.reason_label.text).is_equal("All tasks done in 1:05.")
	screen.show_reason(&"time_up", -1)
	assert_str(screen.reason_label.text).is_equal("The tasks aren't done.")
	assert_str(screen.title_label.text).is_equal("end.title.time_up")
	for unknown: StringName in [&"no_crew_present", &""]:
		screen.show_reason(unknown, 461)
		assert_bool(screen.reason_label.visible).is_false()
		assert_str(screen.reason_label.text).is_empty()
		assert_str(screen.title_label.text).is_equal("end.title")


## The reason comes with MatchEnded through the model (#548): the condition's id and its time.
func test_the_reason_follows_the_models_match_ended() -> void:
	var screen := _screen()
	var model := _ended(&"crew", &"crew")
	model.fold(
		&"MatchEnded", {"side": &"crew", "reason": &"every_task_done", "numbers": {&"time": 461}}
	)
	screen.refresh(model, _mode, 100)
	assert_bool(screen.reason_label.visible).is_true()
	assert_str(screen.reason_label.text).is_equal("All tasks done in 7:41.")
	model.fold(&"MatchEnded", {"side": &"dissidents", "reason": &"time_up", "numbers": {}})
	screen.refresh(model, _mode, 100)
	assert_str(screen.reason_label.text).is_equal("The tasks aren't done.")
	# No deck key for no_crew_present (ui-0.4.0): the line hides.
	model.fold(&"MatchEnded", {"side": &"dissidents", "reason": &"no_crew_present", "numbers": {}})
	screen.refresh(model, _mode, 100)
	assert_bool(screen.reason_label.visible).is_false()


func test_the_round_time_is_minutes_and_two_digit_seconds() -> void:
	assert_str(EndScreen.round_time(0)).is_equal("0:00")
	assert_str(EndScreen.round_time(461)).is_equal("7:41")
	assert_str(EndScreen.round_time(600)).is_equal("10:00")


func test_it_counts_3_2_1_to_the_lobby_for_everyone_with_no_button() -> void:
	# #212: End's end tick (PhaseChanged) is 3 s after its entry; host and client see the same.
	for hosting: bool in [true, false]:
		var model := Preview.fake_model(_mode, hosting)
		model.fold(&"PhaseChanged", {"phase": &"end", "end_tick": 160})
		model.fold(&"MatchEnded", {"side": &"crew"})
		var screen := _screen()
		var shown := PackedStringArray()
		for host_tick: int in [100, 101, 120, 121, 140, 141, 160, 200]:
			screen.refresh(model, _mode, host_tick)
			shown.append(screen.countdown_label.text)
		var expected := PackedStringArray()
		for count: int in [3, 3, 2, 2, 1, 1, 1, 1]:
			expected.append("Back to the ship in %d…" % count)
		assert_array(Array(shown)).is_equal(Array(expected))
		assert_bool(screen.countdown_label.visible).is_true()
		assert_array(screen.find_children("*", "BaseButton", true, false)).is_empty()
		# No end tick known (an End with no `seconds`, or no host tick yet): no countdown.
		screen.refresh(model, _mode, -1)
		assert_bool(screen.countdown_label.visible).is_false()
		model.fold(&"PhaseChanged", {"phase": &"end", "end_tick": -1})
		screen.refresh(model, _mode, 150)
		assert_bool(screen.countdown_label.visible).is_false()


func test_the_texts_from_code_follow_a_language_switch() -> void:
	var screen := _screen()
	var model := _ended(&"crew", &"crew")
	model.fold(&"PhaseChanged", {"phase": &"end", "end_tick": 160})
	screen.refresh(model, _mode, 100)
	screen.show_reason(&"every_task_done", 461)
	TranslationServer.set_locale("uk")
	assert_str(screen.reason_label.text).is_equal("Усі задачі виконано за 7:41.")
	assert_str(screen.countdown_label.text).is_equal("Повернення на корабель через 3…")
	# The plain keys translate themselves.
	assert_str(screen.title_label.atr(screen.title_label.text)).is_equal("Вечірка вдалася!")
	assert_str(screen.winner_label.atr(screen.winner_label.text)).is_equal("Перемогли Інженери")
	TranslationServer.set_locale("en")
	assert_str(screen.countdown_label.text).is_equal("Back to the ship in 3…")


func test_no_control_takes_focus_or_input() -> void:
	var screen := _screen()
	screen.refresh(_ended(&"crew", &"crew"), _mode, 100)
	var controls: Array[Node] = [screen]
	controls.append_array(screen.find_children("*", "Control", true, false))
	for node: Node in controls:
		var control := node as Control
		assert_int(control.mouse_filter).override_failure_message(str(control.name)).is_equal(
			Control.MOUSE_FILTER_IGNORE
		)
		assert_int(control.focus_mode).override_failure_message(str(control.name)).is_equal(
			Control.FOCUS_NONE
		)


func test_night_fades_in_over_the_handoffs_time_and_cuts_under_reduced_motion() -> void:
	UiPrefs.reduced_motion = false
	var screen := _screen(false)
	var began: Array[int] = [0]
	screen.outro_began.connect(func() -> void: began[0] += 1)
	screen.visible = true
	assert_float(screen.night.modulate.a).is_equal(0.0)
	assert_object(screen.fade).is_not_null()
	screen.fade.custom_step(EndScreen.FADE_SECONDS / 2.0)
	assert_float(screen.night.modulate.a).is_equal_approx(0.5, 0.01)
	screen.fade.custom_step(EndScreen.FADE_SECONDS)
	assert_float(screen.night.modulate.a).is_equal(1.0)
	assert_int(began[0]).is_equal(1)
	# Hidden (back in the lobby), then the next End: a fade again, one more outro.
	screen.visible = false
	assert_object(screen.fade).is_null()
	UiPrefs.reduced_motion = true
	screen.visible = true
	assert_float(screen.night.modulate.a).is_equal(1.0)
	assert_object(screen.fade).is_null()
	assert_int(began[0]).is_equal(2)


func test_the_next_end_starts_without_the_last_rounds_reason_or_countdown() -> void:
	var screen := _screen()
	screen.refresh(_ended(&"crew", &"crew"), _mode, 100)
	screen.show_reason(&"every_task_done", 461)
	assert_bool(screen.reason_label.visible).is_true()
	screen.visible = false
	screen.visible = true
	assert_bool(screen.reason_label.visible).is_false()
	assert_str(screen.reason_label.text).is_empty()
	assert_bool(screen.countdown_label.visible).is_false()
	assert_str(screen.title_label.text).is_equal("end.title")


func test_a_parent_hidden_and_shown_again_is_not_a_new_end() -> void:
	UiPrefs.reduced_motion = false
	var screen := _screen(false)
	var began: Array[int] = [0]
	screen.outro_began.connect(func() -> void: began[0] += 1)
	screen.visible = true
	screen.fade.custom_step(EndScreen.FADE_SECONDS * 2.0)
	assert_float(screen.night.modulate.a).is_equal(1.0)
	_stage.visible = false
	_stage.visible = true
	assert_float(screen.night.modulate.a).is_equal(1.0)
	assert_object(screen.fade).is_null()
	assert_int(began[0]).is_equal(1)


func test_the_outro_sound_starts_once_per_end_on_the_ui_bus() -> void:
	# #657: the one sound of both outcomes, on the UI bus, once each time End starts.
	AudioBuses.ensure()
	_free_outro_player()
	var screen := _screen(false)
	var outros_before := UiSounds.outros
	assert_object(UiSounds.outro_player_in(get_tree())).is_null()
	screen.visible = true
	assert_int(UiSounds.outros).is_equal(outros_before + 1)
	var player := UiSounds.outro_player_in(get_tree())
	assert_object(player).is_not_null()
	assert_str(String(player.bus)).is_equal(String(AudioBuses.UI))
	var stream := player.stream as AudioStreamRandomizer
	assert_int(stream.streams_count).is_equal(SfxSet.paths_for(SfxSet.UI_OUTRO).size())
	# It started: play() made a playback, which the player keeps until its next frame (no frame
	# runs in this test). Not `playing`: the file lasts about 0.12 s and the headless (Dummy)
	# driver mixes it on its own thread in real time, so on a loaded runner it has ended and
	# `playing` is false again before this line (#948).
	assert_bool(player.has_stream_playback()).is_true()
	var first := player.get_stream_playback()
	# A parent hidden and shown again is not a new End: no second outro.
	_stage.visible = false
	_stage.visible = true
	assert_int(UiSounds.outros).is_equal(outros_before + 1)
	# Back in the lobby, then the next End: one more, from the same player.
	screen.visible = false
	assert_int(UiSounds.outros).is_equal(outros_before + 1)
	screen.visible = true
	assert_int(UiSounds.outros).is_equal(outros_before + 2)
	assert_object(UiSounds.outro_player_in(get_tree())).is_same(player)
	# Started again: a new playback, not the last End's.
	assert_object(player.get_stream_playback()).is_not_same(first)
	_free_outro_player()


## The outro's player under the root (an End shown plays it): each test ends without one.
func _free_outro_player() -> void:
	var player := UiSounds.outro_player_in(get_tree())
	if player != null:
		player.get_parent().remove_child(player)
		player.free()


## An EndScreen on the stage, with the shared theme; `shown` false: hidden, as GameUi starts it.
func _screen(shown := true) -> EndScreen:
	var screen := EndScreen.new()
	screen.visible = shown
	_stage.add_child(screen)
	return screen


## A lobby of three after a match the `side` won, the own role `role` (&"": none).
func _ended(role: StringName, side: StringName) -> ClientModel:
	var model := Preview.fake_model(_mode, true)
	if not role.is_empty():
		model.fold(&"RoleAssigned", {"role": role})
	model.fold(&"MatchEnded", {"side": side})
	return model


## [left, top, right, bottom] anchors of `control`.
func _anchors(control: Control) -> Array:
	return [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]
