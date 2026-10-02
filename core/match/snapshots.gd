class_name Snapshots
extends RefCounted
## One peer's snapshot of one tick, built from visibility rules per entity (ARCHITECTURE §5): the
## avatar of every living or downed player reaches every player, the dead included (a spectator's
## camera is built from these); a dead player has no avatar, so no snapshot holds one; bodies and
## items reach everyone; nobody gets their own avatar. The avatar's flag `downed` marks a downed
## player, and `invulnerable` one whom strikes skip at that tick (after a respawn or a revive,
## vision revision 1: public, so nobody swings at it in vain unawares). The hand and belt items are
## public too (`held_item`, `belt_item`: vision revision 1, Two hands). Private numbers (health,
## stamina) are never avatar fields: they travel in SelfStatus.


## What `viewer` is entitled to see at host tick `at_tick` (the tick whose state it shows).
static func for_peer(state: MatchState, viewer: int, at_tick: int) -> Dictionary:
	var avatars := {}
	for peer: int in state.present_peers():
		if peer == viewer:
			continue
		var player := state.players[peer]
		if player.life == PlayerState.Life.DEAD:
			continue
		avatars[peer] = {
			"position": player.position,
			"velocity": player.velocity,
			"facing": player.facing,
			"downed": player.life == PlayerState.Life.DOWNED,
			"invulnerable": player.is_invulnerable(at_tick),
			"held_item": player.held_item,
			"belt_item": player.belt_item,
		}
	var item_data := {}
	for id: int in state.items:
		var item := state.items[id]
		item_data[id] = {"where": item.where, "holder": item.holder, "position": item.position}
	var body_data := {}
	for peer: int in state.bodies:
		body_data[peer] = state.bodies[peer]
	return {"avatars": avatars, "items": item_data, "bodies": body_data}
