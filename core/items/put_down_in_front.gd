class_name PutDownInFront
extends RuleEffect
## The actor's held item comes to rest `distance_m` in front of it (ARCHITECTURE §7.1, §9.4). The
## client sends only its facing; the host takes the facing's horizontal direction and asks
## WorldQuery.rest_position from the actor's eye (Items.eye_of: the floor below its last accepted
## position raised by the mode's PlayerRules.eye_height_m) towards the point `distance_m` along it:
## the item is stopped before a wall and dropped to the floor. A facing with no horizontal direction
## (straight up or down, zero or not finite) puts the item down below the eye, at the actor's feet.
## Run it after HoldsItem.
##
## Emits: ItemPlaced (put down, everyone), then the fact item_rested.

## Metres, 0.3 to 3. The neutral default is out of bounds on purpose: the data sets it (the base
## mode's PutDown: 1), so the mode check refuses a rule that forgot it.
@export var distance_m := 0.0


func run(ctx: MatchContext) -> void:
	var actor := ctx.actor_state()
	var item := Items.held_by(ctx.state, ctx.actor)
	if actor == null or item == null or ctx.state.player_rules == null:
		ctx.error("PutDownInFront: player %d holds no item" % ctx.actor)
		return
	var facing := ctx.command.get_vector3("facing") if ctx.command != null else Vector3.ZERO
	var ahead := Vector3(facing.x, 0.0, facing.z)
	if not ahead.is_finite() or ahead.is_zero_approx():
		ahead = Vector3.ZERO
	else:
		ahead = ahead.normalized()
	var eye := Items.eye_of(ctx, actor)
	var at := ctx.world.rest_position(eye, eye + ahead * distance_m)
	Items.place(ctx, item, at, Items.PUT_DOWN)


func emits() -> Array[Script]:
	return [ItemPlacedEvent]


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(found, [out_of_bounds("PutDownInFront distance_m", distance_m, 0.3, 3)])
	return found
