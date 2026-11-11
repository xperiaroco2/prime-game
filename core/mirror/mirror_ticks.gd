class_name MirrorTicks
extends TickSystem
## Gives up the mirror places that no longer hold and tells the places to whoever lacks them
## (#1394; ARCHITECTURE §7.1.23, §9.4.5), each tick of a phase that lists it: a place is given up
## when its player is no longer present, alive (or dead in the hall) and standing (gone, knocked
## down, dead, limp), its station is gone, or its last accepted position is outside the station's
## cylinder (walked away); all those of one tick go out as one MirrorPlaces. Then, while a place is
## held, a present player who was not told the places (a joiner) gets one MirrorPlaces, to everyone
## (the list is public and whole, so the others' copies change nothing); with none held a joiner
## needs none (a client starts with every place free). A phase that places a mirror lists it
## (problems()).
##
## Emits: MirrorPlaces (everyone). No demands.


func run(ctx: MatchContext) -> void:
	var held := Mirror.places(ctx.state).held
	var lost: Array[int] = []
	for station: int in held:
		if not holds(ctx, station, held[station]):
			lost.append(station)
	for station: int in lost:
		held.erase(station)
	if not lost.is_empty():
		Mirror.announce(ctx)
	elif not held.is_empty() and not Mirror.told_all(ctx.state):
		Mirror.announce(ctx)


## Whether `peer` still holds place `station` at `ctx.tick`.
func holds(ctx: MatchContext, station: int, peer: int) -> bool:
	var player := ctx.state.player(peer)
	if not Mirror.standing(player):
		return false
	var place: StationState = ctx.state.stations.get(station)
	return place != null and place.contains(player.position)


func emits() -> Array[Script]:
	return [MirrorPlacesEvent]


## The problems of `mode`'s mirror (UseMirror.check): a phase that places a station whose rules
## use a mirror place (a StationTicks of a kind holding a UseMirror) lists a MirrorTicks; every row
## from a phase that lists one into a phase that does not runs an EndMirror, so no place outlasts
## the phases that give them up. Empty when none.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	for phase: PhaseSpec in mode.phases:
		if phase == null or _ticking(phase):
			continue
		if _places_mirror(phase):
			found.append("phase %s places the mirror but lists no MirrorTicks" % phase.id)
	for row: Transition in mode.transitions:
		if row == null:
			continue
		var from := mode.find_phase(row.from)
		var to := mode.find_phase(row.to)
		if from == null or to == null or not _ticking(from) or _ticking(to):
			continue
		var ends := false
		for action: RuleEffect in row.actions:
			ends = ends or action is EndMirror
		if not ends:
			found.append(
				(
					"row %s -> %s runs no EndMirror: a mirror place would outlast it"
					% [row.from, row.to]
				)
			)
	return found


static func _ticking(phase: PhaseSpec) -> bool:
	for system: TickSystem in phase.tick_systems:
		if system is MirrorTicks:
			return true
	return false


static func _places_mirror(phase: PhaseSpec) -> bool:
	for system: TickSystem in phase.tick_systems:
		var placing := system as StationTicks
		if placing != null and Mirror.is_mirror_kind(placing.kind):
			return true
	return false
