class_name FixtureKillingRound
extends RoundPhase
## A Round whose own timers (Phase.on_tick) queue the kill of the player in the setting `kills`
## while it is living (LifeRules.kill_later; the car repair ADR's RE17, #806).


func on_tick(ctx: MatchContext) -> void:
	var victim := ctx.state.player(int(setting(&"kills", 0)))
	if victim != null and victim.is_alive():
		LifeRules.kill_later(ctx, victim.peer)


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(settings, {&"kills": Vector2(0, 1000)})
