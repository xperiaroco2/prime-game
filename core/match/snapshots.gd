class_name Snapshots
extends RefCounted
## One peer's snapshot of one tick, built from visibility rules per entity (ARCHITECTURE §5): a
## living player's avatar reaches every player; a downed player's reaches the downed only (as a
## ghost's did, until M4-2 makes the downed public); bodies and items reach everyone; nobody gets
## their own avatar. The avatar's flag keeps its wire name `ghost` and is set from DOWNED (M4-2
## renames it `downed` with a protocol bump). Private numbers (health, stamina) are never avatar
## fields: they travel in SelfStatus.


## What `viewer` is entitled to see now.
static func for_peer(state: MatchState, viewer: int) -> Dictionary:
	var avatars := {}
	var viewer_state := state.player(viewer)
	var viewer_downed := viewer_state != null and viewer_state.life == PlayerState.Life.DOWNED
	for peer: int in state.present_peers():
		if peer == viewer:
			continue
		var player := state.players[peer]
		if player.life == PlayerState.Life.DOWNED and not viewer_downed:
			continue
		avatars[peer] = {
			"position": player.position,
			"velocity": player.velocity,
			"facing": player.facing,
			"ghost": player.life == PlayerState.Life.DOWNED,
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
