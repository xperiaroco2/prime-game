class_name DealRoles
extends RuleEffect
## Deals every present player a role (ARCHITECTURE §3.3, §9.4): the first transition action of
## the deal. Each quota in order draws its players from those not drawn yet: the roster in peer-id
## order, shuffled with RngStreams.shuffled_indices over the RNG purpose `rng_purpose` (never the
## global RNG). A quota draws max(0, min(setting, N - leave_at_least)) players (RoleQuota), N the
## present players, and never more than are left. Everyone else gets `default_role`.
##
## Emits: RoleAssigned to each player, in peer-id order (that player only); then, for each role
## of the mode that knows its teammates and has players, in the mode's order, Teammates (every
## player of that role, and nobody else, §5).
##
## Forced roles (§8, §9.7: a debug command or a scenario, debug builds only) come as data:
## MatchState.forced_roles (peer -> role id), which server/'s debug path or the scenario runner
## sets through Match.force_roles() before the start, since core/ cannot tell a debug build (2j).
## Before its draws, each present peer with a forced role the mode declares gets it and is drawn by
## no quota; a forced role counts toward its quota (the engineer's answer A on #30: "dissidents 1"
## with bot 2 forced to dissident makes bot 2 the only dissident), so a quota draws its count minus
## the players forced to its role, never below 0. A forced role the mode does not declare is a
## match error and is ignored.

## The quotas, in order: each draws its players from those the earlier ones left.
@export var quotas: Array[RoleQuota] = []
## The role of every player no quota drew (Crew).
@export var default_role: GameRole
## The RNG purpose of the draw (§3.3): `roles` in the base mode.
@export var rng_purpose: StringName


func run(ctx: MatchContext) -> void:
	if default_role == null:
		ctx.error("DealRoles: no default_role")
		return
	var peers := ctx.state.present_peers()
	var left: Array[int] = peers.duplicate()
	var forced := _apply_forced(ctx, peers, left)
	var rng := ctx.rng(rng_purpose)
	for quota: RoleQuota in quotas:
		var wanted := quota.count_for(ctx.state.settings, peers.size())
		wanted -= forced.get(quota.role.id, 0)
		var count := clampi(wanted, 0, left.size())
		var order := RngStreams.shuffled_indices(left.size(), rng)
		var drawn: Array[int] = []
		for i in count:
			drawn.append(left[order[i]])
		for peer: int in drawn:
			ctx.state.players[peer].role = quota.role.id
			left.erase(peer)
	for peer: int in left:
		ctx.state.players[peer].role = default_role.id
	for peer: int in peers:
		ctx.emit(RoleAssignedEvent.new(peer, ctx.state.players[peer].role))
	for role: GameRole in ctx.mode.roles:
		if role == null or not role.knows_teammates:
			continue
		var of_role := PackedInt32Array()
		for peer: int in peers:
			if ctx.state.players[peer].role == role.id:
				of_role.append(peer)
		if not of_role.is_empty():
			ctx.emit(TeammatesEvent.new(role.id, of_role))


## Gives each present peer its forced role and takes it out of `left`; returns how many players
## were forced to each role.
static func _apply_forced(
	ctx: MatchContext, peers: Array[int], left: Array[int]
) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for peer: int in peers:
		if not ctx.state.forced_roles.has(peer):
			continue
		var role_id: StringName = ctx.state.forced_roles[peer]
		if ctx.mode.find_role(role_id) == null:
			ctx.error(
				"DealRoles: peer %d is forced to role %s, which the mode lacks" % [peer, role_id]
			)
			continue
		ctx.state.players[peer].role = role_id
		left.erase(peer)
		counts[role_id] = counts.get(role_id, 0) + 1
	return counts


func emits() -> Array[Script]:
	return [RoleAssignedEvent, TeammatesEvent]


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if default_role == null:
		found.append("DealRoles has no default_role")
	elif mode.find_role(default_role.id) == null:
		found.append("DealRoles: default_role %s is not a role of the mode" % default_role.id)
	if rng_purpose.is_empty():
		found.append("DealRoles has no rng_purpose")
	return found
