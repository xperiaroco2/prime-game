extends GdUnitTestSuite
## The mode check over `content/` (ARCHITECTURE §9.1): every game mode in `content/modes/` loads as
## a GameMode and passes ModeCheck. The check with the levels' layouts runs on the real levels
## from 2j, when the marker reader exists; until then a match of the base mode is created with
## layouts built in code. Also the base mode's data that 2b settles: its numbers, and ResetMatch
## before PlacePlayers on `End -> Lobby`. One of the two tests that load `content/` (§9.6).

const MODES_DIR := "res://content/modes/"
const BASE_MODE := "res://content/modes/base_mode.tres"


func test_every_mode_in_content_passes_the_mode_check() -> void:
	var paths := _mode_paths(MODES_DIR)
	assert_array(paths).contains(["res://content/modes/base_mode.tres"])
	for path: String in paths:
		var mode := load(path) as GameMode
		assert_object(mode).override_failure_message("%s is not a GameMode" % path).is_not_null()
		if mode == null:
			continue
		var check := ModeCheck.run(mode)
		(
			assert_array(Array(check.errors))
			. override_failure_message("%s: %s" % [path, "\n".join(check.errors)])
			. is_empty()
		)


func test_a_match_of_the_base_mode_starts_in_the_lobby() -> void:
	var mode := _base_mode()
	var game := Match.new(mode, 1, FlatWorldQuery.new(), _layouts_for(mode))
	assert_array(Array(game.refusals)).is_empty()
	assert_bool(game.start(0)).is_true()
	assert_str(game.phase_id()).is_equal("lobby")
	assert_str(game.command_log.mode_path).is_equal("res://content/modes/base_mode.tres")
	assert_int(game.command_log.mode_hash).is_equal(ContentHash.of(mode))


func test_the_base_mode_writes_its_numbers() -> void:
	# The engineer's answer on #49: the §9.5 numbers are in the data, the class defaults neutral.
	var mode := _base_mode()
	assert_int(mode.min_players).is_equal(1)
	assert_int(mode.max_players).is_equal(10)
	assert_float(mode.find_phase(&"countdown").settings[&"seconds"]).is_equal(5.0)
	assert_float(mode.find_phase(&"loading").settings[&"deadline_seconds"]).is_equal(60.0)
	var defaults := GameMode.new()
	assert_int(defaults.min_players).is_equal(0)
	assert_int(defaults.max_players).is_equal(0)


func test_end_to_lobby_resets_the_match_before_placing_players() -> void:
	# Placed first, a ghost would still be a ghost when PlayersPlaced goes to everyone (#58).
	var mode := _base_mode()
	var row := mode.find_transition(&"end", &"back")
	assert_int(row.actions.size()).is_equal(2)
	assert_object(row.actions[0]).is_instanceof(ResetMatch)
	assert_object(row.actions[1]).is_instanceof(PlacePlayers)
	assert_str((row.actions[1] as PlacePlayers).tag).is_equal("lobby_player")


## Layouts built in code for the mode's levels until the marker reader exists (2j): every tag the
## rows place on, with a marker for each of the mode's players.
func _layouts_for(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var layouts: Dictionary[String, LevelLayout] = {}
	var lobby := LevelLayout.new(mode.lobby_level)
	for i in mode.max_players:
		lobby.add_marker(LayoutCheck.LOBBY_PLAYER, Vector3(i, 0, 0))
	layouts[mode.lobby_level] = lobby
	var needed := LayoutCheck.demands_of(
		mode, PhaseSpec.Level.MAP, mode.default_settings(), mode.max_players
	)
	for map: String in mode.maps:
		var layout := LevelLayout.new(map)
		var x := 0
		for tag: StringName in needed.markers:
			for i in needed.markers[tag]:
				layout.add_marker(tag, Vector3(x, 0, 0))
				x += 1
		layouts[map] = layout
	return layouts


func test_the_base_mode_writes_the_mvp_player_rules() -> void:
	# PlayerRules' class defaults are 0, so each number below is written in the file (§9.5).
	var mode := load(MODES_DIR.path_join("base_mode.tres")) as GameMode
	var expected := FixtureModes.player_rules()
	for property: Dictionary in expected.get_property_list():
		var number: String = property["name"]
		var usage: int = property["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var got: float = mode.player_rules.get(number)
		var want: float = expected.get(number)
		(
			assert_float(got)
			. override_failure_message("PlayerRules_base.%s is %s, not %s" % [number, got, want])
			. is_equal_approx(want, 1e-6)
		)


func _mode_paths(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			found.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		found.append_array(_mode_paths(dir_path.path_join(sub)))
	found.sort()
	return found


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode
