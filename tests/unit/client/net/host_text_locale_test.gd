extends GdUnitTestSuite
## Host text over the loopback (#548, the issue's verification): the host's SettingsChanged and
## MatchEnded carry ids plus arguments, so the same bytes read in English under `en` and in
## Ukrainian under `uk`, with no new message. One process has one locale: two players of one lobby
## in two languages are one locale-free payload worded under each locale in turn.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")
const MODE := "res://content/modes/base_mode.tres"

var _harness: Harness
var _locale := ""
var _stage: Control


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	_harness = Harness.new()
	_stage = auto_free(Control.new())
	add_child(_stage)


func after_test() -> void:
	_harness.close()
	TranslationServer.set_locale(_locale)


func test_the_lobby_shortfall_reads_in_each_clients_language() -> void:
	_harness.welcome()
	_harness.send(_lacking(1))
	_harness.pump()
	var model := _harness.session.model
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	_stage.add_child(panel)
	TranslationServer.set_locale("en")
	panel.refresh(model, -1, false)
	assert_str(panel.shortfalls_label.text).is_equal("1 more player to start")
	TranslationServer.set_locale("uk")
	panel.refresh(model, -1, false)
	assert_str(panel.shortfalls_label.text).is_equal("Ще 1 гравець до старту")
	var forms: Array[String] = []
	for count: int in [2, 5]:
		_harness.send(_lacking(count))
		_harness.pump()
		for locale: String in ["en", "uk"]:
			TranslationServer.set_locale(locale)
			panel.refresh(model, -1, false)
			forms.append(panel.shortfalls_label.text)
	(
		assert_array(forms)
		. is_equal(
			[
				"2 more players to start",
				"Ще 2 гравці до старту",
				"5 more players to start",
				"Ще 5 гравців до старту",
			]
		)
	)


func test_the_end_reason_reads_in_each_clients_language() -> void:
	_harness.welcome()
	_harness.send(MatchEndedEvent.new(&"crew", &"every_task_done", {&"time": 461}))
	_harness.pump()
	var model := _harness.session.model
	var mode := load(MODE) as GameMode
	var screen := EndScreen.new()
	_stage.add_child(screen)
	TranslationServer.set_locale("en")
	screen.refresh(model, mode, -1)
	assert_str(screen.reason_label.text).is_equal("All tasks done in 7:41.")
	TranslationServer.set_locale("uk")
	assert_str(screen.reason_label.text).is_equal("Усі задачі виконано за 7:41.")


func test_the_shortfalls_label_and_the_status_plate_word_every_demand_alike() -> void:
	_harness.welcome()
	var problems: Array[HostText] = [
		HostText.of(
			HostText.PLAYERS_MANY, PackedStringArray(), {&"count": 1, &"min": 2, &"max": 10}
		),
		HostText.of(HostText.MARKERS, PackedStringArray(["crew"]), {&"need": 5, &"have": 3}),
		HostText.of(HostText.NO_LAYOUT),
		HostText.of(HostText.NO_TASK_TYPES),
	]
	var no_sets: Dictionary[StringName, PackedStringArray] = {}
	_harness.send(
		SettingsChangedEvent.new(
			{}, "res://levels/maps/a.tscn", 1, Demands.new(null), null, problems, no_sets
		)
	)
	_harness.pump()
	var model := _harness.session.model
	var panel: LobbyPanel = auto_free(LobbyPanel.new())
	_stage.add_child(panel)
	for locale: String in ["en", "uk"]:
		TranslationServer.set_locale(locale)
		panel.refresh(model, -1, false)
		var plate := LobbyText.status_text(LobbyText.of(model, load(MODE) as GameMode, 0))
		assert_str(panel.shortfalls_label.text).is_equal(plate)
		assert_int(plate.split("\n").size()).is_equal(4)
		assert_str(plate).not_contains("=")
	TranslationServer.set_locale("en")
	panel.refresh(model, -1, false)
	assert_str(panel.shortfalls_label.text).is_equal(
		(
			"Too many players: up to 10\nNot enough spawn points on the map: 3 of 5\n"
			+ "Map unavailable\nNo tasks left for this map"
		)
	)


## The host's SettingsChanged of a lobby of one, `count` players short of the mode's minimum.
func _lacking(count: int) -> SettingsChangedEvent:
	var problems: Array[HostText] = [
		HostText.of(
			HostText.PLAYERS_FEW,
			PackedStringArray(),
			{&"count": count, &"min": count + 1, &"max": 10}
		)
	]
	var no_sets: Dictionary[StringName, PackedStringArray] = {}
	return SettingsChangedEvent.new(
		{}, "res://levels/maps/a.tscn", 1, Demands.new(null), null, problems, no_sets
	)
