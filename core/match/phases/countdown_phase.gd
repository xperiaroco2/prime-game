class_name CountdownPhase
extends Phase
## The base mode's Countdown (ARCHITECTURE §3.2, §3.5, §9.4): `countdown_done` on its end tick,
## `seconds` after the entry (announced in PhaseChanged). Joins and leaves as in Lobby, and
## SetReady(false), each cancel it: CountdownCancelled(reason) (everyone), then `cancelled`. The
## `cancelled` row has no actions: ready flags and positions stay, so after a leave the Lobby's
## `all_ready` fires again on entry and the countdown restarts. The settings are locked here
## (ChangeSettings is Lobby's only).

const CANCELLED := &"cancelled"
const COUNTDOWN_DONE := &"countdown_done"


func handled_intents() -> Array[StringName]:
	return [Intents.HELLO, Intents.SET_READY]


func outcomes() -> Array[StringName]:
	return [CANCELLED, COUNTDOWN_DONE]


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(settings, {&"seconds": Vector2(0, 60)})


## The data's `seconds` (the base mode's 5 s is 100 ticks); the class default is neutral.
func end_tick() -> int:
	return entered_tick + Ticks.from_seconds(setting(&"seconds", 0))


func on_tick(ctx: MatchContext) -> void:
	if ctx.tick >= end_tick():
		ctx.report_outcome(COUNTDOWN_DONE)


func handle_intent(ctx: MatchContext, command: MatchCommand) -> void:
	match command.kind:
		Intents.HELLO:
			if JoinRules.hello(ctx, command, spec):
				_cancel(ctx, CountdownCancelledEvent.JOIN)
		Intents.SET_READY:
			# Countdown accepts SetReady(false) only (§4.1).
			if not JoinRules.has_ready_flag(ctx, command):
				return
			if command.get_bool("ready"):
				ctx.reject(command, RejectReasons.NOT_ACCEPTED)
			elif JoinRules.set_ready(ctx, command, false):
				_cancel(ctx, CountdownCancelledEvent.UN_READY)
		_:
			ctx.reject(command, RejectReasons.NOTHING_TO_DO)


func on_peer_connected(ctx: MatchContext, peer: int) -> void:
	JoinRules.connect_peer(ctx, peer)


func on_peer_left(ctx: MatchContext, peer: int) -> void:
	if JoinRules.leave(ctx, peer):
		ctx.emit(FitCheck.settings_changed(ctx))
		_cancel(ctx, CountdownCancelledEvent.LEAVE)


static func _cancel(ctx: MatchContext, reason: StringName) -> void:
	ctx.emit(CountdownCancelledEvent.new(reason))
	ctx.report_outcome(CANCELLED)
