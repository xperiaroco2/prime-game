class_name SpawnItems
extends RuleEffect
## Places `count_setting` items of `kind` on distinct random markers of the kind's spawn tag
## (ARCHITECTURE §3.3, §9.4): a transition action of the deal (the knives). A deal puts at most
## one item on a marker, so the markers where an item already rests (Delivery's packages dealt
## just before, when their kinds share a tag) are skipped. The markers are drawn with the RNG
## purpose `rng_purpose`, then the items are added in the markers' level order, so item ids follow
## the spawn points and say nothing about the draw (§3.3).
##
## Emits: ItemSpawned for each item, in id order (everyone); then raises item_rested (cause
## `spawn`) for each, in id order, so a task type's check sees every spawned item (§7.1).
## Demands: `count_setting` markers of the kind's spawn tag.

## The cause of item_rested for an item a deal placed: the same name as Items.SPAWN (2e, #61).
const SPAWN := &"spawn"

## The item kind to place (Knife).
@export var kind: ItemKind
## The match setting that holds the count (`knives`).
@export var count_setting: StringName
## The RNG purpose of the draw (§3.3): `knives` in the base mode.
@export var rng_purpose: StringName


func run(ctx: MatchContext) -> void:
	if ctx.layout == null:
		ctx.error("SpawnItems: no layout for the level being entered")
		return
	var count := maxi(0, ctx.setting(count_setting))
	if count == 0:
		return
	var free := free_markers(ctx, kind.spawn_tag)
	if free.size() < count:
		ctx.error(
			(
				"SpawnItems: %d free %s marker(s) for %d %s item(s)"
				% [free.size(), kind.spawn_tag, count, kind.id]
			)
		)
		return
	var order := RngStreams.shuffled_indices(free.size(), ctx.rng(rng_purpose))
	var chosen: Array[int] = []
	for i in count:
		chosen.append(order[i])
	chosen.sort()
	var spawned: Array[ItemState] = []
	for index: int in chosen:
		spawned.append(ctx.state.add_item(kind, free[index]))
	for item: ItemState in spawned:
		ctx.emit(ItemSpawnedEvent.new(item.id, kind.id, item.position))
	for item: ItemState in spawned:
		_raise_rested(ctx, item)


## The markers of `tag` in the level being entered, in level order, on which no item rests: a
## deal puts at most one item on a marker (§3.3, §9.6).
static func free_markers(ctx: MatchContext, tag: StringName) -> PackedVector3Array:
	var free := PackedVector3Array()
	for at: Vector3 in ctx.layout.positions(tag):
		var taken := false
		for item: ItemState in ctx.state.items.values():
			if item.where != ItemState.Where.HAND and item.position == at:
				taken = true
				break
		if not taken:
			free.append(at)
	return free


## item_rested for a spawned item, with the fields and cause of Items.raise_rested (2e, #61);
## this becomes Items.raise_rested(ctx, item, Items.SPAWN) once #61 is merged.
static func _raise_rested(ctx: MatchContext, item: ItemState) -> void:
	var fact := Fact.new(Facts.ITEM_RESTED)
	fact.item = item.id
	fact.position = item.position
	fact.cause = SPAWN
	ctx.raise_fact(fact)


func emits() -> Array[Script]:
	return [ItemSpawnedEvent]


func add_demands(settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	var count: int = settings.get(count_setting, 0)
	if kind != null and count > 0:
		into.add_markers(kind.spawn_tag, count)


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if kind == null:
		found.append("SpawnItems has no kind")
	elif mode.find_item_kind(kind.id) == null:
		found.append("SpawnItems: item kind %s is not an item kind of the mode" % kind.id)
	if count_setting.is_empty():
		found.append("SpawnItems has no count_setting")
	if rng_purpose.is_empty():
		found.append("SpawnItems has no rng_purpose")
	return found
