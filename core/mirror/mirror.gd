class_name Mirror
extends RefCounted
## The lobby's mirror (#1394; ARCHITECTURE §7.1.24, §9.4; GDD §3 "The mirror"): one wide mirror
## with several places, each a station of the mirror's kind on its own `mirror` marker (StationTicks
## with `every_marker`), so the places are level data. A player's Interact at a free place takes it
## (UseMirror), its own place's Interact gives it up, and an Interact at another place moves it
## there; a place another player holds refuses `unavailable` (MirrorFree). The host holds which
## place each player uses: per-part state (MatchState.part_state, cleared by ResetMatch), told to
## everyone whole as MirrorPlaces on every change (announce()); who stands where is public, as
## the pinball's seat is.
##
## Holding a place is what lets a player change its body colour (JoinRules.set_profile: in a phase
## that lists MirrorTicks, gates_colour(), a SetProfile that changes the colour from a player not
## standing at a place it holds, at_place(), is `not_at_mirror`). In M8 the mirror changes only the
## colour (the engineer, the M8 sit-down of 2026-11-08); clothes and body shapes come after M8.
##
## A place is given up (MirrorTicks) when its player is no longer present, alive (or dead in the
## hall) and standing, its station is gone, or its last accepted position is outside the station's
## cylinder (walked away); and through EndMirror on a row out of the phases that list MirrorTicks,
## so no place survives into a match.

## Its key in MatchState's per-part state.
const PART_KEY := &"mirror"
## The reason a colour change gets from a player at no mirror place (JoinRules.set_profile).
const NOT_AT_MIRROR := &"not_at_mirror"
## The most places a mirror holds in use at once: MirrorPlaces' list cap on the wire
## (WireSchema.MAX_MIRROR_PLACES, which a unit test pins equal).
const MAX_PLACES := 16


## The places in use: station id -> the peer holding it.
class Places:
	extends RefCounted
	var held: Dictionary[int, int] = {}
	## The players present at the last MirrorPlaces: MirrorTicks tells the places again when one is
	## missing (a joiner).
	var told: Dictionary[int, bool] = {}


## The mirror's places, made on first use.
static func places(state: MatchState) -> Places:
	return state.part_state(PART_KEY, func() -> RefCounted: return Places.new()) as Places


## The station of the place `peer` holds, or -1.
static func place_of(state: MatchState, peer: int) -> int:
	var held := places(state).held
	for station: int in held:
		if held[station] == peer:
			return station
	return -1


## The peer holding place `station`, or -1.
static func holder(state: MatchState, station: int) -> int:
	return places(state).held.get(station, -1)


## Whether `kind` is a mirror place's kind: its rules hold a UseMirror.
static func is_mirror_kind(kind: StationKind) -> bool:
	if kind == null:
		return false
	for rule: Rule in kind.actions:
		if rule == null:
			continue
		for effect: RuleEffect in rule.effects:
			if effect is UseMirror:
				return true
	return false


## Whether the colour changes only at the mirror in `ctx`'s phase: the phase lists MirrorTicks
## (MirrorTicks.problems makes every phase that places the mirror list it). The phase's data, not
## the stations standing, so the tick before its StationTicks first runs (a match's start, End ->
## Lobby) is no gap.
static func gates_colour(ctx: MatchContext) -> bool:
	var spec := ctx.phase_spec()
	if spec == null:
		return false
	for system: TickSystem in spec.tick_systems:
		if system is MirrorTicks:
			return true
	return false


## Whether `peer` holds a mirror place and still stands at it now (MirrorTicks.holds: present,
## standing and inside the place's cylinder), so a holder who walked off this tick, before
## MirrorTicks gives the place up at the tick's end, changes no colour.
static func at_place(state: MatchState, peer: int) -> bool:
	var station := place_of(state, peer)
	return station >= 0 and MirrorTicks.holds(state, station, peer)


## Whether `player` may keep a place: present, alive and standing (not limp); Pinball.standing's
## "dead in the hall" never applies, as the places stand only in the lobby's phases.
static func standing(player: PlayerState) -> bool:
	return Pinball.standing(player)


## The actor takes place `station`, giving up the one it held. One MirrorPlaces. A mirror never
## has more places in use than MAX_PLACES, the wire's cap: a take past it is a level error
## (more `mirror` markers than the cap) and takes nothing.
static func take(ctx: MatchContext, station: int) -> void:
	var held := places(ctx.state).held
	var before := place_of(ctx.state, ctx.actor)
	if before < 0 and held.size() >= MAX_PLACES:
		ctx.error("Mirror: more than %d places in use" % MAX_PLACES)
		return
	if before >= 0:
		held.erase(before)
	held[station] = ctx.actor
	announce(ctx)


## Place `station` is given up. One MirrorPlaces; nothing when nobody holds it.
static func leave(ctx: MatchContext, station: int) -> void:
	var held := places(ctx.state).held
	if not held.has(station):
		return
	held.erase(station)
	announce(ctx)


## Every place is given up. One MirrorPlaces; nothing when none is held.
static func leave_all(ctx: MatchContext) -> void:
	var held := places(ctx.state).held
	if held.is_empty():
		return
	held.clear()
	announce(ctx)


## Every place in use goes to everyone as one MirrorPlaces, in station order.
static func announce(ctx: MatchContext) -> void:
	var kept := places(ctx.state)
	var stations: Array[int] = []
	stations.assign(kept.held.keys())
	stations.sort()
	var peers := PackedInt32Array()
	for station: int in stations:
		peers.append(kept.held[station])
	ctx.emit(MirrorPlacesEvent.new(PackedInt32Array(stations), peers))
	kept.told.clear()
	for peer: int in ctx.state.present_peers():
		kept.told[peer] = true


## Whether every present player was told the places as they are.
static func told_all(state: MatchState) -> bool:
	var kept := places(state)
	for peer: int in state.present_peers():
		if not kept.told.has(peer):
			return false
	return true
