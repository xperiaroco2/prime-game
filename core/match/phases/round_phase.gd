class_name RoundPhase
extends Phase
## The base mode's Round (ARCHITECTURE §3.2, §9.4): nothing of its own. Its intents go to rules
## (PickUp, PutDown, Use) and to the movement rule (MoveClaim); a leave goes to the life rule
## (§3.5, 2g); the phase spec runs its tick systems, the match clock and the win checks. Joins are
## refused (§3.5): a connection that completed anyway gets DisconnectPeer (2b).


func on_peer_connected(ctx: MatchContext, peer: int) -> void:
	JoinRules.refuse(ctx, peer)
