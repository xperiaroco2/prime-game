class_name Snapshots
extends RefCounted
## One peer's snapshot of one tick, built from visibility rules per entity (ARCHITECTURE §5): the
## avatar of every living or downed player reaches every player, the dead included (a spectator's
## camera is built from these); a dead player has no avatar, so no snapshot holds one; bodies and
## items reach everyone; nobody gets their own avatar, except a knocked-down or limp player (the
## knockdown rework's KE5 (a); #1393): its own place, where the host's physics may carry it, and
## nothing hidden. The
## avatar's flag `downed` marks a downed player, `posed` one in the seated pose (#1296: public body
## state; the own client is not told, as it gets no own avatar), `limp` one lying limp (#1393:
## public body state; the own client gets its own avatar then), and `invulnerable` one whom strikes
## skip at that tick (after a respawn or a revive, vision revision 1: public, so nobody swings at it
## in vain unawares). `drunk` is how drunk the player is (#1390: public body state, 0..PlayerRules
## drunk_max; the own client reads its own in SelfStatus). The hand and belt items are
## public too (`held_item`, `belt_item`, `belt_item2`: vision revision 1, Two hands; GDD §6). An
## item in flight shows `where` FLYING at its launch's origin (§7.1.16; items are not on the wire,
## E3: clients draw the arc from the throw's event). Private numbers (health, stamina) are never
## avatar fields: they travel in SelfStatus.


## What `viewer` is entitled to see at host tick `at_tick` (the tick whose state it shows): the
## avatars, the items and the bodies. Match records it for view_of() (keep_history); the snapshot
## the host sends each tick is avatars_for() alone (#1198).
static func for_peer(state: MatchState, viewer: int, at_tick: int) -> Dictionary:
	var item_data := {}
	for id: int in state.items:
		var item := state.items[id]
		item_data[id] = {"where": item.where, "holder": item.holder, "position": item.position}
	var body_data := {}
	for peer: int in state.bodies:
		body_data[peer] = state.bodies[peer]
	return {"avatars": avatars_for(state, viewer, at_tick), "items": item_data, "bodies": body_data}


## The avatars `viewer` is entitled to see at host tick `at_tick`, by peer.
static func avatars_for(state: MatchState, viewer: int, at_tick: int) -> Dictionary:
	var avatars := {}
	for peer: int in state.present_peers():
		var player := state.players[peer]
		if peer == viewer and not player.holds_still():
			continue
		if player.life == PlayerState.Life.DEAD:
			continue
		avatars[peer] = {
			"position": player.position,
			"velocity": player.velocity,
			"facing": player.facing,
			"downed": player.life == PlayerState.Life.DOWNED,
			"invulnerable": player.is_invulnerable(at_tick),
			"crouched": player.crouched,
			"sneaking": player.sneaking,
			"posed": player.posed,
			"limp": player.is_limp(),
			"drunk": player.drunk,
			"held_item": player.held_item,
			"belt_item": player.belt_item,
			"belt_item2": player.belt_item2,
		}
	return avatars
