class_name RoundPhase
extends Phase
## The base mode's Round (ARCHITECTURE §3.2, §9.4): nothing of its own. Its intents go to rules
## (PickUp, PutDown, Use) and to the movement rule (MoveClaim); a leave goes to the life rule
## (§3.5, LifeRules.leave); the phase spec runs its tick systems, the match clock and the win
## checks. Joins are refused (§3.5): a connection that completed anyway gets DisconnectPeer (2b).
## Its one setting, `linger_seconds`, is how long the round lingers after a win decided at a
## finale (the ship engine's last stage, §3.4, #1502) before its `won`; none, no linger.

const LINGER_SECONDS := &"linger_seconds"


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(settings, {LINGER_SECONDS: Vector2(0, 30)})


func linger_ticks() -> int:
	if spec == null:
		return 0
	return Ticks.from_seconds(setting(LINGER_SECONDS, 0))


## `round_spec`'s linger in seconds (the client's finish lasts as long, #1502); 0 for none.
static func linger_seconds_of(round_spec: PhaseSpec) -> float:
	if round_spec == null:
		return 0.0
	return round_spec.settings.get(LINGER_SECONDS, 0.0)


func on_peer_connected(ctx: MatchContext, peer: int) -> void:
	JoinRules.refuse(ctx, peer)


## A newcomer that never joined is forgotten silently (2b); a player's leave is the life rule's:
## life `left`, PlayerLeft, player_left, then its held item drops (§3.5).
func on_peer_left(ctx: MatchContext, peer: int) -> void:
	if JoinRules.forget_newcomer(ctx, peer):
		return
	LifeRules.leave(ctx, peer)
