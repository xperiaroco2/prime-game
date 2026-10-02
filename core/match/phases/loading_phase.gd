class_name LoadingPhase
extends Phase
## The base mode's Loading (ARCHITECTURE §3.2, §3.5, §9.4). On entry the roster is frozen:
## RefuseJoins (server), a DisconnectPeer (server) for every newcomer still waiting for its Hello
## to be accepted (E14), and LoadMatch(match id, map, settings) (everyone). Each player confirms
## once with LoadAck(match id): an ack naming another match (an earlier one of the session) is
## dropped, a second one is rejected (`unchanged`); a valid one emits PlayerLoaded (everyone). At
## the deadline, `deadline_seconds` after the entry, each player without an ack gets
## Disconnecting(load_deadline) (only that player, #119), then DisconnectPeer (server), and is
## dropped from the roster (PlayerLeft); a leave drops too. The host (peer 1) is
## never dropped at the deadline: if its own load fails, server/ ends the session. Reports
## `all_loaded` when every remaining player confirmed.

const ALL_LOADED := &"all_loaded"
## The host's own player (§4): never dropped at the deadline.
const HOST := 1

## Peer -> true: the players who confirmed.
var _acks: Dictionary[int, bool] = {}
var _deadline_passed := false


func handled_intents() -> Array[StringName]:
	return [Intents.LOAD_ACK]


func outcomes() -> Array[StringName]:
	return [ALL_LOADED]


## `deadline_seconds` is required: without it the deadline would pass on the first tick and drop
## every client but the host, so a mode that leaves it out is refused.
func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	var found := check_known_settings(settings, {&"deadline_seconds": Vector2(5, 600)})
	if not settings.has(&"deadline_seconds"):
		found.append("missing setting deadline_seconds")
	return found


## The host tick of the loading deadline, from the data's `deadline_seconds` (the base mode's
## 60 s), which the mode check requires. Not announced: PhaseChanged carries only a countdown's or
## the match clock's end (§4.2).
func deadline_tick() -> int:
	return entered_tick + Ticks.from_seconds(setting(&"deadline_seconds", 0))


func enter(ctx: MatchContext) -> void:
	ctx.emit(RefuseJoinsEvent.new())
	JoinRules.drop_newcomers(ctx)
	ctx.emit(LoadMatchEvent.new(ctx.state.match_id(), ctx.state.map, ctx.state.settings))


func handle_intent(ctx: MatchContext, command: MatchCommand) -> void:
	if command.kind != Intents.LOAD_ACK:
		ctx.reject(command, RejectReasons.NOTHING_TO_DO)
		return
	var id: Variant = command.field("match_id")
	if not (id is int and id == ctx.state.match_id()):
		return
	if _acks.has(command.peer):
		ctx.reject(command, RejectReasons.UNCHANGED)
		return
	_acks[command.peer] = true
	ctx.emit(PlayerLoadedEvent.new(command.peer))
	_check_all_loaded(ctx)


func on_tick(ctx: MatchContext) -> void:
	if _deadline_passed or ctx.tick < deadline_tick():
		return
	_deadline_passed = true
	for peer: int in ctx.state.present_peers():
		if _acks.has(peer) or peer == HOST:
			continue
		ctx.emit(DisconnectingEvent.new(peer, DisconnectingEvent.LOAD_DEADLINE))
		ctx.emit(DisconnectPeerEvent.new(peer))
		JoinRules.leave(ctx, peer)
	_check_all_loaded(ctx)


func on_peer_connected(ctx: MatchContext, peer: int) -> void:
	JoinRules.refuse(ctx, peer)


func on_peer_left(ctx: MatchContext, peer: int) -> void:
	if JoinRules.leave(ctx, peer):
		_acks.erase(peer)
		_check_all_loaded(ctx)


func _check_all_loaded(ctx: MatchContext) -> void:
	# The host is never dropped, so the roster is never empty; an empty one never moves on.
	if ctx.state.present_peers().is_empty():
		return
	for peer: int in ctx.state.present_peers():
		if not _acks.has(peer):
			return
	ctx.report_outcome(ALL_LOADED)
