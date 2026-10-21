extends RefCounted
## The levels of a mode that the bot scenarios play on (ARCHITECTURE §9.7): its lobby, a scenario's
## default map (BotScenario.played_map(): the mode's first test bench, the greybox, #767) and every
## map a scenario in content/scenarios/ of that mode names, but the maps with storeys.
## These are the levels the scenarios' fake world, one flat floor at y = 0, must describe truly.
## The maps with storeys (STOREYED_MAPS, the House, #626) are played by people, and by the scenarios
## that play their stations one storey at a time (#1197).

const SCENARIOS_DIR := "res://content/scenarios/"
## The maps a scenario may name that are not flat (#1197): the House (#626), the one map the station
## tasks play on (TaskType.maps). The fake world stays one flat floor, at the scenario's floor_y, so
## a scenario plays one storey of it (the ground floor at 0, the basement at -3.2): the markers are
## read where the scene places them, never snapped (GE12), and the bots reach only the stations
## whose cylinders stand on that floor.
const STOREYED_MAPS: Array[String] = ["res://levels/house/house.tscn"]


## The paths, the lobby first, each once.
static func of(mode: GameMode) -> PackedStringArray:
	var paths := PackedStringArray()
	if not mode.lobby_level.is_empty():
		paths.append(mode.lobby_level)
	var unnamed := BotScenario.new()
	unnamed.mode = mode
	if not unnamed.played_map().is_empty():
		paths.append(unnamed.played_map())
	for file in DirAccess.get_files_at(SCENARIOS_DIR):
		if not file.ends_with(".tres"):
			continue
		var scenario := load(SCENARIOS_DIR.path_join(file)) as BotScenario
		if scenario == null or scenario.mode == null:
			# A broken scenario would hide the map it names from the flatness check: say so.
			push_error("%s: not a scenario with a mode" % file)
			continue
		if scenario.mode.resource_path != mode.resource_path or scenario.map.is_empty():
			continue
		if STOREYED_MAPS.has(scenario.map):
			continue
		if not paths.has(scenario.map):
			paths.append(scenario.map)
	return paths


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
