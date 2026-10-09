extends RefCounted
## The levels of a mode that the bot scenarios play on (ARCHITECTURE §9.7): its lobby, its first
## map (a scenario's default) and every map a scenario in content/scenarios/ of that mode names.
## These are the levels the scenarios' fake world, one flat floor at y = 0, must describe truly;
## the mode's other maps (the House, #626) are played by people only.

const SCENARIOS_DIR := "res://content/scenarios/"


## The paths, the lobby first, each once.
static func of(mode: GameMode) -> PackedStringArray:
	var paths := PackedStringArray()
	if not mode.lobby_level.is_empty():
		paths.append(mode.lobby_level)
	if not mode.maps.is_empty():
		paths.append(mode.maps[0])
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
		if not paths.has(scenario.map):
			paths.append(scenario.map)
	return paths
