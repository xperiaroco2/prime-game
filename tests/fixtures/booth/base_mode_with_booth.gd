class_name BaseModeWithBooth
extends GameMode
## The base mode with the photo booth M8 hides (#1680, the engineer's "hide until M9"): its three
## parts added back, as the base mode had them (#1396) and as M9 brings them back. The Lobby's
## StationTicks of the booth kind and its BoothTicks, before the mirror's two systems; StopBooth on
## the Lobby's all_ready row. The booth's tests on the hall's real layout and the bots scenario
## `booth_strip_of_frames` run on it (base_mode_with_booth.tres), so they keep checking the booth
## while the game ships without it. Every other part is the base mode's own, shared, never changed:
## the Lobby phase and the row are copies.

const BASE := "res://content/modes/base_mode.tres"
const BOOTH := "res://content/stations/booth.tres"


func _init() -> void:
	var base := load(BASE) as GameMode
	for property: Dictionary in base.get_property_list():
		var key := property["name"] as String
		var usage := property["usage"] as int
		if (usage & PROPERTY_USAGE_STORAGE) == 0 or key == "script" or key.begins_with("resource_"):
			continue
		set(key, base.get(key))
	var with_phases: Array[PhaseSpec] = []
	for phase: PhaseSpec in base.phases:
		with_phases.append(_with_booth_ticks(phase) if phase.id == &"lobby" else phase)
	phases = with_phases
	var with_rows: Array[Transition] = []
	for row: Transition in base.transitions:
		var stops := row.from == &"lobby" and row.outcome == LobbyPhase.ALL_READY
		with_rows.append(_with_stop(row) if stops else row)
	transitions = with_rows


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
	var actions: Array[RuleEffect] = row.actions.duplicate()
	actions.append(StopBooth.new())
	stops.actions = actions
	return stops
