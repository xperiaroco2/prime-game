class_name FixtureItemMove
extends RuleEffect
## Stands in for the cooking task's parts in tests (C1's GiveItem, C3's grill, C4's places; the
## cooking ADR, CE4, CE5, CE19, CE20): an effect of a mode-level Use rule that runs one Items move,
## as `move` says (a test may set `move`, `kind` and `at` between two Use commands):
## - GIVE: a new item of `kind` spawned at `at` (Items.spawn, ItemSpawned), then given to the actor
##   (Items.give), as a box's take.
## - GIVE_AT: the item lying or locked at `at` given to the actor (Items.give), as the grill's
##   take-off.
## - HAND_OUT_AT: the item lying or locked at `at` handed out to the actor (Items.hand_out, a
##   two-handed one too), as the ship crystal's socket and charger (#1461).
## - LOCK: the actor's hand item locked at `at` (Items.lock_at), as a patty put on the grill.
## - LAY: the actor's hand item laid at `at` (Items.lay_on_station), as a wrong ingredient.
## - CHANGE: the item lying or locked at `at` becomes `kind` (Items.change_kind).
## - CHANGE_HELD: the actor's hand item becomes `kind`.
##
## mode(): FixtureItemModes.basic() with the one-handed kinds `herb`, `raw` and `fried` (no
## actions, so Use with one in the hand reaches the mode's rule) and a Use rule running a new
## FixtureItemMove (the mode's `actions` last; move_of() returns it).

const GIVE := &"give"
const GIVE_AT := &"give_at"
const HAND_OUT_AT := &"hand_out_at"
const LOCK := &"lock"
const LAY := &"lay"
const CHANGE := &"change"
const CHANGE_HELD := &"change_held"

@export var move := GIVE
@export var kind: ItemKind
@export var at := Vector3.ZERO


func run(ctx: MatchContext) -> void:
	match move:
		GIVE:
			var made := Items.spawn(ctx, kind, at)
			ctx.emit(ItemSpawnedEvent.new(made.id, kind.id, at))
			Items.give(ctx, ctx.actor, made)
		GIVE_AT:
			Items.give(ctx, ctx.actor, _at(ctx))
		HAND_OUT_AT:
			Items.hand_out(ctx, ctx.actor, _at(ctx))
		LOCK:
			Items.lock_at(ctx, Items.held_by(ctx.state, ctx.actor), at)
		LAY:
			Items.lay_on_station(ctx, Items.held_by(ctx.state, ctx.actor), at)
		CHANGE:
			Items.change_kind(ctx, _at(ctx), kind)
		CHANGE_HELD:
			Items.change_kind(ctx, Items.held_by(ctx.state, ctx.actor), kind)


func emits() -> Array[Script]:
	return [ItemSpawnedEvent, ItemPickedUpEvent, ItemPlacedEvent, ItemChangedEvent]


## The fixture item mode with `herb`, `raw` and `fried`, and a Use rule running a FixtureItemMove.
static func mode() -> GameMode:
	var made := FixtureItemModes.basic()
	for id: StringName in [&"herb", &"raw", &"fried"]:
		made.item_kinds.append(FixtureItemModes.item_kind(id, []))
	made.actions.append(FixtureModes.rule(Intents.USE, [], [FixtureItemMove.new()]))
	return made


## The FixtureItemMove of mode()'s Use rule in `game`.
static func move_of(game: Match) -> FixtureItemMove:
	return game.mode.actions[-1].effects[0] as FixtureItemMove


## Sets the move (with its kind, by id, and spot) and sends `peer`'s Use.
static func use(
	game: Match, peer: int, what: StringName, at_spot: Vector3, kind_id: StringName = &""
) -> void:
	var effect := move_of(game)
	effect.move = what
	effect.at = at_spot
	effect.kind = game.mode.find_item_kind(kind_id) if kind_id != &"" else null
	FixtureModes.send(game, Intents.USE, peer, {"facing": Vector3.FORWARD})


## The lowest-id item that lies or is locked exactly at `at`, or null.
func _at(ctx: MatchContext) -> ItemState:
	var found: ItemState = null
	for item: ItemState in ctx.state.items.values():
		if item.is_carried() or item.is_in_flight() or item.position != at:
			continue
		if found == null or item.id < found.id:
			found = item
	return found
