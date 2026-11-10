class_name Respawn
extends RuleEffect
## The respawn (ARCHITECTURE §3.4, §9.4; vision revision 1, V6): the actor, dead, comes back at a
## respawn marker of `tag` (`respawn` in the base mode) in the current level. The marker is drawn
## uniformly with the RNG purpose `rng_purpose` (`respawn`) from the free ones: a marker is free
## when no living or downed player stands within `PlayerRules.respawn_free_m` of it (from its
## feet). When none is free it is drawn from all of them (the engineer's answer 5 on PR #133: a
## respawn is never delayed by where others stand; players push apart, §7.1). LifeRules.respawn
## then does the rest: the body goes, full health and stamina, empty hands, a new epoch, the
## marker's facing (#1522; a marker with none leaves the player's own) and invulnerability.
##
## LifeTicks runs it, with the dead player as the actor, when its respawn time
## (`PlayerRules.respawn_s` after the death) runs out; it is held by LifeTicks, not by a row, so
## LifeTicks forwards its demand.
##
## Emits: Respawned (everyone; it removes the body, E26), then Correction (that player only), and
## SelfStatus at the end of the tick (that player). Demands: one `tag` marker on every map, at least
## (ARCHITECTURE §9.4); the layout check and the lobby's fit check then refuse a map with none.

## The spawn tag of the respawn markers (`respawn`). Empty fails the mode check: the data sets it.
@export var tag: StringName
## The RNG purpose of the draw (`respawn`). Empty fails the mode check: the data sets it.
@export var rng_purpose: StringName
## Seconds a drone prints the player back before it stands living (#1489; placeholder, "not a
## decision"; its bounds, 0 to 10, too). 0: at once, Respawned with no PrintStarted.
@export var print_s := 0.0
## The spawn tag of the markers in the dead's hall (`dead`); empty: this phase has no hall, the dead
## wait where they died and send no intents (the lobby).
@export var hall_tag: StringName
## The RNG purpose of the draw of a hall marker. Empty fails the mode check when hall_tag is set.
@export var hall_rng_purpose: StringName
## How far from the middle of the hall's markers a dead player may be (placeholder, "not a
## decision"): a claim or a named target beyond it is refused. Over 0 when hall_tag is set.
@export var hall_radius_m := 0.0


func run(ctx: MatchContext) -> void:
	var dead := ctx.actor_state()
	if dead == null or dead.life != PlayerState.Life.DEAD:
		ctx.error("Respawn: player %d is not dead" % ctx.actor)
		return
	if ctx.state.player_rules == null:
		ctx.error("Respawn: the mode has no PlayerRules")
		return
	if ctx.layout == null:
		ctx.error("Respawn: no layout for the current level")
		return
	var spots := ctx.layout.positions(tag)
	if spots.is_empty():
		ctx.error("Respawn: the level has no %s marker" % tag)
		return
	var pool := free_indexes(ctx.state, spots)
	if pool.is_empty():
		for i in spots.size():
			pool.append(i)
	var drawn := pool[ctx.rng(rng_purpose).randi_range(0, pool.size() - 1)]
	var facing := ctx.layout.facing_at(tag, drawn)
	if print_s > 0.0:
		LifeRules.begin_print(ctx, ctx.actor, spots[drawn], facing, print_s)
	else:
		LifeRules.respawn(ctx, ctx.actor, spots[drawn], facing)


## The dead actor goes to a random marker of this phase's hall, if the phase has one (#1489): it
## stands there with the hall's middle and radius (PlayerState.hall_holds), a new epoch and a
## Correction to it alone. Its body stays where it died (MatchState.bodies), and so do the items it
## dropped. No layout or no marker (LayoutCheck refuses a map that lacks one): the dead waits where
## it died, as in a phase with no hall.
func send_to_hall(ctx: MatchContext) -> void:
	if hall_tag.is_empty() or ctx.layout == null:
		return
	var spots := ctx.layout.positions(hall_tag)
	if spots.is_empty():
		return
	var dead := ctx.actor_state()
	var drawn := ctx.rng(hall_rng_purpose).randi_range(0, spots.size() - 1)
	var middle := Vector3.ZERO
	for spot: Vector3 in spots:
		middle += spot
	dead.in_hall = true
	dead.hall_center = middle / spots.size()
	dead.hall_radius_m = hall_radius_m
	dead.position = spots[drawn]
	dead.velocity = Vector3.ZERO
	var facing := ctx.layout.facing_at(hall_tag, drawn)
	if facing != Vector3.ZERO:
		dead.facing = facing
	dead.epoch += 1
	ctx.emit(CorrectionEvent.new(ctx.actor, dead.epoch, dead.position, dead.velocity, facing))


## The markers of `spots` with no living, downed or printing player within the free radius, in
## level order.
static func free_markers(state: MatchState, spots: PackedVector3Array) -> PackedVector3Array:
	var found := PackedVector3Array()
	for i: int in free_indexes(state, spots):
		found.append(spots[i])
	return found


## The indexes in `spots` of the free markers (free_markers), in level order.
static func free_indexes(state: MatchState, spots: PackedVector3Array) -> PackedInt32Array:
	var radius := state.player_rules.respawn_free_m
	var found := PackedInt32Array()
	for i in spots.size():
		var taken := false
		for peer: int in state.peers():
			var player := state.players[peer]
			var standing := (
				player.life == PlayerState.Life.ALIVE
				or player.life == PlayerState.Life.DOWNED
				or player.is_printing()
			)
			if standing and player.position.distance_to(spots[i]) <= radius:
				taken = true
				break
		if not taken:
			found.append(i)
	return found


func emits() -> Array[Script]:
	return [PrintStartedEvent, RespawnedEvent, CorrectionEvent, SelfStatusEvent]


func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	into.add_markers(tag, 1)
	if not hall_tag.is_empty():
		into.add_markers(hall_tag, 1)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if tag.is_empty():
		found.append("Respawn has no tag")
	if rng_purpose.is_empty():
		found.append("Respawn has no rng_purpose")
	if print_s < 0.0 or print_s > 10.0:
		found.append("Respawn print_s must be 0 to 10")
	if not hall_tag.is_empty():
		if hall_rng_purpose.is_empty():
			found.append("Respawn has a hall_tag but no hall_rng_purpose")
		if hall_radius_m <= 0.0:
			found.append("Respawn has a hall_tag but no hall_radius_m")
	return found
