class_name EndPhase
extends Phase
## The base mode's End (ARCHITECTURE §3.2, §3.5, §9.4): frozen. It reports `back` on its end tick,
## `seconds` after the entry (announced in PhaseChanged), or earlier on the host's ReturnToLobby (a
## shortcut no screen offers since #212: the tests and the bots use it). The `back` row resets the
## match (ResetMatch) and then places everyone in the lobby. With no `seconds` it has no end tick
## and waits for ReturnToLobby. Joins are refused (DisconnectPeer). A leave sets the player's life
## state to `left`, as in Round, and emits PlayerLeft (everyone); ResetMatch then drops the player
## from the roster.

const BACK := &"back"


func handled_intents() -> Array[StringName]:
	return [Intents.RETURN_TO_LOBBY]


func outcomes() -> Array[StringName]:
	return [BACK]


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(settings, {&"seconds": Vector2(0, 60)})


## The data's `seconds` after the entry (the base mode's 3 s is 60 ticks); -1 with no `seconds`.
func end_tick() -> int:
	if spec == null or not spec.settings.has(&"seconds"):
		return -1
	return entered_tick + Ticks.from_seconds(setting(&"seconds", 0))


func on_tick(ctx: MatchContext) -> void:
	var end := end_tick()
	if end >= 0 and ctx.tick >= end:
		ctx.report_outcome(BACK)


func handle_intent(ctx: MatchContext, command: MatchCommand) -> void:
	if command.kind == Intents.RETURN_TO_LOBBY:
		ctx.report_outcome(BACK)
	else:
		ctx.reject(command, RejectReasons.NOTHING_TO_DO)


func on_peer_connected(ctx: MatchContext, peer: int) -> void:
	JoinRules.refuse(ctx, peer)


func on_peer_left(ctx: MatchContext, peer: int) -> void:
	if JoinRules.forget_newcomer(ctx, peer):
		return
	if not ctx.state.is_present(peer):
		return
	ctx.state.players[peer].life = PlayerState.Life.LEFT
	ctx.emit(PlayerLeftEvent.new(peer))
