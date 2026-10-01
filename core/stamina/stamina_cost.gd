class_name StaminaCost
extends Cost
## A cost in stamina (ARCHITECTURE §9.4, §7.1): the knife's hit (2g). It first settles the
## actor's stamina up to now with its last claim's sprint flag and movement (the only change a
## condition may make, §9.2), then passes when the actor has at least `amount`; paying spends it
## and touches the actor's SelfStatus, sent at the end of the tick. At 0 stamina the action is
## unavailable until stamina regenerates that far (Q7). A downed player's stamina never limits it.
##
## Rejects with `tired`: it reveals only the actor's own stamina. Emits: SelfStatus (the actor).

## The rejection reason: the actor's own stamina is below the amount.
const TIRED := &"tired"

## Whole points, 0 to the mode's PlayerRules stamina.
@export var amount := 0


func pay(ctx: MatchContext) -> void:
	var player := ctx.actor_state()
	if player == null:
		return
	StaminaLedger.spend(player, Ticks.thousandths(amount))
	SelfStatusFeed.touch(ctx.state, player.peer)


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	var most := mode.player_rules.stamina if mode != null and mode.player_rules != null else 0
	append_found(found, [out_of_bounds("amount", amount, 0, most)])
	return found


func _test(ctx: MatchContext) -> bool:
	var player := ctx.actor_state()
	if player == null:
		return false
	StaminaLedger.settle_ahead(player, ctx.state.player_rules, ctx.tick)
	SelfStatusFeed.touch(ctx.state, player.peer)
	return StaminaLedger.covers(player, Ticks.thousandths(amount))


func _reason() -> StringName:
	return TIRED
