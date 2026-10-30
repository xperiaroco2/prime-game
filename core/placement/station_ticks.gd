class_name StationTicks
extends TickSystem
## A station of the phase's level that no task type deals (#1390: the lobby's tap; ARCHITECTURE
## §9.4.5): every tick of a phase that lists it, when the match holds no station of `kind`, one is
## placed on the first `kind.spawn_tag` marker of the phase's level (MatchState.add_station; the
## kind's first palette colour, else white) and announced by StationPlaced (everyone). So it stands
## from the first Lobby tick, again after End -> Lobby's ResetMatch, and stays through a cancelled
## countdown; ClearStations removes it at the lobby's end. A joiner learns it from JoinRules.hello's
## replay. The station's rules are `kind.actions` (Interact), which ModeCheck checks as a task
## type's (Stations.kinds_in lists the kind). A level with no such marker is a rule error, logged
## once per match (LayoutCheck refuses that level first: the demand below).
##
## Emits: StationPlaced (everyone). Demands: exactly one `kind.spawn_tag` marker on the phase's
## level.

## Its key in MatchState's per-part state (§9.1): the kinds whose missing marker was logged.
const PART_KEY := &"station_ticks"

## The station kind placed: an id and a spawn tag.
@export var kind: StationKind


func run(ctx: MatchContext) -> void:
	if kind == null:
		return
	for id: int in ctx.state.stations:
		if ctx.state.stations[id].kind == kind:
			return
	var spots := (
		ctx.layout.positions(kind.spawn_tag) if ctx.layout != null else PackedVector3Array()
	)
	if spots.is_empty():
		var logged := ctx.state.part_state(PART_KEY, func() -> RefCounted: return Logged.new())
		if not (logged as Logged).kinds.has(kind.id):
			(logged as Logged).kinds[kind.id] = true
			ctx.error("StationTicks: the level has no %s marker for %s" % [kind.spawn_tag, kind.id])
		return
	var colour := kind.palette[0] if not kind.palette.is_empty() else Color.WHITE
	var station := ctx.state.add_station(kind, spots[0], colour)
	ctx.emit(StationPlacedEvent.new(station.id, kind.id, station.colour, station.position))


func emits() -> Array[Script]:
	return [StationPlacedEvent]


func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	if kind != null and kind.spawn_tag != &"":
		into.add_markers(kind.spawn_tag, 1, true)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if kind == null or kind.id == &"" or kind.spawn_tag == &"":
		found.append("StationTicks needs a station kind with an id and a spawn tag")
	return found


## The kinds already logged as missing their marker (once per match: ResetMatch clears it).
class Logged:
	extends RefCounted
	var kinds: Dictionary[StringName, bool] = {}
