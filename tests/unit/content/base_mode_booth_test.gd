extends GdUnitTestSuite
## The base mode's photo booth (#1396; GDD §3 "The photo booth"; ARCHITECTURE §9.5.29): the
## shipped booth and strip carry the provisional numbers; on the hall's real layout the booth
## stands on its one `booth` marker, a press inside it runs the whole session and prints a strip
## for each player in the frames; readying up mid-session stops it, and countdown_done clears the
## booth and every strip before the map loads. M8 hides the booth (#1680): the shipped base mode
## places none and runs none of its parts, and the booth's tests run on BaseModeWithBooth, the
## base mode with its three parts back as M9 brings them.

const BASE_MODE := "res://content/modes/base_mode.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const GREYBOX := "res://levels/greybox/greybox.tscn"
const P1 := 1
const P2 := 2
const BOOTH := "res://content/stations/booth.tres"
const STRIP := "res://content/items/strip.tres"


func _layouts_for(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var levels := MarkerReader.read_levels(
		mode, FlatWorldQuery.new(), ScenarioLevels.unsnapped(mode)
	)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts


## The base mode in the hall with P1 and P2 standing inside the booth, after one tick.
func _in_booth(mode: GameMode) -> Match:
	var layouts := _layouts_for(mode)
	var game := Match.new(mode, 7, FlatWorldQuery.new(), layouts)
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	var marker := layouts[mode.lobby_level].positions(&"booth")
	assert_int(marker.size()).is_equal(1)
	var booth := FixtureBooth.booth_id(game)
	assert_int(booth).is_not_equal(-1)
	assert_vector(game.state.stations[booth].position).is_equal(marker[0])
	FixtureItemModes.stand(game, P1, marker[0] + Vector3(0.4, 0, 0.3))
	FixtureItemModes.stand(game, P2, marker[0] + Vector3(-0.4, 0, -0.3))
	return game


func test_m8_s_base_mode_places_no_booth_and_runs_none_of_its_parts() -> void:
	var mode := load(BASE_MODE) as GameMode
	for phase: PhaseSpec in mode.phases:
		assert_bool(BoothTicks.listed_in(phase)).override_failure_message(String(phase.id)).is_false()
		for system: TickSystem in phase.tick_systems:
			var placing := system as StationTicks
			if placing != null:
				assert_str(String(placing.kind.id)).is_not_equal("booth")
	for row: Transition in mode.transitions:
		for action: RuleEffect in row.actions:
			assert_bool(action is StopBooth).is_false()
	assert_array(Array(BoothCheck.problems(mode))).is_empty()
	# In the hall's lobby the marker stays for M9, and no booth stands on it.
	var game := Match.new(mode, 7, FlatWorldQuery.new(), _layouts_for(mode))
	game.state.map = GREYBOX
	assert_bool(game.start(0)).is_true()
	FixtureBaseMode.join(game, P1)
	FixtureModes.run_ticks(game, 1)
	assert_int(FixtureBooth.booth_id(game)).is_equal(-1)


## The fixture is the base mode but for the booth's three parts, the base mode's own resources.
func test_the_base_mode_with_the_booth_adds_only_its_three_parts() -> void:
	var base := load(BASE_MODE) as GameMode
	var mode: GameMode = BaseModeWithBooth.new()
	assert_int(mode.phases.size()).is_equal(base.phases.size())
	for i: int in base.phases.size():
		if base.phases[i].id != &"lobby":
			assert_object(mode.phases[i]).is_same(base.phases[i])
	var lobby := mode.find_phase(&"lobby").tick_systems
	assert_int(lobby.size()).is_equal(base.find_phase(&"lobby").tick_systems.size() + 2)
	assert_str(String((lobby[lobby.size() - 4] as StationTicks).kind.id)).is_equal("booth")
	assert_object(lobby[lobby.size() - 3]).is_instanceof(BoothTicks)
	# The base mode's own Lobby is untouched.
	assert_bool(BoothTicks.listed_in(base.find_phase(&"lobby"))).is_false()
	var row := mode.find_transition(&"lobby", LobbyPhase.ALL_READY)
	assert_object(row.actions[row.actions.size() - 1]).is_instanceof(StopBooth)
	assert_int(base.find_transition(&"lobby", LobbyPhase.ALL_READY).actions.size()).is_equal(
		row.actions.size() - 1
	)
	assert_array([mode.item_kinds, mode.roles, mode.settings]).is_equal(
		[base.item_kinds, base.roles, base.settings]
	)
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_the_shipped_booth_and_strip_carry_the_provisional_numbers() -> void:
	var booth := load(BOOTH) as StationKind
	assert_str(String(booth.spawn_tag)).is_equal("booth")
	assert_array([booth.radius_m, booth.height_m]).is_equal([1.2, 2.5])
	var start := booth.actions[0].effects[0] as StartBooth
	assert_object(start).is_not_null()
	assert_array([start.frames, start.countdown_s, start.gap_s]).is_equal([4, 3.0, 2.0])
	var strip := load(STRIP) as ItemKind
	assert_object(start.strip).is_same(strip)
	assert_array([strip.hands, strip.max_items, strip.vanish_seconds]).is_equal([1, 21, 120])


func test_a_press_in_the_hall_s_booth_prints_a_strip_for_each() -> void:
	var mode: GameMode = BaseModeWithBooth.new()
	var game := _in_booth(mode)
	FixtureBooth.press(game, P1, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	var start := FixtureBooth.start_in(mode)
	FixtureModes.run_ticks(game, start.countdown_ticks() + start.frames * start.gap_ticks() + 1)
	var flashes := FixtureBooth.steps_of(game, P2, BoothStepEvent.FLASH)
	assert_array(flashes).has_size(start.frames)
	for flash: BoothStepEvent in flashes:
		assert_array(FixtureBooth.peers_of(flash)).is_equal([P1, P2])
	var printed := FixtureBooth.steps_of(game, P2, BoothStepEvent.PRINTED)
	assert_array(printed).has_size(1)
	for k in 2:
		var strip: ItemState = game.state.items[printed[0].items[k]]
		assert_str(String(strip.kind.id)).is_equal("strip")
		assert_int(game.state.player([P1, P2][k] as int).held_item).is_equal(strip.id)
	assert_array(game.diagnostics).is_empty()


func test_ready_stops_the_session_and_countdown_done_clears_the_booth_and_its_strips() -> void:
	var mode: GameMode = BaseModeWithBooth.new()
	var game := _in_booth(mode)
	var start := FixtureBooth.start_in(mode)
	FixtureBooth.press(game, P1, 1)
	FixtureModes.run_ticks(game, start.countdown_ticks() + start.frames * start.gap_ticks() + 1)
	assert_int(game.state.items.size()).is_equal(2)
	FixtureBooth.press(game, P2, 1)
	assert_object(BoothSessions.running(game.state)).is_not_null()
	for peer: int in [P1, P2]:
		FixtureBaseMode.ready(game, peer)
	assert_str(game.phase_id()).is_equal("countdown")
	assert_object(BoothSessions.running(game.state)).is_null()
	assert_array(FixtureBooth.steps_of(game, P1, BoothStepEvent.STOPPED)).has_size(1)
	# A press in the countdown: the booth still stands, and nothing ticks it.
	FixtureBooth.press(game, P1, 2)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([&"unavailable"])
	for i in 200:
		if game.phase_id() != &"countdown":
			break
		FixtureModes.run_ticks(game, 1)
	assert_str(game.phase_id()).is_equal("loading")
	assert_bool(game.state.items.is_empty()).is_true()
	assert_int(FixtureBooth.booth_id(game)).is_equal(-1)
	assert_array(game.diagnostics).is_empty()
