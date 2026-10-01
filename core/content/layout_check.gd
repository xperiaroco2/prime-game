class_name LayoutCheck
extends RefCounted
## The mode check with the levels' layouts (ARCHITECTURE §9.1, second part), which Match runs on
## creation with the layouts server/ (or a test) hands in. Errors:
## - a level of the mode without a layout;
## - a spawn tag that a row's action places on and a level lacks: the lobby for rows into a lobby
##   phase, every map for rows into a map phase (the tags an action names at the default settings
##   and the mode's maximum of players, §9.4), or that a tick system of a phase played on the
##   level places on (LifeTicks' Respawn: `respawn` markers on every map, M4-3);
## - a marker with two tags (the same position under two tags; §9.6: a marker carries one tag);
## - a lobby with fewer `lobby_player` markers than the mode's maximum of players, since a joiner
##   and `End -> Lobby` each put a player on a marker of its own.

## The spawn tag of the lobby's player markers (§9.3).
const LOBBY_PLAYER := &"lobby_player"


## Every problem of `mode` with `layouts` (level path -> layout); empty when they fit.
static func run(mode: GameMode, layouts: Dictionary[String, LevelLayout]) -> PackedStringArray:
	var found := PackedStringArray()
	if mode == null:
		return found
	if not mode.lobby_level.is_empty():
		var lobby: LevelLayout = layouts.get(mode.lobby_level)
		if lobby == null:
			found.append("no layout for the lobby %s" % mode.lobby_level)
		else:
			_check_level(mode, mode.lobby_level, lobby, PhaseSpec.Level.LOBBY, found)
			if lobby.count(LOBBY_PLAYER) < mode.max_players:
				found.append(
					(
						"the lobby %s has %d %s marker(s), fewer than the mode's %d players"
						% [
							mode.lobby_level,
							lobby.count(LOBBY_PLAYER),
							LOBBY_PLAYER,
							mode.max_players
						]
					)
				)
	for map: String in mode.maps:
		var layout: LevelLayout = layouts.get(map)
		if layout == null:
			found.append("no layout for the map %s" % map)
		else:
			_check_level(mode, map, layout, PhaseSpec.Level.MAP, found)
	return found


## What the actions of every row into a phase played on `level`, and the tick systems of those
## phases, demand, summed (§9.4): the fit check of `all_ready` compares this for the map with the
## chosen map's markers. `id_sets` are the set settings (the host's bans of task types); empty
## means every set is empty.
static func demands_of(
	mode: GameMode,
	level: PhaseSpec.Level,
	settings: Dictionary[StringName, int],
	players: int,
	id_sets: Dictionary[StringName, PackedStringArray] = {}
) -> Demands:
	var demands := Demands.new(mode)
	demands.id_sets = id_sets.duplicate()
	for row: Transition in _rows_into(mode, level):
		for action: RuleEffect in row.actions:
			if action != null:
				action.add_demands(settings, players, demands)
	# A tick system's markers serve every phase it runs in (a Respawn's marker is not used up), so
	# the phases' tick-system demands take the most of any one phase per tag, not their sum.
	var ticking := Demands.new(mode)
	for spec: PhaseSpec in _phases_on(mode, level):
		var one := Demands.new(mode)
		one.id_sets = demands.id_sets
		for system: TickSystem in spec.tick_systems:
			if system != null:
				system.add_demands(settings, players, one)
		for tag: StringName in one.markers:
			ticking.markers[tag] = maxi(ticking.markers.get(tag, 0) as int, one.markers[tag])
		for station: StringName in one.colours:
			ticking.colours[station] = maxi(
				ticking.colours.get(station, 0) as int, one.colours[station]
			)
			ticking.palettes[station] = one.palettes[station]
	for tag: StringName in ticking.markers:
		demands.add_markers(tag, ticking.markers[tag])
	for station: StringName in ticking.colours:
		demands.colours[station] = demands.colours.get(station, 0) + ticking.colours[station]
		demands.palettes[station] = ticking.palettes[station]
	return demands


static func _check_level(
	mode: GameMode,
	path: String,
	layout: LevelLayout,
	level: PhaseSpec.Level,
	found: PackedStringArray
) -> void:
	var defaults := mode.default_settings()
	for row: Transition in _rows_into(mode, level):
		var demands := Demands.new(mode)
		for action: RuleEffect in row.actions:
			if action != null:
				action.add_demands(defaults, mode.max_players, demands)
		var tags: Array[StringName] = []
		tags.assign(demands.markers.keys())
		tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for tag: StringName in tags:
			if layout.count(tag) == 0:
				found.append(
					(
						"%s has no %s marker, which the row %s, %s places on"
						% [path, tag, row.from, row.outcome]
					)
				)
	for spec: PhaseSpec in _phases_on(mode, level):
		var demands := Demands.new(mode)
		for system: TickSystem in spec.tick_systems:
			if system != null:
				system.add_demands(defaults, mode.max_players, demands)
		for tag: StringName in demands.markers:
			if demands.markers[tag] > 0 and layout.count(tag) == 0:
				found.append(
					(
						"%s has no %s marker, which a tick system of phase %s places on"
						% [path, tag, spec.id]
					)
				)
	var tag_at: Dictionary[Vector3, StringName] = {}
	for tag: StringName in layout.tags():
		for position: Vector3 in layout.positions(tag):
			if tag_at.has(position) and tag_at[position] != tag:
				found.append(
					(
						"%s has a marker at %s with two tags, %s and %s"
						% [path, position, tag_at[position], tag]
					)
				)
			else:
				tag_at[position] = tag


## The phases played on `level`, in the mode's order.
static func _phases_on(mode: GameMode, level: PhaseSpec.Level) -> Array[PhaseSpec]:
	var found: Array[PhaseSpec] = []
	for spec: PhaseSpec in mode.phases:
		if spec != null and spec.level == level:
			found.append(spec)
	return found


static func _rows_into(mode: GameMode, level: PhaseSpec.Level) -> Array[Transition]:
	var found: Array[Transition] = []
	for row: Transition in mode.transitions:
		if row == null:
			continue
		var to := mode.find_phase(row.to)
		if to != null and to.level == level:
			found.append(row)
	return found
