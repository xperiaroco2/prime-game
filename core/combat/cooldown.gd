class_name Cooldown
extends Cost
## A minimum time between two payments of one key by one player (ARCHITECTURE §9.4, §7.1): the
## knife's hit interval (key `hit`). Passes when the actor never paid `key`, or at least `seconds`
## (converted to host ticks toward zero, §3.3) passed since it last did; paying records the tick in
## MatchState's cooldown table. The key belongs to the player, not to the item, so swapping to a
## second knife does not skip the interval. ResetMatch clears the table.
##
## Rejects with `too_soon`: it reveals only the actor's own timing. Emits nothing.

## The rejection reason: the actor paid this key less than `seconds` ago.
const TOO_SOON := &"too_soon"

## The name the payments are recorded under (the knife: `hit`). The neutral default is refused by
## the mode check: the data names it.
@export var key: StringName
## Seconds, 0 to 600.
@export var seconds := 0.0


func pay(ctx: MatchContext) -> void:
	ctx.state.set_cooldown_paid(ctx.actor, key, ctx.tick)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if key.is_empty():
		found.append("Cooldown has no key")
	append_found(found, [out_of_bounds("Cooldown seconds", seconds, 0, 600)])
	return found


func _test(ctx: MatchContext) -> bool:
	if ctx.actor_state() == null:
		return false
	var paid_at := ctx.state.cooldown_paid_at(ctx.actor, key)
	return paid_at < 0 or ctx.tick - paid_at >= Ticks.from_seconds(seconds)


func _reason() -> StringName:
	return TOO_SOON
