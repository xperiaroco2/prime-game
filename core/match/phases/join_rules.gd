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
## A joiner gets a number in the session (MatchState.give_number): the next one, or, for a player
## who left and joins again with the same return key (its Hello's `key`, ReturnKey), its old one
## (the returning-players ADR, Decision 2; the engineer's answers P1 (c), P3 (a), P4 (a), P13 (b)
## on #302). It is named by its Hello's `name` (#550, #73) as PlayerNames cleans it, or
## Player<number> when nothing usable or only a reserved name (Player and digits) is left; a name a
## present player has gets a suffix (PlayerNames.unique). A joiner takes the first body colour no
## present player has (PlayerColours, #551); SetProfile changes name and colour in the lobby
## (set_profile). The joiner's spot is a placeholder, "not a decision".

## The protocol version this build speaks; a Hello with another gets DisconnectPeer (§4.1).
const PROTOCOL_VERSION := 43
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
## this build can read (§4.3). Accepted: the joiner gets its number from its `key`
## (MatchState.give_number: a returner its old one, anyone else the next), is named (joiner_name),
## given the first free colour (PlayerColours.first_free), placed at a lobby marker (_free_spot)
## with a new epoch; Welcome (the joiner), PlayerJoined (everyone), a StationPlaced (everyone)
## for each standing station in id order (_replay_stations: the lobby's tap, #1390, a stopgap
## until Welcome carries the stations, #1404) and SettingsChanged (everyone). A name or a key
## is never a reason to refuse: a bad name falls back, an unusable key is none (P7 (a)). `spec`
## is the phase's own (its id goes into Welcome, its level decides the spot).
static func hello(ctx: MatchContext, command: MatchCommand, spec: PhaseSpec) -> bool:
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
	var spot := _free_spot(ctx, spec)
	var number := ctx.state.give_number(command.field("key"))
	var player_name := joiner_name(ctx, command.field("name"), number)
	var colour := PlayerColours.first_free(_colours_of_others(ctx, peer))
	var joined := ctx.state.add_player(peer, player_name)
	joined.number = number
	joined.colour = colour
	joined.position = spot
	joined.velocity = Vector3.ZERO
	joined.epoch += 1
	ctx.emit(_welcome(ctx, joined, spec.id))
	ctx.emit(PlayerJoinedEvent.new(peer, player_name, spot, colour))
	_replay_stations(ctx)
	ctx.emit(FitCheck.settings_changed(ctx))
	return true


## Names the joiner with `number` (§3.5, #550): `wanted` as PlayerNames.clean leaves it, or the
## fallback Player<number> (PlayerNames.fallback) when that is empty (no name, the wrong type,
## blanks or controls only) or reserved for the fallback names (PlayerNames.is_reserved, P13 (b) of
## the returning-players ADR: the joiner keeps its fallback, never Rejected); then
## PlayerNames.unique against the present players, so a chosen name never repeats one ("Dima",
## then "Dima 2").
static func joiner_name(ctx: MatchContext, wanted: Variant, number: int) -> String:
	var fallback := PlayerNames.fallback(number)
	var cleaned := PlayerNames.clean(wanted)
	var taken := PackedStringArray()
	for peer: int in ctx.state.present_peers():
		taken.append(ctx.state.players[peer].name)
	var own := not cleaned.is_empty() and not PlayerNames.is_reserved(cleaned)
	return PlayerNames.unique(cleaned if own else fallback, taken)


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


## A PeerLeft outside Round (Lobby, Countdown, Loading; §3.5): true when a player left the roster.
## In Round's order (LifeRules.leave): every channel it runs or is the target of stops, it is
## marked left, PlayerLeft goes to everyone else, then what it carries drops to the floor below it
## (Items.drop_carried: ItemPlaced, cause `leave`, to everyone else; the lobby's hand and belt,
## #1388), and only then it leaves the roster. A newcomer is forgotten silently; a peer that is
## gone already (disconnected by a directive, whose PeerLeft comes later) changes nothing.
static func leave(ctx: MatchContext, peer: int) -> bool:
	if forget_newcomer(ctx, peer):
		return false
	if not ctx.state.is_present(peer):
		return false
	Channels.interrupt_involving(ctx, peer)
	var leaver := ctx.state.player(peer)
	# A limp body leaves with its player: StopBody frees the host's body (#1393).
	LifeRules.clear_limp(ctx, leaver, true)
	leaver.life = PlayerState.Life.LEFT
	ctx.emit(PlayerLeftEvent.new(peer))
	Items.drop_carried(ctx, peer, Items.LEAVE)
	ctx.state.remove_player(peer)
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


## SetProfile(name, colour) from a player (§3.5, §4.1, #551): true when the profile changed. In
## order: a `name` that is not text or a `colour` that is not an int is Rejected (`bad_args`); a
## colour outside PlayerColours is `out_of_bounds`. The name as PlayerNames cleans it, made unique
## against the other present players (so re-sending one's own "Dima 2" keeps it); a name with
## nothing usable left, or one reserved for the fallback names (PlayerNames.is_reserved, P13 (b)),
## keeps the current one, never Rejected for the name (so a player without an own name re-sends
## its Player<n> with a new colour), and never counts a join (MatchState.joins numbers joins
## only). The colour as asked when no other present player has it, else the first free one
## (the engineer's answer on #73). Both as they are: Rejected (`unchanged`). Otherwise both are set
## and ProfileChanged goes to everyone. The ready flag is untouched.
static func set_profile(ctx: MatchContext, command: MatchCommand) -> bool:
	var wanted_name: Variant = command.field("name")
	var wanted_colour: Variant = command.field("colour")
	if not (wanted_name is String or wanted_name is StringName) or not wanted_colour is int:
		ctx.reject(command, RejectReasons.BAD_ARGS)
		return false
	if not PlayerColours.is_valid(wanted_colour):
		ctx.reject(command, RejectReasons.OUT_OF_BOUNDS)
		return false
	var player := ctx.state.player(command.peer)
	var player_name := player.name
	var cleaned := PlayerNames.clean(wanted_name)
	if not cleaned.is_empty() and not PlayerNames.is_reserved(cleaned):
		var taken := PackedStringArray()
		for peer: int in ctx.state.present_peers():
			if peer != command.peer:
				taken.append(ctx.state.players[peer].name)
		player_name = PlayerNames.unique(cleaned, taken)
	var colour := PlayerColours.resolve(wanted_colour as int, _colours_of_others(ctx, command.peer))
	if player_name == player.name and colour == player.colour:
		ctx.reject(command, RejectReasons.UNCHANGED)
		return false
	player.name = player_name
	player.colour = colour
	ctx.emit(ProfileChangedEvent.new(command.peer, player_name, colour))
	return true


## The colours of the present players other than `peer`.
static func _colours_of_others(ctx: MatchContext, peer: int) -> Array[int]:
	var taken: Array[int] = []
	for other: int in ctx.state.present_peers():
		if other != peer:
			taken.append(ctx.state.players[other].colour)
	return taken


static func _drop(ctx: MatchContext, peer: int) -> void:
	ctx.state.newcomers.erase(peer)
	ctx.emit(DisconnectPeerEvent.new(peer))


## Where a joiner stands (§3.5). In a phase at no level (PhaseSpec.Level.NONE: the tutorial's
## `gather`, E72) the origin, with no error: nobody sees it and the deal places everyone. Otherwise
## the first lobby_player marker of the phase's level with no player within SPOT_CLEARANCE_M, or
## the first marker when all are taken; none (no marker, or the layout failed to load: null) is a
## match error and the origin. Keyed on the spec's level, never on ctx.layout being null, which
## both cases have.
static func _free_spot(ctx: MatchContext, spec: PhaseSpec) -> Vector3:
	if spec.level == PhaseSpec.Level.NONE:
		return Vector3.ZERO
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
		welcome.roster.append(
			{"peer": peer, "name": player.name, "ready": player.ready, "colour": player.colour}
		)
		if peer != joined.peer:
			welcome.positions[peer] = player.position
	welcome.settings = ctx.state.settings.duplicate()
	welcome.map = ctx.state.map
	welcome.phase = phase_id
	welcome.lobby_name = ctx.state.lobby_name
	return welcome


## The stations standing before a join (#1390: the lobby's tap, StationTicks), again in id order
## (StationPlaced, everyone): Welcome carries none yet (#1404), and a client overwrites a station
## it knows by id, so the others' copies change nothing. Lobby and Countdown both join here.
static func _replay_stations(ctx: MatchContext) -> void:
	var ids: Array[int] = []
	ids.assign(ctx.state.stations.keys())
	ids.sort()
	for id: int in ids:
		var station := ctx.state.stations[id]
		ctx.emit(StationPlacedEvent.new(id, station.kind.id, station.colour, station.position))
