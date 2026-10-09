class_name FixtureThrow
extends RuleEffect
## Puts an item in flight for #642's flight tests (the real effect is ThrowItem, tested through
## FixtureThrowModes): kept because those tests' numbers and Use rule lie outside ThrowItem's
## bounds and required conditions. The actor's hand item leaves from
## its eye (Items.eye_of) along the intent's facing at `speed_mps`, with `gravity`, `radius_m` and
## `longest_ticks` set on the flight, and the fallback rest asked below the actor's feet
## (Items.fallback_rest); then Items.launch. A facing that does not normalize, or an empty hand,
## does nothing. The numbers are a test's, not a decision.

@export var speed_mps := 10.0
@export var gravity := Vector3(0.0, -9.8, 0.0)
@export var radius_m := 0.15
@export var longest_ticks := 60


static func of(speed: float, longest: int = 60, radius: float = 0.15) -> FixtureThrow:
	var effect := FixtureThrow.new()
	effect.speed_mps = speed
	effect.longest_ticks = longest
	effect.radius_m = radius
	return effect


func run(ctx: MatchContext) -> void:
	var player := ctx.actor_state()
	var item := Items.held_by(ctx.state, ctx.actor)
	var facing := ctx.command.get_vector3("facing") if ctx.command != null else Vector3.ZERO
	if item == null or not facing.is_finite() or facing.is_zero_approx():
		return
	var flight := ItemFlight.new(
		Items.eye_of(ctx, player),
		facing.normalized() * speed_mps,
		gravity,
		Items.fallback_rest(ctx, player.position),
		ctx.actor,
		radius_m,
		longest_ticks
	)
	Items.launch(ctx, item, flight)
