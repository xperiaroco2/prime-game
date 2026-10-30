class_name GoLimp
extends RuleEffect
## The player goes limp (#1393; GDD §3 Base mode, "The bar"; ARCHITECTURE §7.1.21, §9.4.3): the
## base mode's reaction on the fact drunk_too_much (Drink raises it; Fact.player names the
## drinker). LifeRules.go_limp lays the player down as a rag-doll for `limp_s` while its life stays
## ALIVE; LimpTicks pushes the body and gets the player up, EndLimps ends the limp where a phase
## without LimpTicks follows. On an intent (no fact) the actor goes limp.
##
## A player who is not alive is a rule error, logged (LifeRules.go_limp); one limp already stays
## as it is. The mode check (LimpTicks.problems) wants a LimpTicks, with a LifeTicks, in a phase,
## and an EndLimps on every row from such a phase into one without.
##
## Emits: RaiseStopped (everyone), for a channel involving the player; Correction (the player:
## its new epoch); LaunchBody (server). No demands.

## How long the limp lasts, in seconds: provisional, "not a decision" (the engineer tunes it).
@export var limp_s := 0.0


func run(ctx: MatchContext) -> void:
	var peer := ctx.fact.player if ctx.fact != null else ctx.actor
	LifeRules.go_limp(ctx, peer, limp_s)


func emits() -> Array[Script]:
	return [RaiseStoppedEvent, CorrectionEvent, LaunchBodyEvent]


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(found, [out_of_bounds("limp_s", limp_s, 0.5, 60)])
	found.append_array(LimpTicks.problems(mode))
	return found
