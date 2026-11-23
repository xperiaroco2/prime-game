class_name FixtureBaseModeWithBooth
extends GameMode
## The base mode with the photo booth M8 hides (#1680, the engineer's "hide until M9"): the
## shipped base mode (`content/modes/base_mode.tres`, read when this loads, so it never drifts
## from it) plus the booth's three parts, as the base mode had them (#1396) and as M9 brings them
## back: the Lobby's StationTicks of the booth kind and its BoothTicks, before the mirror's two
## systems, and StopBooth on the Lobby's all_ready row. The booth's tests on the hall's real layout
## and the bot scenario `booth_strip_of_frames` play here, so they keep checking the booth while
## the game ships without it. Loaded through `base_mode_with_booth.tres` (PATH), so a bot scenario
## can name it as its mode and a command log replays it by its path.

const PATH := "res://tests/fixtures/booth/base_mode_with_booth.tres"
const BASE_MODE := "res://content/modes/base_mode.tres"
const BOOTH := "res://content/stations/booth.tres"


func _init() -> void:
	var base := load(BASE_MODE) as GameMode
	for property: Dictionary in base.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name: String = property["name"]
			var value: Variant = base.get(property_name)
			# Its own arrays: the copies below leave the cached shipped mode's alone (the parts in
			# them are shared, as the shipped mode's own).
			if value is Array:
				value = (value as Array).duplicate()
			elif value is Dictionary:
				value = (value as Dictionary).duplicate()
			set(property_name, value)
	for index: int in phases.size():
		if phases[index].id == &"lobby":
			phases[index] = _with_booth_ticks(phases[index])
	for index: int in transitions.size():
		var row := transitions[index]
		if row.from == &"lobby" and row.outcome == LobbyPhase.ALL_READY:
			transitions[index] = _with_stop(row)


## The mode, loaded from PATH.
static func mode() -> GameMode:
	return load(PATH) as GameMode


## A copy of the Lobby `phase` with the booth's StationTicks and BoothTicks before its last two
## systems (the mirror's places and ticks).
static func _with_booth_ticks(phase: PhaseSpec) -> PhaseSpec:
	var lobby := phase.duplicate() as PhaseSpec
	var placing := StationTicks.new()
	placing.kind = load(BOOTH) as StationKind
	var systems: Array[TickSystem] = phase.tick_systems.duplicate()
	systems.insert(systems.size() - 2, placing)
	systems.insert(systems.size() - 2, BoothTicks.new())
	lobby.tick_systems = systems
	return lobby


static func _with_stop(row: Transition) -> Transition:
	var stops := row.duplicate() as Transition
	var stopping: Array[RuleEffect] = row.actions.duplicate()
	stopping.append(StopBooth.new())
	stops.actions = stopping
	return stops
