extends RefCounted
## The levels of a mode that the bot scenarios play on (ARCHITECTURE §9.7): its lobby, a scenario's
## default map (BotScenario.played_map(): the mode's first test bench, the greybox, #767) and every
## map a scenario in content/scenarios/ or tests/fixtures/scenarios/ (the zone task's, #842) of
## that mode names.
## These are the levels the scenarios' fake world, one flat floor at y = 0, must describe truly;
## the mode's other maps (the House, #626) are played by people only.

const SCENARIOS_DIRS: Array[String] = [
	"res://content/scenarios/", "res://tests/fixtures/scenarios/"
]


## The paths, the lobby first, each once.
static func of(mode: GameMode) -> PackedStringArray:
	var paths := PackedStringArray()
	if not mode.lobby_level.is_empty():
		paths.append(mode.lobby_level)
	var unnamed := BotScenario.new()
	unnamed.mode = mode
	if not unnamed.played_map().is_empty():
		paths.append(unnamed.played_map())
	for folder: String in SCENARIOS_DIRS:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".tres"):
				continue
			var scenario := load(folder.path_join(file)) as BotScenario
			if scenario == null or scenario.mode == null:
				# A broken scenario would hide the map it names from the flatness check: say so.
				push_error("%s: not a scenario with a mode" % file)
				continue
			if scenario.mode.resource_path != mode.resource_path or scenario.map.is_empty():
				continue
			if not paths.has(scenario.map):
				paths.append(scenario.map)
	return paths


## The mode's levels that no scenario plays (the House, #626), which the runners read without
## floor snapping (GE12): their station markers stay where the scene puts them, since the flat
## fake finds no floor below y = 0. The scenario's own `map` counts as played, even when no
## scenario file names it.
static func unsnapped(mode: GameMode, map: String = "") -> PackedStringArray:
	var played := of(mode)
	if not map.is_empty() and not played.has(map):
		played.append(map)
	var rest := PackedStringArray()
	for path: String in MarkerReader.level_paths_of(mode):
		if not played.has(path):
			rest.append(path)
	return rest
