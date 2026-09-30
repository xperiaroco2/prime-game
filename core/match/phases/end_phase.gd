class_name EndPhase
extends Phase
## The base mode's End (ARCHITECTURE §3.2, §3.5, §9.4): frozen. The host's ReturnToLobby reports
## `back`, whose row resets the match (ResetMatch) and then places everyone in the lobby. Joins
## are refused (DisconnectPeer). A leave sets the player's life state to `left`, as in Round, and
## emits PlayerLeft (everyone); ResetMatch then drops the player from the roster.

const BACK := &"back"


func handled_intents() -> Array[StringName]:
	return [Intents.RETURN_TO_LOBBY]


func outcomes() -> Array[StringName]:
	return [BACK]


func handle_intent(ctx: MatchContext, command: MatchCommand) -> void:
	if command.kind == Intents.RETURN_TO_LOBBY:
		ctx.report_outcome(BACK)
	else:
		ctx.reject(command, RejectReasons.NOTHING_TO_DO)


func on_peer_connected(ctx: MatchContext, peer: int) -> void:
	JoinRules.refuse(ctx, peer)


func on_peer_left(ctx: MatchContext, peer: int) -> void:
	if ctx.state.newcomers.has(peer):
		ctx.state.newcomers.erase(peer)
		return
	if not ctx.state.is_present(peer):
		return
	ctx.state.players[peer].life = PlayerState.Life.LEFT
	ctx.emit(PlayerLeftEvent.new(peer))
