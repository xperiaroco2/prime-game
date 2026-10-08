class_name PregamePhase
extends Phase
## The base mode's Pregame (ARCHITECTURE §3.2, §3.5, §3.6, §9.4, #213): the silent intro between
## Loading and Round, while each client shows a black screen with its own role. Nothing of its own
## but a timer: it reports `pregame_done` on its end tick, `seconds` after the entry (announced in
## PhaseChanged). The data makes it frozen and silent (no accepts, SilentVoice, the clock stopped,
## no win check); the deal already ran on the row into it, so the roles are known. Joins are
## refused (DisconnectPeer). A leave is Round's: the players were dealt, so a newcomer that never
## joined is forgotten silently and a player's leave goes to the life rule (life `left`,
## PlayerLeft, player_left, its held item drops); the win check counts it on Round's entry.

const PREGAME_DONE := &"pregame_done"


func outcomes() -> Array[StringName]:
	return [PREGAME_DONE]


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(settings, {&"seconds": Vector2(0, 60)})


## The data's `seconds` (the base mode's 3 s is 60 ticks); the class default is neutral.
func end_tick() -> int:
	return entered_tick + Ticks.from_seconds(setting(&"seconds", 0))


func on_tick(ctx: MatchContext) -> void:
	if ctx.tick >= end_tick():
		ctx.report_outcome(PREGAME_DONE)


func on_peer_connected(ctx: MatchContext, peer: int) -> void:
	JoinRules.refuse(ctx, peer)


func on_peer_left(ctx: MatchContext, peer: int) -> void:
	if JoinRules.forget_newcomer(ctx, peer):
		return
	LifeRules.leave(ctx, peer)
