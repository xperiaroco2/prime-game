class_name JoinRules
extends RefCounted
## Joining, leaving and the ready flag, shared by the base mode's phase classes (ARCHITECTURE
## §3.2, §3.5, §4.1). A connected peer (PeerConnected) is a newcomer until its Hello is accepted;
## only a newcomer may join, once, in a phase that allows joins (Lobby, Countdown). Loading, Round
## and End refuse joins: a connection that completed anyway gets DisconnectPeer.
## A Hello must also carry the host's content hash (`wrong_content`, E1). A Hello in a phase that
## refuses joins gets `joins_closed` (Match._refuse, E14), and drop_newcomers disconnects the
## waiting newcomers when a phase freezes the roster (Loading's entry).
##
## The host names every joiner Player<n>, n counting the session's joins (MatchState.joins); the
## name a Hello carries is ignored in the MVP (#73). The joiner's spot is a placeholder, "not a
## decision".

## The protocol version this build speaks; a Hello with another gets DisconnectPeer (§4.1).
const PROTOCOL_VERSION := 12
## A joiner takes the first lobby marker, in level order, with no other player within this many
## metres; when every marker is taken, the first one: placeholder, "not a decision".
const SPOT_CLEARANCE_M := 1.0


## PeerConnected where joins are allowed: the peer may now send its Hello.
static func connect_peer(ctx: MatchContext, peer: int) -> void:
	if ctx.state.players.has(peer):
		ctx.error("PeerConnected for peer %d, which is a player" % peer)
		return
	ctx.state.newcomers[peer] = true


## PeerConnected where joins are refused (§3.5): the connection completed anyway.
static func refuse(ctx: MatchContext, peer: int) -> void:
	ctx.emit(DisconnectPeerEvent.new(peer))


## A Hello (§4.1): true when the peer joined. In order: the sender must be a newcomer; the
## version must be the host's, else Rejected (`wrong_version`) and DisconnectPeer; the content
## hash must be the host's (Match.content_hash), else Rejected (`wrong_content`) and
## DisconnectPeer (§4.3, E1); the roster must have room for one more, else Rejected (`full`) and
## DisconnectPeer. The version comes first: a Hello of another version carries nothing else that
## this build can read (§4.3). Accepted: the joiner is named Player<n> by the session's join
## count, placed at a lobby marker with a new epoch; Welcome (the joiner), PlayerJoined and
## SettingsChanged (everyone).
static func hello(ctx: MatchContext, command: MatchCommand, phase_id: StringName) -> bool:
	var peer := command.peer
	if not ctx.state.newcomers.has(peer):
		ctx.reject(command, RejectReasons.NOT_ACCEPTED)
		return false
	var version: Variant = command.field("version")
	if not (version is int and version == PROTOCOL_VERSION):
		ctx.reject(command, RejectReasons.WRONG_VERSION)
		_drop(ctx, peer)
		return false
	var content: Variant = command.field("content")
	if not (content is int and content == ctx.content_hash()):
		ctx.reject(command, RejectReasons.WRONG_CONTENT)
		_drop(ctx, peer)
		return false
	if ctx.state.peers().size() >= ctx.mode.max_players:
		ctx.reject(command, RejectReasons.FULL)
		_drop(ctx, peer)
		return false
	ctx.state.newcomers.erase(peer)
	var spot := _free_spot(ctx)
	var player_name := ctx.state.name_next_joiner()
	var joined := ctx.state.add_player(peer, player_name)
	joined.position = spot
	joined.velocity = Vector3.ZERO
	joined.epoch += 1
	ctx.emit(_welcome(ctx, joined, phase_id))
	ctx.emit(PlayerJoinedEvent.new(peer, player_name, spot))
	ctx.emit(FitCheck.settings_changed(ctx))
	return true


## Disconnects every newcomer still waiting (DisconnectPeer each, in peer-id order, no Rejected:
## none sent a Hello that could be answered) and forgets them: a phase that freezes the roster
## (Loading's entry, E14) can accept none of their Hellos this match, so none lingers until the
## hello deadline.
static func drop_newcomers(ctx: MatchContext) -> void:
	var waiting: Array[int] = []
	waiting.assign(ctx.state.newcomers.keys())
	waiting.sort()
	for peer: int in waiting:
		_drop(ctx, peer)


## A PeerLeft outside Round (§3.5): true when a player left the roster (PlayerLeft to everyone
## else). A newcomer is forgotten silently; a peer that is gone already (disconnected by a
## directive, whose PeerLeft comes later) changes nothing.
static func leave(ctx: MatchContext, peer: int) -> bool:
	if forget_newcomer(ctx, peer):
		return false
	if not ctx.state.is_present(peer):
		return false
	ctx.state.remove_player(peer)
	ctx.emit(PlayerLeftEvent.new(peer))
	return true


## A newcomer's PeerLeft, in any phase: the peer is forgotten silently. True when it was one.
static func forget_newcomer(ctx: MatchContext, peer: int) -> bool:
	return ctx.state.newcomers.erase(peer)


## True when a SetReady carries a bool `ready`; else Rejected (`bad_args`), so a malformed intent
## is never read as SetReady(false) (which would cancel a countdown).
static func has_ready_flag(ctx: MatchContext, command: MatchCommand) -> bool:
	if command.field("ready") is bool:
		return true
	ctx.reject(command, RejectReasons.BAD_ARGS)
	return false


## Sets the sender's ready flag to `ready` (§4.1): only a change is accepted, else Rejected
## (`unchanged`). ReadyChanged (everyone). True when it changed.
static func set_ready(ctx: MatchContext, command: MatchCommand, ready: bool) -> bool:
	var player := ctx.state.player(command.peer)
	if player.ready == ready:
		ctx.reject(command, RejectReasons.UNCHANGED)
		return false
	player.ready = ready
	ctx.emit(ReadyChangedEvent.new(command.peer, ready))
	return true


static func _drop(ctx: MatchContext, peer: int) -> void:
	ctx.state.newcomers.erase(peer)
	ctx.emit(DisconnectPeerEvent.new(peer))


static func _free_spot(ctx: MatchContext) -> Vector3:
	var spots := PackedVector3Array()
	if ctx.layout != null:
		spots = ctx.layout.positions(LayoutCheck.LOBBY_PLAYER)
	if spots.is_empty():
		ctx.error("no %s marker for a joiner" % LayoutCheck.LOBBY_PLAYER)
		return Vector3.ZERO
	for spot: Vector3 in spots:
		var taken := false
		for peer: int in ctx.state.present_peers():
			if ctx.state.players[peer].position.distance_to(spot) < SPOT_CLEARANCE_M:
				taken = true
				break
		if not taken:
			return spot
	return spots[0]


## Public facts only (§5): in Lobby and Countdown nobody has a role and everyone is alive.
static func _welcome(ctx: MatchContext, joined: PlayerState, phase_id: StringName) -> WelcomeEvent:
	var welcome := WelcomeEvent.new(joined.peer, joined.position, joined.epoch)
	for peer: int in ctx.state.present_peers():
		var player := ctx.state.players[peer]
		welcome.roster.append({"peer": peer, "name": player.name, "ready": player.ready})
		if peer != joined.peer:
			welcome.positions[peer] = player.position
	welcome.settings = ctx.state.settings.duplicate()
	welcome.map = ctx.state.map
	welcome.phase = phase_id
	return welcome
