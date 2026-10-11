class_name FixtureKillingRound
extends RoundPhase
## A Round that queues the kill of the player in the setting `kills` while it is living
## (LifeRules.kill_later; the car repair ADR's RE17, #806): from its own timers (Phase.on_tick),
## and on entry too when `on_enter` is 1.


func enter(ctx: MatchContext) -> void:
	if setting(&"on_enter", 0) > 0:
		_queue(ctx)


func on_tick(ctx: MatchContext) -> void:
	if setting(&"on_enter", 0) == 0:
		_queue(ctx)


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(settings, {&"kills": Vector2(0, 1000), &"on_enter": Vector2(0, 1)})


func _queue(ctx: MatchContext) -> void:
	var victim := ctx.state.player(int(setting(&"kills", 0)))
	if victim != null and victim.is_alive():
		LifeRules.kill_later(ctx, victim.peer)
