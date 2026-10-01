class_name Respawn
extends RuleEffect
## The respawn (ARCHITECTURE §3.4, §9.4; vision revision 1, V6): the actor, dead, comes back at a
## respawn marker of `tag` (`respawn` in the base mode) in the current level. The marker is drawn
## uniformly with the RNG purpose `rng_purpose` (`respawn`) from the free ones: a marker is free
## when no living or downed player stands within `PlayerRules.respawn_free_m` of it (from its
## feet). When none is free it is drawn from all of them (the engineer's answer 5 on PR #133: a
## respawn is never delayed by where others stand; players push apart, §7.1). LifeRules.respawn
## then does the rest: the body goes, full health and stamina, empty hands, a new epoch and
## invulnerability.
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
	var pool := free_markers(ctx.state, spots)
	if pool.is_empty():
		pool = spots
	var drawn := ctx.rng(rng_purpose).randi_range(0, pool.size() - 1)
	LifeRules.respawn(ctx, ctx.actor, pool[drawn])


## The markers of `spots` with no living or downed player within the free radius, in level order.
static func free_markers(state: MatchState, spots: PackedVector3Array) -> PackedVector3Array:
	var radius := state.player_rules.respawn_free_m
	var found := PackedVector3Array()
	for spot: Vector3 in spots:
		var taken := false
		for peer: int in state.peers():
			var player := state.players[peer]
			var standing := (
				player.life == PlayerState.Life.ALIVE or player.life == PlayerState.Life.DOWNED
			)
			if standing and player.position.distance_to(spot) <= radius:
				taken = true
				break
		if not taken:
			found.append(spot)
	return found


func emits() -> Array[Script]:
	return [RespawnedEvent, CorrectionEvent, SelfStatusEvent]


func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	into.add_markers(tag, 1)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if tag.is_empty():
		found.append("Respawn has no tag")
	if rng_purpose.is_empty():
		found.append("Respawn has no rng_purpose")
	return found
