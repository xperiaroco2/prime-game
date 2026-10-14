extends GdUnitTestSuite
## The Generator's row on the map screen (#801, G6; GD3): a ProgressBar `Charge` (MapBar, its
## percentage on) in place of the counter, its range the progress event's `needed` and its value
## the ticks, extrapolated at the host tick while the charge counts in the round; fed only by its
## generator station's ZoneProgress; full and struck through once done; frozen when the round
## ends (a win before the clock's end_tick), however far the host tick runs on.

const Preview := preload("res://client/dev/screen_preview.gd")
const G := preload("res://tests/fixtures/client/fixture_generator_client.gd")
const TASK := 1
const NEEDED := FixtureGeneratorModes.NEEDED

var _mode: GameMode
var _data: MapData
var _model: ClientModel


func before() -> void:
	_mode = FixtureGeneratorModes.basic()
	var house := Preview.fake_level()
	_data = MapData.from_level(house, _mode)
	house.free()


func before_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)
	_model = G.dealt(FixtureGeneratorModes.SWITCHES, _mode)
	_task(0)


func test_the_generator_row_is_a_charge_bar_and_no_counter() -> void:
	var screen := _screen(1000.0)
	var row := screen.rows_box.get_child(0)
	assert_object(row.find_child("Count", true, false)).is_null()
	var bar := _bar(screen)
	assert_str(String(bar.theme_type_variation)).is_equal("MapBar")
	assert_bool(bar.show_percentage).is_true()
	assert_float(bar.max_value).is_equal(float(NEEDED))
	assert_float(bar.value).is_equal(0.0)
	assert_bool(_struck(screen)).is_false()


func test_the_bar_grows_while_the_charge_counts_and_holds_when_it_stops() -> void:
	G.charge(_model, 5, true, 1000)
	var screen := _screen(1004.0)
	assert_float(_bar(screen).value).is_equal(9.0)
	screen.refresh(_model, _mode, 1006.0, HudText.Local.new())
	assert_float(_bar(screen).value).is_equal(11.0)
	# A switch turned off stops the charge: the event's ticks hold, however far the clock runs.
	G.charge(_model, 7, false, 1007)
	screen.refresh(_model, _mode, 1015.0, HudText.Local.new())
	assert_float(_bar(screen).value).is_equal(7.0)


func test_only_the_generator_stations_progress_feeds_the_bar() -> void:
	G.charge(_model, 5, false, 1000)
	var other := ZoneProgressEvent.new(G.FIRST_SWITCH, 15, NEEDED, true, 1000)
	G.fold(_model, other)
	var screen := _screen(1004.0)
	assert_float(_bar(screen).value).is_equal(5.0)


func test_a_full_charge_fills_the_bar_and_strikes_the_row_through() -> void:
	G.charge(_model, NEEDED, false, 1040)
	var screen := _screen(1050.0)
	assert_float(_bar(screen).value).is_equal(float(NEEDED))
	assert_bool(_struck(screen)).is_true()


func test_every_switch_subtask_done_strikes_the_row_through() -> void:
	_task(FixtureGeneratorModes.SWITCHES)
	var screen := _screen(1000.0)
	assert_bool(_struck(screen)).is_true()
	assert_float(_bar(screen).value).is_equal(float(NEEDED))


func test_the_rounds_end_freezes_the_bar() -> void:
	G.charge(_model, 5, true, 1000)
	var screen := _screen(1004.0)
	assert_float(_bar(screen).value).is_equal(9.0)
	# A win ends the round early, before the clock's end_tick.
	_model.fold(&"MatchEnded", {"side": &"crew"})
	screen.refresh(_model, _mode, 1010.0, HudText.Local.new())
	var frozen := _bar(screen).value
	screen.refresh(_model, _mode, 1030.0, HudText.Local.new())
	assert_float(_bar(screen).value).is_equal(frozen)
	assert_float(frozen).is_equal(5.0)


func test_hovering_or_focusing_the_generator_row_lights_nothing_on_the_board() -> void:
	var type := FixtureGeneratorModes.type_of(_mode)
	assert_array(Array(_data.zone_of(type.id))).is_empty()
	var screen := _screen(1000.0)
	# Hovering a row lights its type (light(), as _process does for the row under the mouse).
	screen.light(type.id)
	assert_int(_zones(screen)).is_equal(0)
	assert_bool(screen.zone_hint.visible).is_false()
	screen.unlight()
	# The keyboard's focus on the row's «?».
	var help := screen.rows_box.get_child(0).find_child("Help", true, false) as Button
	help.grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_zones(screen)).is_equal(0)
	assert_bool(screen.zone_hint.visible).is_false()
	get_viewport().gui_release_focus()
	await get_tree().process_frame


func _zones(screen: MapScreen) -> int:
	return screen.plan.find_children("Zone*", "Panel", true, false).size()


func _task(done: int) -> void:
	var type := FixtureGeneratorModes.type_of(_mode)
	_model.fold(
		&"TaskState",
		{"task": TASK, "type": type.id, "done": done, "total": FixtureGeneratorModes.SWITCHES}
	)


func _screen(host_tick: float) -> MapScreen:
	var screen: MapScreen = auto_free(MapScreen.new())
	screen.theme = GameUi.THEME
	add_child(screen)
	screen.set_data(_data)
	screen.refresh(_model, _mode, host_tick, HudText.Local.new())
	return screen


func _bar(screen: MapScreen) -> ProgressBar:
	return screen.rows_box.get_child(0).find_child("Charge", true, false) as ProgressBar


func _struck(screen: MapScreen) -> bool:
	var name_label := screen.rows_box.get_child(0).find_child("Name", true, false) as Label
	return name_label.get_meta(&"struck", false)
