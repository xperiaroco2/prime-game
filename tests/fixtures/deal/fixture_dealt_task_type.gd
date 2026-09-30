class_name FixtureDealtTaskType
extends TaskType
## A fake task type for DealTasks' tests (ARCHITECTURE §9.4): each task is one subtask, a token
## item. Its deal places one token per task on distinct random markers of the token kind's spawn
## tag (ids in the markers' level order), binds the tokens to the tasks of the players in peer-id
## order with its own RNG purpose, emits ItemSpawned (everyone) in id order and TasksAssigned to
## each owner, then raises item_rested (spawn) per token. Its check of a fact emits a note
## "<id> rested <item> <cause>" for item_rested, so tests see which facts reached task types.
##
## With a `station` kind, each token also belongs to a station, as Delivery's package belongs to
## its circle (§9.5; the real deal is Delivery's, 2f): one station per token on the station
## kind's markers in level order, coloured from its palette in order. StationPlaced (everyone) is
## emitted in station-id order before the ItemSpawned, which then carry the station and colour.


## One task's state: the token it must move (never done here).
class FixtureDealtState:
	extends TaskState

	var targets: Array[int] = []

	func total() -> int:
		return targets.size()


var token: ItemKind
## The station kind each token belongs to, or null for tokens without a station.
var station: StationKind
var rng_purpose: StringName = &"fixture_tasks"


func _init(type_id: StringName = &"fixture_dealt", token_kind: ItemKind = null) -> void:
	id = type_id
	token = token_kind


func new_state() -> TaskState:
	return FixtureDealtState.new()


func deal(ctx: MatchContext, per_player: int) -> void:
	var peers := ctx.state.present_peers()
	var total := peers.size() * per_player
	var free := SpawnItems.free_markers(ctx, token.spawn_tag)
	if free.size() < total:
		ctx.error("%s: %d free markers for %d tokens" % [id, free.size(), total])
		return
	var draw := RngStreams.shuffled_indices(free.size(), ctx.rng(rng_purpose))
	var chosen: Array[int] = []
	for i in total:
		chosen.append(draw[i])
	chosen.sort()
	var tokens: Array[ItemState] = []
	for index: int in chosen:
		tokens.append(ctx.state.add_item(token, free[index]))
	var stations: Array[StationState] = []
	if station != null:
		var at := ctx.layout.positions(station.spawn_tag)
		for i in tokens.size():
			stations.append(ctx.state.add_station(station, at[i], station.palette[i]))
	var binding := RngStreams.shuffled_indices(tokens.size(), ctx.rng(rng_purpose))
	var next := 0
	var assigned: Dictionary[int, Array] = {}
	for peer: int in peers:
		var tasks: Array[Dictionary] = []
		for i in per_player:
			var task := ctx.state.add_task(peer, self)
			var target := tokens[binding[next]].id
			next += 1
			(task.state as FixtureDealtState).targets.append(target)
			tasks.append({"task": task.id, "type": id, "targets": [{"item": target}]})
		assigned[peer] = tasks
	for placed: StationState in stations:
		ctx.emit(StationPlacedEvent.new(placed.id, station.id, placed.colour, placed.position))
	for i in tokens.size():
		var item := tokens[i]
		if stations.is_empty():
			ctx.emit(ItemSpawnedEvent.new(item.id, token.id, item.position))
		else:
			ctx.emit(
				ItemSpawnedEvent.new(
					item.id, token.id, item.position, stations[i].id, stations[i].colour
				)
			)
	for peer: int in peers:
		var tasks: Array[Dictionary] = []
		tasks.assign(assigned[peer])
		ctx.emit(TasksAssignedEvent.new(peer, tasks))
	for item: ItemState in tokens:
		var fact := Fact.new(Facts.ITEM_RESTED)
		fact.item = item.id
		fact.position = item.position
		fact.cause = SpawnItems.SPAWN
		ctx.raise_fact(fact)


func on_fact(ctx: MatchContext) -> void:
	if ctx.fact.name == Facts.ITEM_RESTED:
		ctx.emit(FixtureNoteEvent.new("%s rested %d %s" % [id, ctx.fact.item, ctx.fact.cause]))


func add_demands(
	_settings: Dictionary[StringName, int], players: int, per_player: int, into: Demands
) -> void:
	into.add_markers(token.spawn_tag, players * per_player)
	if station != null:
		into.add_markers(station.spawn_tag, players * per_player)
		into.add_colours(station, players * per_player)


func emits() -> Array[Script]:
	return [StationPlacedEvent, ItemSpawnedEvent, TasksAssignedEvent, FixtureNoteEvent]
