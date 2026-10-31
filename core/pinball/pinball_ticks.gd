class_name PinballTicks
extends TickSystem
## Ends the pinball game that no longer holds and tells the machine's state to whoever lacks it
## (#1398; ARCHITECTURE §7.1.22, §9.4.5), each tick of a phase that lists it: the game ends
## (Pinball.end) when the seated player is no longer present, alive and standing (gone, knocked
## down, dead, limp), its station is gone, or its last accepted position is outside the station's
## cylinder (walked away). Then, once the session started a game, a present player who was not told
## the current state (a joiner; everyone after ResetMatch made a new game state, so every peer sees
## the best score that survived it) gets one PinballState, to everyone (the state is public and
## whole, so the others' copies change nothing). A phase that holds the machine or accepts Flippers
## lists it (problems()).
##
## Emits: PinballState (everyone). No demands.


func run(ctx: MatchContext) -> void:
	var played := Pinball.game(ctx.state)
	if played.player >= 0 and not holds(ctx, played):
		Pinball.end(ctx)
	elif Pinball.started(ctx.state) and not Pinball.told_all(ctx.state):
		Pinball.announce(ctx)


## Whether the running game `played` still holds at `ctx.tick`.
func holds(ctx: MatchContext, played: Pinball.Machine) -> bool:
	var player := ctx.state.player(played.player)
	if not Pinball.standing(player):
		return false
	var station: StationState = ctx.state.stations.get(played.station)
	return station != null and station.contains(player.position)


func emits() -> Array[Script]:
	return [PinballStateEvent]


## The problems of `mode`'s pinball (UsePinball.check): a phase that places a station whose rules
## use the machine (a StationTicks of a kind holding a UsePinball) or accepts Flippers lists a
## PinballTicks; every row from a phase that lists one into a phase that does not runs an
## EndPinball, so no seat outlasts the phases that end games. Empty when none.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	for phase: PhaseSpec in mode.phases:
		if phase == null or _ticking(phase):
			continue
		if _places_machine(phase):
			found.append("phase %s places the pinball but lists no PinballTicks" % phase.id)
		elif phase.senders_of(Intents.FLIPPERS) != 0:
			found.append("phase %s accepts Flippers but lists no PinballTicks" % phase.id)
	for row: Transition in mode.transitions:
		if row == null:
			continue
		var from := mode.find_phase(row.from)
		var to := mode.find_phase(row.to)
		if from == null or to == null or not _ticking(from) or _ticking(to):
			continue
		var ends := false
		for action: RuleEffect in row.actions:
			ends = ends or action is EndPinball
		if not ends:
			found.append(
				(
					"row %s -> %s runs no EndPinball: a pinball seat would outlast it"
					% [row.from, row.to]
				)
			)
	return found


static func _ticking(phase: PhaseSpec) -> bool:
	for system: TickSystem in phase.tick_systems:
		if system is PinballTicks:
			return true
	return false


static func _places_machine(phase: PhaseSpec) -> bool:
	for system: TickSystem in phase.tick_systems:
		var placing := system as StationTicks
		if placing == null or placing.kind == null:
			continue
		for rule: Rule in placing.kind.actions:
			if rule == null:
				continue
			for effect: RuleEffect in rule.effects:
				if effect is UsePinball:
					return true
	return false
