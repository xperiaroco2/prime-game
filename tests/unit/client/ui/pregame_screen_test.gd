extends GdUnitTestSuite
## The pregame role reveal (#496; prime-game-ui docs/handoff/s06-pre-game.md at ui-0.4.0): the tree
## node for node, the pack's variations only, `engineer`, `dissident` with and without teammates,
## `after` (Night's fade over the round's HUD and its cut under reduced motion), the language
## switch, no focus or input, that it reads only the own role and Teammates, and the own side's
## sound once per reveal on the UI bus, only in the pregame (#716). How it looks: the
## `shot`s of client/dev/pregame_*preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const PACK := "res://client/ui/theme/pack/toy.pack.json"
const SOURCE := "res://client/ui/pregame_screen.gd"

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
	_free_role_players()


func test_the_tree_matches_the_handoff_node_for_node() -> void:
	var screen := _screen()
	assert_array(_anchors(screen)).is_equal([0.0, 0.0, 1.0, 1.0])
	# [path, class, variation, children's names in order]
	var rows: Array[Array] = [
		[".", "Control", &"", ["Night", "V"]],
		["Night", "Panel", &"ToyBackdropNight", []],
		["V", "VBoxContainer", &"ToyColumnThirtyTwo", ["YourRole", "RoleRaised", "Text"]],
		["V/YourRole", "Label", &"ToyTextMutedOnDark", []],
		["V/RoleRaised", "MarginContainer", &"", ["Base", "Role"]],
		["V/RoleRaised/Base", "Panel", &"ToyBaseTitle", []],
		["V/RoleRaised/Role", "Label", &"ToyTitlePlate", []],
		["V/Text", "VBoxContainer", &"ToyColumnSixteen", ["Goal", "Team"]],
		["V/Text/Goal", "Label", &"ToyTextOnDark", []],
		["V/Text/Team", "Label", &"ToyTextMutedOnDark", []],
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
	var column := screen.column
	assert_array(_anchors(column)).is_equal([0.5, 0.5, 0.5, 0.5])
	var offsets := [
		column.offset_left, column.offset_top, column.offset_right, column.offset_bottom
	]
	assert_array(offsets).is_equal([0.0, 0.0, 0.0, 0.0])
	assert_int(column.grow_horizontal).is_equal(Control.GROW_DIRECTION_BOTH)
	assert_int(column.grow_vertical).is_equal(Control.GROW_DIRECTION_BOTH)
	assert_vector(column.custom_minimum_size).is_equal(Vector2(1152, 0))
	assert_int(column.alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	assert_int(column.get_theme_constant(&"separation")).is_equal(32)
	assert_int(screen.text_box.get_theme_constant(&"separation")).is_equal(16)
	assert_bool(screen.role_plate is ToyRaised).is_true()
	assert_int(screen.role_plate.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_CENTER)
	for label: Label in [screen.goal_label, screen.team_label]:
		assert_vector(label.custom_minimum_size).is_equal(Vector2(1152, 0))
		assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	for label: Label in [screen.title_label, screen.goal_label, screen.team_label]:
		assert_int(label.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_str(screen.title_label.text).is_equal("pregame.your_role")
	# The team line has a placeholder and the players' names: set from code, never re-translated.
	assert_int(screen.team_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)


func test_it_names_only_the_packs_variations() -> void:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	var variations: Dictionary = pack["variations"]
	var screen := _screen()
	var used := PackedStringArray()
	for control: Control in screen.find_children("*", "Control", true, false):
		if not control.theme_type_variation.is_empty():
			used.append(control.theme_type_variation)
	assert_int(used.size()).is_equal(8)
	for variation: String in used:
		assert_bool(variations.has(variation)).override_failure_message(variation).is_true()


func test_an_engineer_sees_the_role_and_the_goal_and_no_team() -> void:
	var screen := _screen()
	screen.refresh(_pregame(&"crew"), _mode)
	assert_str(screen.role_label.text).is_equal("role.engineer")
	assert_str(screen.goal_label.text).is_equal("role.goal.engineer")
	assert_bool(screen.column.visible).is_true()
	assert_bool(screen.goal_label.visible).is_true()
	assert_bool(screen.team_label.visible).is_false()
	assert_str(screen.team_label.text).is_empty()


func test_a_dissident_sees_its_teammates_and_not_itself() -> void:
	var screen := _screen()
	screen.refresh(_pregame(&"dissident"), _mode)
	assert_str(screen.role_label.text).is_equal("role.dissident")
	assert_str(screen.goal_label.text).is_equal("role.goal.dissident")
	assert_bool(screen.team_label.visible).is_true()
	assert_str(screen.team_label.text).is_equal("Your team: Player3")
	# Two teammates, joined by ", " in the host's order; one who left the roster is skipped.
	var model := Preview.fake_model(_mode, false)
	model.fold(&"RoleAssigned", {"role": &"dissident"})
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([1, 2, 3, 9])})
	screen.refresh(model, _mode)
	assert_str(screen.team_label.text).is_equal("Your team: Player1, Player3")
	assert_array(Array(PregameScreen.team_of(model))).is_equal(["Player1", "Player3"])


func test_a_dissident_with_no_teammates_sees_no_team_line() -> void:
	var screen := _screen()
	screen.refresh(_pregame(&"dissident", false), _mode)
	assert_str(screen.role_label.text).is_equal("role.dissident")
	assert_bool(screen.team_label.visible).is_false()
	assert_str(screen.team_label.text).is_empty()


func test_before_the_role_arrives_only_night_shows() -> void:
	var screen := _screen()
	var model := Preview.fake_model(_mode, true)
	model.fold(&"PhaseChanged", {"phase": &"pregame", "end_tick": 160})
	screen.reveal()
	screen.refresh(model, _mode)
	assert_bool(screen.visible).is_true()
	assert_bool(screen.column.visible).is_false()
	assert_str(screen.role_label.text).is_empty()


func test_a_role_with_no_deck_key_shows_its_name_and_no_goal() -> void:
	# No goal text is invented for a role the deck does not name (a later mode's).
	var model := Preview.fake_model(_mode, true)
	model.fold(&"RoleAssigned", {"role": &"medic"})
	var screen := _screen()
	screen.refresh(model, _mode)
	assert_str(screen.role_label.text).is_equal("medic")
	assert_bool(screen.goal_label.visible).is_false()


func test_it_reads_only_the_own_role_and_teammates() -> void:
	# #175: nothing about any other player's role. The source names only these model fields.
	var source := FileAccess.get_file_as_string(SOURCE)
	var found := RegEx.create_from_string("model\\.([a-z_]+)")
	var fields := {}
	for match_found: RegExMatch in found.search_all(source):
		fields[match_found.get_string(1)] = true
	var allowed := ["role", "teammates", "own_peer", "roster"]
	for field: String in fields:
		assert_bool(field in allowed).override_failure_message("reads model.%s" % field).is_true()
	# An engineer's model that (wrongly) held the dissidents' Teammates still names nobody: only
	# the own role's entry counts, and the screen is the same as without it.
	var plain := _texts(_pregame(&"crew"))
	var model := _pregame(&"crew")
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([2, 3])})
	assert_array(_texts(model)).is_equal(plain)
	assert_array(Array(PregameScreen.team_of(model))).is_empty()
	# What any screen shows names no microphone, voice or hearing (the engineer, 2026-10-02).
	for role: StringName in [&"crew", &"dissident"]:
		for text: String in _texts(_pregame(role)):
			for word: String in ["mic", "voice", "hear", "player2"]:
				assert_str(text.to_lower()).override_failure_message(text).not_contains(word)


func test_the_team_line_follows_a_language_switch() -> void:
	var screen := _screen()
	screen.refresh(_pregame(&"dissident"), _mode)
	TranslationServer.set_locale("uk")
	screen.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(screen.team_label.text).is_equal("Твоя команда: Player3")
	TranslationServer.set_locale("en")
	screen.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(screen.team_label.text).is_equal("Your team: Player3")


func test_no_control_takes_focus_or_input() -> void:
	var screen := _screen()
	screen.refresh(_pregame(&"dissident"), _mode)
	var controls: Array[Control] = [screen]
	for node: Node in screen.find_children("*", "Control", true, false):
		controls.append(node as Control)
	for control: Control in controls:
		var where := str(screen.get_path_to(control))
		assert_int(control.mouse_filter).override_failure_message(where).is_equal(
			Control.MOUSE_FILTER_IGNORE
		)
		assert_int(control.focus_mode).override_failure_message(where).is_equal(Control.FOCUS_NONE)
		assert_bool(control is BaseButton).override_failure_message(where).is_false()


func test_night_fades_out_over_the_handoffs_time_then_the_screen_hides() -> void:
	UiPrefs.reduced_motion = false
	var screen := _screen()
	screen.refresh(_pregame(&"dissident"), _mode)
	screen.reveal()
	screen.lift()
	# `after`: V gone at once, Night fading from 1 to 0 over 0.4 s.
	assert_bool(screen.visible).is_true()
	assert_bool(screen.column.visible).is_false()
	assert_bool(screen.lifting()).is_true()
	assert_float(screen.night.modulate.a).is_equal(1.0)
	screen.fade.custom_step(PregameScreen.FADE_SECONDS / 2.0)
	assert_float(screen.night.modulate.a).is_equal_approx(0.5, 0.01)
	assert_bool(screen.visible).is_true()
	screen.fade.custom_step(PregameScreen.FADE_SECONDS)
	assert_bool(screen.visible).is_false()
	assert_bool(screen.lifting()).is_false()
	# Ready for the next pregame: Night opaque, the column back once the role shows.
	assert_float(screen.night.modulate.a).is_equal(1.0)
	screen.reveal()
	assert_bool(screen.visible).is_true()
	assert_bool(screen.column.visible).is_true()


func test_the_fade_is_a_cut_under_reduced_motion() -> void:
	UiPrefs.reduced_motion = true
	var screen := _screen()
	screen.refresh(_pregame(&"crew"), _mode)
	screen.reveal()
	screen.lift()
	assert_object(screen.fade).is_null()
	assert_bool(screen.visible).is_false()
	assert_float(screen.night.modulate.a).is_equal(1.0)


func test_the_role_is_revealed_once_per_pregame() -> void:
	# The hook for the one sound per side (#213, #716), with the own role's side in the own mode.
	UiPrefs.reduced_motion = true
	var screen := _screen()
	var revealed: Array[Array] = []
	screen.role_revealed.connect(
		func(role: StringName, side: StringName) -> void: revealed.append([role, side])
	)
	var model := _pregame(&"dissident")
	screen.reveal()
	screen.refresh(model, _mode)
	screen.refresh(model, _mode)
	assert_array(revealed).is_equal([[&"dissident", &"dissidents"]])
	screen.lift()
	screen.reveal()
	screen.refresh(_pregame(&"crew"), _mode)
	assert_array(revealed).is_equal([[&"dissident", &"dissidents"], [&"crew", &"crew"]])


func test_the_own_sides_sound_plays_once_per_reveal_on_the_ui_bus() -> void:
	# #716 (#213 criterion 3, #175): one sound per side, the own side's only, once per pregame.
	AudioBuses.ensure()
	UiPrefs.reduced_motion = true
	var screen := _screen()
	var played_before := UiSounds.roles.size()
	var model := _pregame(&"dissident")
	screen.reveal()
	screen.refresh(model, _mode)
	screen.refresh(model, _mode)
	assert_array(_played_since(played_before)).is_equal([SfxSet.UI_ROLE_DISSIDENTS])
	var player := UiSounds.role_player_in(get_tree(), SfxSet.UI_ROLE_DISSIDENTS)
	assert_object(player).is_not_null()
	assert_str(String(player.bus)).is_equal(String(AudioBuses.UI))
	assert_bool(player.playing).is_true()
	var stream := player.stream as AudioStreamRandomizer
	assert_int(stream.streams_count).is_equal(1)
	assert_object(UiSounds.role_player_in(get_tree(), SfxSet.UI_ROLE_ENGINEERS)).is_null()
	# The next pregame, as an engineer: the engineers' sound, once.
	screen.lift()
	screen.reveal()
	var crew := _pregame(&"crew")
	screen.refresh(crew, _mode)
	screen.refresh(crew, _mode)
	assert_array(_played_since(played_before)).is_equal(
		[SfxSet.UI_ROLE_DISSIDENTS, SfxSet.UI_ROLE_ENGINEERS]
	)
	assert_bool(UiSounds.role_player_in(get_tree(), SfxSet.UI_ROLE_ENGINEERS).playing).is_true()
	# A third pregame as a dissident again: its player is the one made the first time.
	screen.lift()
	screen.reveal()
	screen.refresh(model, _mode)
	assert_array(_played_since(played_before)).is_equal(
		[SfxSet.UI_ROLE_DISSIDENTS, SfxSet.UI_ROLE_ENGINEERS, SfxSet.UI_ROLE_DISSIDENTS]
	)
	assert_object(UiSounds.role_player_in(get_tree(), SfxSet.UI_ROLE_DISSIDENTS)).is_same(player)


func test_no_role_sound_before_the_role_outside_the_pregame_or_for_an_unknown_side() -> void:
	UiPrefs.reduced_motion = false
	var played_before := UiSounds.roles.size()
	# Before RoleAssigned: Night alone, silent.
	var screen := _screen()
	screen.reveal()
	screen.refresh(Preview.fake_model(_mode, true), _mode)
	# A screen not shown (any screen but the pregame) plays nothing.
	var hidden := _screen()
	hidden.visible = false
	hidden.refresh(_pregame(&"crew"), _mode)
	# A role that arrives only as Night fades out over the round plays nothing in the round.
	screen.lift()
	assert_bool(screen.lifting()).is_true()
	screen.refresh(_pregame(&"crew"), _mode)
	# A role of a side SIDE_SOUNDS does not name (a later mode's) plays nothing.
	var other := _screen()
	other.reveal()
	var medic := Preview.fake_model(_mode, true)
	medic.fold(&"RoleAssigned", {"role": &"medic"})
	other.refresh(medic, _mode)
	assert_array(_played_since(played_before)).is_empty()


func test_a_known_role_of_a_side_the_table_lacks_plays_nothing() -> void:
	# A later mode's side (say pirates) has no sound: the table's guard, not a missing key.
	var screen := _screen()
	var played_before := UiSounds.roles.size()
	screen._play_role_sound(&"x", &"pirates")
	assert_array(_played_since(played_before)).is_empty()


func test_the_role_sound_stops_when_the_pregame_ends() -> void:
	# A reveal near the pregame's end must not play into the round, where the microphone is open.
	AudioBuses.ensure()
	UiPrefs.reduced_motion = true
	var screen := _screen()
	screen.reveal()
	screen.refresh(_pregame(&"dissident"), _mode)
	var player := UiSounds.role_player_in(get_tree(), SfxSet.UI_ROLE_DISSIDENTS)
	assert_bool(player.playing).is_true()
	screen.lift()
	assert_bool(player.playing).is_false()
	# Any other screen (stop) ends it too.
	var other := _screen()
	other.reveal()
	other.refresh(_pregame(&"dissident"), _mode)
	assert_bool(player.playing).is_true()
	other.stop()
	assert_bool(player.playing).is_false()


func test_the_role_sound_stays_on_the_own_client() -> void:
	# #716: no peer hears another's role sound. It is a UI-bus player of the own client, chosen
	# from the own role only (the model test above); neither file sends anything or names a
	# session or the voice in its code, so nothing about it leaves the client (the bots test
	# checks the wire).
	for path: String in [SOURCE, "res://client/ui/ui_sounds.gd"]:
		var code := PackedStringArray()
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			code.append(line.get_slice("#", 0))
		var source := "\n".join(code)
		for word: String in ["Session", "send", "rpc", "Voice", "AudioStreamPlayer3D"]:
			assert_str(source).override_failure_message("%s names %s" % [path, word]).not_contains(
				word
			)


func test_the_ui_lifts_it_into_the_round_and_hides_it_on_any_other_screen() -> void:
	UiPrefs.reduced_motion = false
	var ui: GameUi = auto_free(GameUi.new())
	add_child(ui)
	# Over the round's HUD, the life screen and the map, so its black uncovers them (they are on
	# the Ui layer, it on the black screens' layer above, #656); under the post game screen (later
	# on its layer) and the Esc menu (on the layer above it).
	for under: Control in [ui.hud, ui.life, ui.map]:
		assert_object(under.get_parent()).is_same(ui)
	assert_object(ui.pregame.get_parent()).is_same(ui.black)
	assert_int(ui.black.layer).is_greater(ui.layer)
	var order := ui.black.get_children()
	assert_int(order.find(ui.pregame)).is_less(order.find(ui.end))
	assert_int(ui.above.layer).is_greater(ui.black.layer)
	assert_object(ui.esc.get_parent()).is_same(ui.above)
	ui.show_screen(GameFlow.Screen.PREGAME)
	ui.refresh(_pregame(&"crew"), _mode, 100, true)
	assert_bool(ui.pregame.visible).is_true()
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.hud.visible).is_true()
	assert_bool(ui.pregame.visible).is_true()
	assert_bool(ui.pregame.lifting()).is_true()
	# The game shows its screen every frame: the round again does not stop the fade.
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.pregame.lifting()).is_true()
	ui.pregame.fade.custom_step(PregameScreen.FADE_SECONDS * 2.0)
	assert_bool(ui.pregame.visible).is_false()
	# A pregame left for the lobby (the host gone, a leave) hides at once, with no fade.
	ui.show_screen(GameFlow.Screen.PREGAME)
	ui.show_screen(GameFlow.Screen.LOBBY)
	assert_bool(ui.pregame.visible).is_false()
	assert_bool(ui.pregame.lifting()).is_false()
	# A round not entered from the pregame (a later round's frame) never shows it.
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.pregame.visible).is_false()


## The role sounds played since UiSounds.roles held `before` of them.
func _played_since(before: int) -> Array[StringName]:
	return UiSounds.roles.slice(before)


## The role sounds' players under the root (a reveal plays one): each test ends without them.
func _free_role_players() -> void:
	for id: StringName in UiSounds.ROLE_PLAYERS:
		var player := UiSounds.role_player_in(get_tree(), id)
		if player != null:
			player.get_parent().remove_child(player)
			player.free()


func _screen() -> PregameScreen:
	var screen := PregameScreen.new()
	_stage.add_child(screen)
	return screen


## The own player (peer 1) dealt `role` into the pregame; a dissident with peer 3 unless alone.
func _pregame(role: StringName, with_mate := true) -> ClientModel:
	var model := Preview.fake_model(_mode, true)
	Preview.fold_pregame(model, role, with_mate)
	return model


## Every visible text the screen shows for `model`, in the current language.
func _texts(model: ClientModel) -> Array[String]:
	var screen := _screen()
	screen.reveal()
	screen.refresh(model, _mode)
	var texts: Array[String] = []
	for found: Node in screen.find_children("*", "Label", true, false):
		var label := found as Label
		if label.is_visible_in_tree():
			texts.append(
				(
					label.atr(label.text)
					if label.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED
					else label.text
				)
			)
	return texts


func _anchors(control: Control) -> Array:
	return [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]
