class_name Snapshots
extends RefCounted
## One peer's snapshot of one tick, built from visibility rules per entity (ARCHITECTURE §5): the
## avatar of every living or downed player reaches every player, the dead outside a hall included
## (a spectator's camera is built from these); a dead player has no avatar outside the hall, and a
## dead viewer in the hall gets only the others there (avatars_for, #1489); bodies and
## items reach everyone; nobody gets their own avatar, except a knocked-down or limp player (the
## knockdown rework's KE5 (a); #1393): its own place, where the host's physics may carry it, and
## nothing hidden. The
## avatar's flag `downed` marks a downed player, `posed` one in the seated pose (#1296: public body
## state; the own client is not told, as it gets no own avatar), `limp` one lying limp (#1393:
## public body state; the own client gets its own avatar then), and `invulnerable` one whom strikes
## skip at that tick (after a respawn or a revive, vision revision 1: public, so nobody swings at it
## in vain unawares). `drunk` is how drunk the player is (#1390: public body state, 0..PlayerRules
## drunk_max; the own client reads its own in SelfStatus). `wheel_pose` is the pose wheel's pose
## (#1485: public body state, WheelPoseCode's byte, 0 for none; the own client reads its own in
## SelfStatus). The hand and belt items are
## public too (`held_item`, `belt_item`, `belt_item2`: vision revision 1, Two hands; GDD §6). An
## item in flight shows `where` FLYING at its launch's origin (§7.1.16; items are not on the wire,
## E3: clients draw the arc from the throw's event). Private numbers (health, stamina) are never
## avatar fields: they travel in SelfStatus.


## What `viewer` is entitled to see at host tick `at_tick` (the tick whose state it shows): the
## avatars, the items, the bodies, and the pinball's ball while one is on the table (`ball`, absent
## otherwise: Pinball.shown_ball, #1399). Match records it for view_of() (keep_history); the
## snapshot the host sends each tick is sent() alone (#1198).
static func for_peer(state: MatchState, viewer: int, at_tick: int) -> Dictionary:
	var item_data := {}
	for id: int in state.items:
		var item := state.items[id]
		item_data[id] = {"where": item.where, "holder": item.holder, "position": item.position}
	var body_data := {}
	for peer: int in state.bodies:
		body_data[peer] = state.bodies[peer]
	var seen := sent(state, viewer, at_tick)
	seen["items"] = item_data
	seen["bodies"] = body_data
	return seen


## What the host sends `viewer` for host tick `at_tick` (Match.snapshot_for): the avatars it is
## entitled to, and the pinball's ball (`ball`, the same for everyone) while one is on the table.
static func sent(state: MatchState, viewer: int, at_tick: int) -> Dictionary:
	var shown := {"avatars": avatars_for(state, viewer, at_tick)}
	shown.merge(Pinball.shown_ball(state))
	return shown


## The avatars `viewer` is entitled to see at host tick `at_tick`, by peer (#1489): nobody sees a
## dead player but a dead viewer in the hall, who sees the others there and nobody else. A printing
## player is shown invulnerable: strikes skip it.
static func avatars_for(state: MatchState, viewer: int, at_tick: int) -> Dictionary:
	var avatars := {}
	var viewer_in_hall := state.player(viewer) != null and state.player(viewer).in_hall
	for peer: int in state.present_peers():
		var player := state.players[peer]
		if peer == viewer and not player.holds_still():
			continue
		if viewer_in_hall != player.in_hall:
			continue
		if player.life == PlayerState.Life.DEAD and not viewer_in_hall:
			continue
		avatars[peer] = {
			"position": player.position,
			"velocity": player.velocity,
			"facing": player.facing,
			"downed": player.life == PlayerState.Life.DOWNED,
			"invulnerable": player.is_invulnerable(at_tick) or player.is_printing(),
			"crouched": player.crouched,
			"sneaking": player.sneaking,
			"posed": player.posed,
			"limp": player.is_limp(),
			"drunk": player.drunk,
			"wheel_pose": player.wheel_pose_code(),
			"held_item": player.held_item,
			"belt_item": player.belt_item,
			"belt_item2": player.belt_item2,
		}
	return avatars
