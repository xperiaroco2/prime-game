class_name Snapshots
extends RefCounted
## One peer's snapshot of one tick, built from visibility rules per entity (ARCHITECTURE §5): the
## avatar of every living or downed player reaches every player, the dead included (a spectator's
## camera is built from these); a dead player has no avatar, so no snapshot holds one; bodies and
## items reach everyone; nobody gets their own avatar. The avatar's flag `downed` marks a downed
## player. Private numbers (health, stamina) are never avatar fields: they travel in SelfStatus.


## What `viewer` is entitled to see now.
static func for_peer(state: MatchState, viewer: int) -> Dictionary:
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
			"held_item": player.held_item,
		}
	var item_data := {}
	for id: int in state.items:
		var item := state.items[id]
		item_data[id] = {"where": item.where, "holder": item.holder, "position": item.position}
	var body_data := {}
	for peer: int in state.bodies:
		body_data[peer] = state.bodies[peer]
	return {"avatars": avatars, "items": item_data, "bodies": body_data}
