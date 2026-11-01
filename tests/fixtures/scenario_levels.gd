extends RefCounted
## The levels of a mode that the bot scenarios play on (ARCHITECTURE §9.7): its lobby, a scenario's
## default map (BotScenario.played_map(): the mode's first test bench, the greybox, #767) and every
## map a scenario of that mode (in SCENARIOS_DIRS) names, but the maps with storeys.
## These are the levels the scenarios' fake world, one flat floor at y = 0, must describe truly.
## The maps with storeys (STOREYED_MAPS, the House, #626) are played by people, and by the scenarios
## that play their stations (#1197) in a fake world with storeys (world_of(), #1209).

const StoreyedWorld := preload("res://tests/fixtures/storeyed_world.gd")
## Where the bot scenarios live: the shipped modes' in content/scenarios/, and in
## tests/fixtures/scenarios/ those on a fixture mode, which shipped content must not name (the
## export leaves tests/ out): the knockdown scenarios on FixtureBaseModeWithMelee since the M8
## slice took the hitting out of the base mode's Round (#1497). `bots`, the scenario suite and the
## content tests read both (scenario_paths()).
const SCENARIOS_DIRS: Array[String] = [
	"res://content/scenarios/", "res://tests/fixtures/scenarios/"
]
const HOUSE := "res://levels/house/house.tscn"
## The maps a scenario may name that are not flat (#1197): the House (#626), the one map the station
## tasks play on (TaskType.maps). The scenarios play it in a fake world with its storeys and stairs
## (world_of(), #1209): the markers are read where the scene places them, never snapped (GE12), and
## a bot reaches a station on another storey only by a walk over the stairs.
const STOREYED_MAPS: Array[String] = [HOUSE]
## The House's storeys the fake world joins (house.tscn's levels): the basement, the ground floor
## and the second floor. The attic, which no task uses, is left out.
const HOUSE_STOREYS: Array[float] = [-3.2, 0.0, 3.2]
## The House's stairs in the fake world, each flight by its two ends in turn (StoreyedWorld): the
## pantry stairs from storage up to the ground floor (two flights and the landing between them) and
## the external stairs from the terrace up to the balcony (one flight). The ends follow the walks
## over the real stairs in house_cooking_test's PANTRY_UP and house_photo_test's UPSTAIRS, so a
## scenario's waypoints over them are the ones a player takes; the fake knows nothing else of them.
const HOUSE_FLIGHTS: Array[Vector3] = [
	Vector3(25, -3.2, 29),
	Vector3(25, -1.6, 25),
	Vector3(24.4, -1.6, 25),
	Vector3(27.6, -1.6, 25),
	Vector3(27, -1.6, 25),
	Vector3(27, 0, 29),
	Vector3(39, 0, 14.4),
	Vector3(39, 3.2, 21.6),
]
## Every flight's width in the fake world: the bots walk up its middle.
const FLIGHT_WIDTH_M := 1.2


## The fake world a scenario plays in (ARCHITECTURE §9.7): the House's storeys and stairs on the
## House (#1209), else one flat floor at y = 0.
static func world_of(scenario: BotScenario) -> WorldQuery:
	if scenario != null and scenario.mode != null and scenario.played_map() == HOUSE:
		return StoreyedWorld.new(HOUSE, HOUSE_STOREYS, HOUSE_FLIGHTS, FLIGHT_WIDTH_M)
	return FlatWorldQuery.new()


## The paths, the lobby first, each once.
static func of(mode: GameMode) -> PackedStringArray:
	var paths := PackedStringArray()
	if not mode.lobby_level.is_empty():
		paths.append(mode.lobby_level)
	var unnamed := BotScenario.new()
	unnamed.mode = mode
	if not unnamed.played_map().is_empty():
		paths.append(unnamed.played_map())
	for path: String in scenario_paths():
		var scenario := load(path) as BotScenario
		if scenario == null or scenario.mode == null:
			# A broken scenario would hide the map it names from the flatness check: say so.
			push_error("%s: not a scenario with a mode" % path)
			continue
		if scenario.mode.resource_path != mode.resource_path or scenario.map.is_empty():
			continue
		if STOREYED_MAPS.has(scenario.map):
			continue
		if not paths.has(scenario.map):
			paths.append(scenario.map)
	return paths


## Every bot scenario file in SCENARIOS_DIRS (measurements included), sorted by path.
static func scenario_paths() -> PackedStringArray:
	var found := PackedStringArray()
	for folder: String in SCENARIOS_DIRS:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file: String in DirAccess.get_files_at(folder):
			if file.ends_with(".tres"):
				found.append(folder.path_join(file))
	found.sort()
	return found


## The path of the scenario named `name` (its file name, with or without `.tres`): the first of
## SCENARIOS_DIRS that holds it, else "".
static func scenario_path(name: String) -> String:
	var file := name.trim_suffix(".tres") + ".tres"
	for folder: String in SCENARIOS_DIRS:
		var path := folder.path_join(file)
		if ResourceLoader.exists(path):
			return path
	return ""


## The mode's levels the runners read without floor snapping (GE12): those no scenario plays and
## the maps with storeys (the House, #626). Their station markers stay where the scene puts them,
## since the flat fake finds no floor below its one floor. The scenario's own flat `map` counts as
## played, even when no scenario file names it.
static func unsnapped(mode: GameMode, map: String = "") -> PackedStringArray:
	var played := of(mode)
	if not map.is_empty() and not played.has(map) and not STOREYED_MAPS.has(map):
		played.append(map)
	var rest := PackedStringArray()
	for path: String in MarkerReader.level_paths_of(mode):
		if not played.has(path):
			rest.append(path)
	return rest
