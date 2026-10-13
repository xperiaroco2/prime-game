class_name DeliveryByMeaning
extends TaskType
## Delivery by meaning (#683's ADR, ARCHITECTURE §3.3, §7.1.14, §9.5.24): the House's Delivery.
## One shared task of `subtasks_setting` items, each carried to the one place where its kind
## belongs (its route's drop-off), not to a colour. Nobody owns the task: any living player
## delivers any item. Today's Delivery (colour circles) stays its own class on the greybox (DE15).
##
## The deal (ADR §2.1; N the setting, K the routes): the routes are shuffled (`tasks_rng`); the
## route at shuffled position p gets floor(N / K) items plus one if p < N mod K, so every route has
## an item before any has a second (DD2 (a)). One station per drop-off that got an item, on its
## tag's one marker, in `routes` order of first appearance: station ids follow `routes`, not the
## level. Items per item spawn tag, the tags in `routes` order of first appearance: the tag's
## items, listed route by route in shuffled order, get as many distinct random free markers
## (`packages_rng`, level order), then a permutation (`packages_rng`, drawn next) gives each listed
## item its marker; item ids follow the markers' level order, tag after tag. Subtask i is the i-th
## item in id order, bound to its route's drop-off station. StationPlaced (white, no palette) and
## ItemSpawned (its drop-off station, white: DE5 (b)) go out in id order, then item_rested (spawn)
## per item, so one that spawned inside its own drop-off is delivered at once. With N = 0 the task
## has no subtasks, and so is done.
##
## The check (on_fact, on item_rested): an item of an undone subtask resting on the ground inside
## its own drop-off's cylinder is delivered: locked, its subtask done, and its drop-off done once
## every item routed to it this round is delivered (DE7). An item in another route's place, or any
## other item there, does nothing (DD5 (a)); a held item never counts.
##
## Emits: StationPlaced, ItemSpawned (everyone) in the deal; PackageDelivered, TaskState and
## TaskProgress (everyone) on a delivery. Raises item_rested (spawn) in the deal and subtask_done
## on a delivery.

## The colour of a drop-off and of its items on the wire: a drop-off has no palette (DE5 (b)).
const WHITE := Color(1, 1, 1)


## Its task state (§9.1): per subtask, in order, its item, its drop-off station and whether it is
## done. Only DeliveryByMeaning reads and writes it.
class State:
	extends TaskState

	## Item ids, one per subtask, in id order.
	var items := PackedInt32Array()
	## Station ids, one per subtask: its item's drop-off.
	var stations := PackedInt32Array()
	var done: Array[bool] = []

	func done_count() -> int:
		return done.count(true)

	func total() -> int:
		return items.size()


## Which item kind goes to which place (DE2).
@export var routes: Array[DeliveryRoute] = []
## The RNG purposes it draws from (§3.3, DE6): the items' markers and which listed item takes
## which, and the routes' order. No `circles`: a drop-off stands on its one marker.
@export var packages_rng: StringName = &"packages"
@export var tasks_rng: StringName = &"tasks"


func new_state() -> TaskState:
	return State.new()


## The routes' drop-offs, each once, in `routes` order (DE4): the one finder of its station kinds.
func station_kinds() -> Array[StationKind]:
	var found: Array[StationKind] = []
	for route: DeliveryRoute in routes:
		if route != null and route.drop_off != null and not found.has(route.drop_off):
			found.append(route.drop_off)
	return found


## The routes' item spawn tags, each once, in `routes` order: the items lie there before anyone
## moves them.
func item_spawn_tags() -> Array[StringName]:
	var found: Array[StringName] = []
	for route: DeliveryRoute in routes:
		if route == null or route.item == null or route.item.spawn_tag.is_empty():
			continue
		if not found.has(route.item.spawn_tag):
			found.append(route.item.spawn_tag)
	return found


## The item count of each route (by its index in `routes`) when the route at shuffled position p
## (`order[p]`) gets floor(n / k) items plus one if p < n mod k (DD2 (a)).
static func counts(n: int, order: PackedInt32Array) -> PackedInt32Array:
	var k := order.size()
	var found := PackedInt32Array()
	found.resize(k)
	if k == 0:
		return found
	@warning_ignore("integer_division")
	var each := n / k
	for p in k:
		found[order[p]] = each + (1 if p < n % k else 0)
	return found


func deal(ctx: MatchContext) -> void:
	var count := ctx.setting(subtasks_setting)
	if count <= 0:
		ctx.state.add_task(self)
		return
	if not _well_formed():
		ctx.error("DeliveryByMeaning %s: a route has no item or no drop-off" % id)
		return
	var order := RngStreams.shuffled_indices(routes.size(), ctx.rng(tasks_rng))
	var per_route := counts(count, order)
	if not _fits(ctx, per_route, order):
		return
	var station_of := _place_drop_offs(ctx, per_route)
	var items := _place_items(ctx, per_route, order)
	# Every item id in use (Items.spawn logged it): no deal comes near that.
	if items.size() < count:
		return
	var task := ctx.state.add_task(self)
	var task_state := task.state as State
	var bound: Dictionary[int, StationState] = {}
	for entry: Array in items:
		var item := entry[0] as ItemState
		var station := station_of[routes[entry[1] as int].drop_off]
		task_state.items.append(item.id)
		task_state.stations.append(station.id)
		task_state.done.append(false)
		bound[item.id] = station
	for station: StationState in station_of.values():
		ctx.emit(StationPlacedEvent.new(station.id, station.kind.id, WHITE, station.position))
	for entry: Array in items:
		var item := entry[0] as ItemState
		ctx.emit(
			ItemSpawnedEvent.new(item.id, item.kind.id, item.position, bound[item.id].id, WHITE)
		)
	for entry: Array in items:
		Items.raise_rested(ctx, entry[0] as ItemState, Items.SPAWN)


func on_fact(ctx: MatchContext) -> void:
	if ctx.fact.name != Facts.ITEM_RESTED:
		return
	var item: ItemState = ctx.state.items.get(ctx.fact.item)
	if item == null or item.where != ItemState.Where.GROUND:
		return
	for task_id: int in ctx.state.tasks:
		var task := ctx.state.tasks[task_id]
		if task.type != self:
			continue
		var task_state := task.state as State
		var index := task_state.items.find(item.id)
		if index < 0 or task_state.done[index]:
			continue
		var station: StationState = ctx.state.stations.get(task_state.stations[index])
		if station == null or not station.contains(item.position):
			return
		Items.lock(item)
		task_state.done[index] = true
		station.done = _all_done_at(task_state, station.id)
		ctx.emit(PackageDeliveredEvent.new(item.id, station.id))
		Tasks.subtask_done(ctx, task, {"subtask": index, "item": item.id})
		return


## While N > 0: exactly one marker of each drop-off's tag (GE10), and per item spawn tag the most
## items a draw can put there (DE6): min(N, r * floor(N / K) + min(r, N mod K)) with r the routes
## whose kind has that tag. No colours: a drop-off has no palette.
func add_demands(settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	if routes.is_empty() or not _well_formed():
		return  # ModeCheck refuses such a mode.
	var count: int = maxi(settings.get(subtasks_setting, 0) as int, 0)
	if count == 0:
		return
	var k := routes.size()
	@warning_ignore("integer_division")
	var each := count / k
	for kind: StationKind in station_kinds():
		into.add_markers(kind.spawn_tag, 1, true)
	for tag: StringName in item_spawn_tags():
		var r := 0
		for route: DeliveryRoute in routes:
			if route.item.spawn_tag == tag:
				r += 1
		into.add_markers(tag, mini(count, r * each + mini(r, count % k)))


func emits() -> Array[Script]:
	return [
		StationPlacedEvent,
		ItemSpawnedEvent,
		PackageDeliveredEvent,
		TaskStateEvent,
		TaskProgressEvent,
	]


func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	if routes.is_empty():
		found.append("DeliveryByMeaning %s has no routes" % id)
	var kinds: Array[StringName] = []
	for index in routes.size():
		var route := routes[index]
		if route == null:
			found.append("DeliveryByMeaning %s: route %d is empty" % [id, index])
			continue
		if route.item == null:
			found.append("DeliveryByMeaning %s: route %d has no item kind" % [id, index])
		else:
			_check_item(mode, route.item, index, found)
			if kinds.has(route.item.id):
				found.append(
					"DeliveryByMeaning %s: item kind %s is in two routes" % [id, route.item.id]
				)
			kinds.append(route.item.id)
		if route.drop_off == null:
			found.append("DeliveryByMeaning %s: route %d has no drop-off" % [id, index])
		elif not route.drop_off.palette.is_empty():
			# A palette suggests a colour the game never shows (DE13).
			found.append(
				"DeliveryByMeaning %s: the drop-off %s has a palette" % [id, route.drop_off.id]
			)
	var item_tags := item_spawn_tags()
	for kind: StationKind in station_kinds():
		if item_tags.has(kind.spawn_tag):
			# One tag would let an item spawn on a drop-off marker, delivered before anyone moves.
			found.append(
				(
					"DeliveryByMeaning %s: the drop-off %s and an item kind share spawn tag %s"
					% [id, kind.id, kind.spawn_tag]
				)
			)
	if packages_rng.is_empty() or tasks_rng.is_empty():
		found.append("DeliveryByMeaning %s has an empty RNG purpose" % id)
	return found


func _check_item(mode: GameMode, kind: ItemKind, index: int, found: PackedStringArray) -> void:
	if mode != null and mode.find_item_kind(kind.id) == null:
		found.append(
			(
				"DeliveryByMeaning %s: route %d names item kind %s, which the mode does not declare"
				% [id, index, kind.id]
			)
		)
	if kind.spawn_tag.is_empty():
		# The deal places the items on markers (CE18 (a)).
		found.append(
			"DeliveryByMeaning %s: the item kind %s has no spawn_tag to place it on" % [id, kind.id]
		)
	if kind.vanishes():
		# The task knows an item by its id alone, and a vanished item's id is reused.
		found.append("DeliveryByMeaning %s: the item kind %s must not vanish" % [id, kind.id])


func _well_formed() -> bool:
	for route: DeliveryRoute in routes:
		if route == null or route.item == null or route.drop_off == null:
			return false
	return true


## Whether every subtask whose drop-off is `station` is done (DE7).
func _all_done_at(task_state: State, station: int) -> bool:
	for i in task_state.stations.size():
		if task_state.stations[i] == station and not task_state.done[i]:
			return false
	return true


## The drop-offs a route with an item needs, each once, in `routes` order.
func _used_drop_offs(per_route: PackedInt32Array) -> Array[StationKind]:
	var found: Array[StationKind] = []
	for r in routes.size():
		if per_route[r] > 0 and not found.has(routes[r].drop_off):
			found.append(routes[r].drop_off)
	return found


## The route indices of `tag`'s items, route by route in shuffled order, each its route's count.
func _listed(tag: StringName, per_route: PackedInt32Array, order: PackedInt32Array) -> Array[int]:
	var found: Array[int] = []
	for r: int in order:
		if routes[r].item.spawn_tag == tag:
			for i in per_route[r]:
				found.append(r)
	return found


## Whether the level being entered has a marker for each drop-off in use and enough free item
## markers; the lobby's fit check (§9.4) keeps a match from getting here without them.
func _fits(ctx: MatchContext, per_route: PackedInt32Array, order: PackedInt32Array) -> bool:
	if ctx.layout == null:
		ctx.error("DeliveryByMeaning %s: no layout for the level being entered" % id)
		return false
	for kind: StationKind in _used_drop_offs(per_route):
		if ctx.layout.count(kind.spawn_tag) < 1:
			ctx.error("DeliveryByMeaning %s: the map has no %s marker" % [id, kind.spawn_tag])
			return false
	for tag: StringName in item_spawn_tags():
		var need := _listed(tag, per_route, order).size()
		var have := Items.free_markers(ctx, tag).size()
		if have < need:
			ctx.error(
				(
					"DeliveryByMeaning %s: %d items need as many free %s markers; the map has %d"
					% [id, need, tag, have]
				)
			)
			return false
	return true


## One station per drop-off in use, on its tag's one marker, in `routes` order.
func _place_drop_offs(
	ctx: MatchContext, per_route: PackedInt32Array
) -> Dictionary[StationKind, StationState]:
	var found: Dictionary[StationKind, StationState] = {}
	for kind: StationKind in _used_drop_offs(per_route):
		found[kind] = ctx.state.add_station(kind, ctx.layout.positions(kind.spawn_tag)[0], WHITE)
	return found


## The items, tag after tag, each tag's in its markers' level order: [ItemState, route index] each.
func _place_items(
	ctx: MatchContext, per_route: PackedInt32Array, order: PackedInt32Array
) -> Array[Array]:
	var placed: Array[Array] = []
	for tag: StringName in item_spawn_tags():
		var listed := _listed(tag, per_route, order)
		if listed.is_empty():
			continue
		var spots := Items.free_markers(ctx, tag)
		var markers := Tasks.pick(spots.size(), listed.size(), ctx.rng(packages_rng))
		var which := RngStreams.shuffled_indices(listed.size(), ctx.rng(packages_rng))
		for m in listed.size():
			var route := listed[which[m]]
			var item := Items.spawn(ctx, routes[route].item, spots[markers[m]])
			if item == null:
				return placed
			placed.append([item, route])
	return placed
