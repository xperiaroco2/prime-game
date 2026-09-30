class_name FixtureDealtTaskType
extends TaskType
## A fake task type for DealTasks' tests (ARCHITECTURE §9.4): one shared task of `tokens`
## subtasks, each a token item (#79: nobody owns it). Its deal places the tokens on distinct
## random free markers of the token kind's spawn tag (ids in the markers' level order) with its
## own RNG purpose, emits ItemSpawned (everyone) in id order, then raises item_rested (spawn) per
## token. Its check of a fact emits a note "<id> rested <item> <cause>" for item_rested, so tests
## see which facts reached task types.
##
## With a `station` kind, each token also belongs to a station, as Delivery's package belongs to
## its circle (§9.5): one station per token on the station kind's markers in level order,
## coloured from its palette in order. StationPlaced (everyone) is emitted in station-id order
## before the ItemSpawned, which then carry the station and colour.


## The task's state: the tokens it must move (never done here).
class FixtureDealtState:
	extends TaskState

	var targets: Array[int] = []

	func total() -> int:
		return targets.size()


var token: ItemKind
## The station kind each token belongs to, or null for tokens without a station.
var station: StationKind
## The subtasks of its task: one token each.
var tokens := 1
var rng_purpose: StringName = &"fixture_tasks"


func _init(type_id: StringName = &"fixture_dealt", token_kind: ItemKind = null, count := 1) -> void:
	id = type_id
	token = token_kind
	tokens = count


func new_state() -> TaskState:
	return FixtureDealtState.new()


func deal(ctx: MatchContext) -> void:
	var free := Items.free_markers(ctx, token.spawn_tag)
	if free.size() < tokens:
		ctx.error("%s: %d free markers for %d tokens" % [id, free.size(), tokens])
		return
	var draw := RngStreams.shuffled_indices(free.size(), ctx.rng(rng_purpose)).slice(0, tokens)
	draw.sort()
	var task := ctx.state.add_task(self)
	var placed: Array[ItemState] = []
	for index: int in draw:
		var item := ctx.state.add_item(token, free[index])
		placed.append(item)
		(task.state as FixtureDealtState).targets.append(item.id)
	var stations: Array[StationState] = []
	if station != null:
		var at := ctx.layout.positions(station.spawn_tag)
		for i in placed.size():
			stations.append(ctx.state.add_station(station, at[i], station.palette[i]))
	for made: StationState in stations:
		ctx.emit(StationPlacedEvent.new(made.id, station.id, made.colour, made.position))
	for i in placed.size():
		var item := placed[i]
		if stations.is_empty():
			ctx.emit(ItemSpawnedEvent.new(item.id, token.id, item.position))
		else:
			ctx.emit(
				ItemSpawnedEvent.new(
					item.id, token.id, item.position, stations[i].id, stations[i].colour
				)
			)
	for item: ItemState in placed:
		Items.raise_rested(ctx, item, Items.SPAWN)


func on_fact(ctx: MatchContext) -> void:
	if ctx.fact.name == Facts.ITEM_RESTED:
		ctx.emit(FixtureNoteEvent.new("%s rested %d %s" % [id, ctx.fact.item, ctx.fact.cause]))


func add_demands(_settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	into.add_markers(token.spawn_tag, tokens)
	if station != null:
		into.add_markers(station.spawn_tag, tokens)
		into.add_colours(station, tokens)


func emits() -> Array[Script]:
	return [StationPlacedEvent, ItemSpawnedEvent, FixtureNoteEvent]
