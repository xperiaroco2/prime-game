extends GdUnitTestSuite
## The round HUD's roster, anger meter and cops' minute (#1570; prime-game-ui `ui-2.5.4`
## `docs/handoff/s07-hud.md`, ARCHITECTURE §4.7.37): the roster's rows from the own ClientModel
## (public names, colours and deaths; the role's tag from the own Teammates knowledge only, so an
## engineer's client tags nobody), their deck words in both languages, and the one clock: the cops'
## minute hides the round timer and shows the danger edge and banner.

const Preview := preload("res://client/dev/screen_preview.gd")
const LayoutTest := preload("res://tests/unit/client/ui/hud_layout_test.gd")
const MODE := "res://content/modes/base_mode.tres"

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_the_roster_lists_every_player_own_first_with_the_body_colours() -> void:
	# The host's client (peer 1) of a three-player round: its own row first, then the session's
	# order; names and colours public (#551).
	var model := Preview.fake_model(_mode, false)
	Preview.fold_round(model)
	var rows := HudText.roster_of(model, _mode)
	var peers: Array = rows.map(func(row: HudText.Row) -> int: return row.peer)
	assert_array(peers).is_equal([2, 1, 3])
	assert_bool(rows[0].own).is_true()
	assert_str(rows[0].name).is_equal("Player2")
	for row: HudText.Row in rows:
		assert_object(row.colour).is_equal(BodyColours.of(model.colour_of(row.peer)))
		assert_bool(row.dead).is_false()


func test_a_dissidents_roster_tags_its_known_teammates_and_itself_only() -> void:
	# fold_round makes the own player a dissident who knows peers 1 and 3 (Teammates).
	var model := Preview.fake_model(_mode, true)
	Preview.fold_round(model)
	var rows := HudText.roster_of(model, _mode)
	var tags: Array = rows.map(func(row: HudText.Row) -> String: return row.tag)
	assert_array(tags).is_equal(["role.dissident", "", "role.dissident"])
	assert_bool(HudText.role_alert(model, _mode)).is_true()
	var shown := HudText.of(model, _mode, 100, HudText.Local.new())
	assert_bool(shown.role_alert).is_true()
	assert_int(shown.roster.size()).is_equal(3)


func test_an_engineers_roster_tags_nobody() -> void:
	# The host sends Teammates only to a role whose players know each other: an engineer's client
	# has none, so no row is tagged and the role's tile is the plain one.
	var model := Preview.fake_model(_mode, false)
	Preview.fold_pregame(model, &"crew", false)
	model.fold(&"PhaseChanged", {"phase": &"round", "end_tick": Preview.ROUND_END_TICK})
	var rows := HudText.roster_of(model, _mode)
	assert_int(rows.size()).is_equal(3)
	for row: HudText.Row in rows:
		assert_str(row.tag).is_empty()
	assert_bool(HudText.role_alert(model, _mode)).is_false()


func test_the_dead_are_marked_and_a_player_who_left_is_gone() -> void:
	var model := Preview.fake_model(_mode, true)
	Preview.fold_round(model)
	model.fold(&"Died", {"peer": 2, "position": Vector3.ZERO})
	model.fold(&"KnockedDown", {"peer": 3, "position": Vector3.ZERO})
	var rows := HudText.roster_of(model, _mode)
	var dead: Array = rows.map(func(row: HudText.Row) -> bool: return row.dead)
	assert_array(dead).is_equal([false, true, false])
	model.fold(&"PlayerLeft", {"peer": 2})
	var peers: Array = HudText.roster_of(model, _mode).map(
		func(row: HudText.Row) -> int: return row.peer
	)
	assert_array(peers).is_equal([1, 3])


func test_the_roster_rows_draw_the_decks_words_in_both_languages() -> void:
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var hud := await _hud()
	hud.show_hud(LayoutTest._state(&"human"))
	assert_int(hud.roster_rows.get_child_count()).is_equal(4)
	assert_str(_name(hud, 0).text).is_equal("Bulk (you)")
	assert_str(_name(hud, 1).text).is_equal("Olena")
	assert_str(_name(hud, 2).text).is_equal("Taras · out")
	assert_str(_name(hud, 2).theme_type_variation).is_equal(&"ToyRosterNameDead")
	var dot := hud.roster_row(1).get_node(^"Dot") as Panel
	assert_object(dot.self_modulate).is_equal(Color.from_hsv(2 / 8.0, 0.5, 0.8))
	var tags: Array = range(4).map(
		func(index: int) -> bool: return (hud.roster_row(index).get_node(^"Tag") as Control).visible
	)
	assert_array(tags).is_equal([true, false, false, true])
	# The map hides the role's tags with the role tile at once (#652), and they come back.
	hud.role_hidden = true
	for index in 4:
		assert_bool((hud.roster_row(index).get_node(^"Tag") as Control).visible).is_false()
	hud.role_hidden = false
	assert_bool((hud.roster_row(0).get_node(^"Tag") as Control).visible).is_true()
	TranslationServer.set_locale("uk")
	hud.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(_name(hud, 0).text).is_equal("Bulk (ти)")
	assert_str(_name(hud, 2).text).is_equal("Taras · поза грою")
	# Fewer players: the rows shrink to them.
	var shown := LayoutTest._state(&"human")
	shown.roster.resize(2)
	hud.show_hud(shown)
	await get_tree().process_frame
	assert_int(hud.roster_rows.get_child_count()).is_equal(2)
	shown.roster.clear()
	hud.show_hud(shown)
	assert_bool(hud.roster.visible).is_false()
	TranslationServer.set_locale(locale)


func test_no_anger_hides_the_meter_and_its_divider() -> void:
	# No mode has the neighbours' anger yet (#1312): the tile holds the time alone.
	var hud := await _hud()
	hud.show_hud(LayoutTest._state(&"empty"))
	assert_bool(hud.timer.visible).is_true()
	assert_bool(hud.time_label.visible).is_true()
	assert_bool(hud.divider.visible or hud.anger_column.visible).is_false()
	var model := Preview.fake_model(_mode, true)
	Preview.fold_round(model)
	assert_float(HudText.of(model, _mode, 100, HudText.Local.new()).anger).is_less(0.0)


func test_the_anger_meter_turns_to_the_alarm_past_seventy_percent() -> void:
	var hud := await _hud()
	var shown := LayoutTest._state(&"human")
	for row: Array in [[0.55, &"ToyBarAngerCalm"], [0.7, &"ToyBarAngerAlarm"]]:
		shown.anger = row[0]
		hud.show_hud(shown)
		assert_bool(hud.divider.visible and hud.anger_column.visible).is_true()
		assert_float(hud.anger_bar.value).is_equal(row[0])
		assert_str(hud.anger_bar.theme_type_variation).is_equal(row[1])
		var caption: StringName = (
			&"ToyTextAlertOnLight" if row[1] == &"ToyBarAngerAlarm" else &"ToyHudCaption"
		)
		assert_str(hud.anger_caption.theme_type_variation).is_equal(caption)
		assert_vector(hud.anger_bar.custom_minimum_size).is_equal(Vector2(240, 16))
	assert_object(hud.siren.texture).is_same(ToyIcons.texture(&"siren-on"))
	shown.siren = false
	hud.show_hud(shown)
	assert_object(hud.siren.texture).is_same(ToyIcons.texture(&"siren-off"))


func test_the_cops_minute_hides_the_round_timer_and_shows_the_edge_and_banner() -> void:
	# One clock (the engineer, 2026-10-22): the timer and its divider hide while the minute runs.
	var hud := await _hud()
	var cops := LayoutTest._state(&"cops")
	# An object within reach: the cops' minute hides Aim all the same (the handoff's `cops`).
	cops.aim = "item.package"
	hud.show_hud(cops)
	assert_bool(hud.time_label.visible or hud.divider.visible).is_false()
	assert_bool(hud.timer.visible and hud.anger_column.visible).is_true()
	assert_bool(hud.edge.visible and hud.cops.visible).is_true()
	assert_str(hud.cops_count.text).is_equal("0:58")
	assert_str(hud.anger_bar.theme_type_variation).is_equal(&"ToyBarAngerAlarm")
	assert_float(hud.anger_bar.value).is_equal(1.0)
	assert_str(hud.anger_caption.theme_type_variation).is_equal(&"ToyTextAlertOnLight")
	assert_bool(hud.aim.visible).is_false()
	cops.cops = ""
	hud.show_hud(cops)
	assert_bool(hud.aim.visible).is_true()
	# The minute over (or never begun): the clock is back, the edge and banner gone.
	hud.show_hud(LayoutTest._state(&"human"))
	assert_bool(hud.time_label.visible and hud.divider.visible).is_true()
	assert_bool(hud.edge.visible or hud.cops.visible).is_false()


static func _name(hud: Hud, index: int) -> Label:
	return hud.roster_row(index).get_node(^"Name") as Label


func _hud() -> Hud:
	var holder: Control = auto_free(Control.new())
	holder.theme = GameUi.THEME
	holder.size = Vector2(1920, 1080)
	add_child(holder)
	var hud := Hud.new()
	holder.add_child(hud)
	await get_tree().process_frame
	return hud
