class_name Delivery
extends TaskType
## The MVP's task type (ARCHITECTURE §3.3, §7.1, §9.5): a task of `subtasks_setting` packages; a
## subtask is done when its package rests inside its own circle, however it got there (put down,
## swapped, dropped at a death or a leave, spawned there, later thrown).
##
## The deal (DealTasks, 2c, calls deal()): players x tasks per player x subtasks packages. Circles
## on distinct random `circle.spawn_tag` markers, with distinct random colours of the palette;
## packages on distinct random `package.spawn_tag` markers; then per player in peer-id order its
## tasks, each package drawn from the placed ones and bound to a random circle of its own, whose
## colour it takes. Station and item ids follow spawn-point order, and StationPlaced and
## ItemSpawned go out in id order, so an id says nothing about its owner. Then item_rested
## (spawn) for each package, so one that spawned inside its own circle is delivered at once.
##
## The check (on_fact, on item_rested): a package of an undone subtask that rests on the ground
## within its circle's radius (horizontally) and within `floor_tolerance_m` of the circle's height
## (the circle's floor) is delivered: locked (PickUp gets `unavailable`), its circle done, its
## subtask done. A held package never counts: holding raises no item_rested.
##
## Emits: StationPlaced, ItemSpawned (everyone), TasksAssigned (the owner) in the deal;
## PackageDelivered, TaskProgress (everyone) and TaskUpdated (the owner) on a delivery. Raises
## item_rested (spawn) in the deal and subtask_done on a delivery.


## Delivery's task state (§9.1): per subtask, in order, its package, its circle and whether it is
## done. Only Delivery reads and writes it.
class State:
	extends TaskState

	## Item ids, one per subtask.
	var packages := PackedInt32Array()
	## Station ids, one per subtask: the package's circle.
	var circles := PackedInt32Array()
	var done: Array[bool] = []

	func done_count() -> int:
		return done.count(true)

	func total() -> int:
		return packages.size()


## The item kind of the packages (the base mode's Package).
@export var package: ItemKind
## The station kind of the circles: spawn tag, radius and colour palette. One circle per package
## is fixed in v0, not a setting (MVP rules).
@export var circle: StationKind
## The match setting of the subtasks per task (`subtasks_per_task`).
@export var subtasks_setting: StringName
## How far above or below the circle's position a resting package may be and still be on the
## circle's floor, in metres (0.01 to 2). The neutral default is out of bounds on purpose: the
## data sets it. A placeholder, "not a decision" (no ADR gives it).
@export var floor_tolerance_m := 0.0
## The RNG purposes it draws from (§3.3).
@export var circles_rng: StringName = &"circles"
@export var packages_rng: StringName = &"packages"
@export var tasks_rng: StringName = &"tasks"


func new_state() -> TaskState:
	return State.new()


func deal(ctx: MatchContext, per_player: int) -> void:
	var peers := ctx.state.present_peers()
	var subtasks := ctx.setting(subtasks_setting)
	var count := peers.size() * per_player * subtasks
	if count <= 0:
		return
	if not _fits(ctx, count):
		return
	var stations := _place_circles(ctx, count)
	var items := _place_packages(ctx, count)
	# Each package is bound to a circle of its own: two independent permutations, walked together.
	var package_order := RngStreams.shuffled_indices(count, ctx.rng(tasks_rng))
	var circle_order := RngStreams.shuffled_indices(count, ctx.rng(tasks_rng))
	var circle_of: Dictionary[int, StationState] = {}
	var dealt: Dictionary[int, Array] = {}
	var next := 0
	for peer: int in peers:
		var entries: Array[Dictionary] = []
		for t in per_player:
			var task := ctx.state.add_task(peer, self)
			var task_state := task.state as State
			var targets: Array[Dictionary] = []
			for s in subtasks:
				var item := items[package_order[next]]
				var station := stations[circle_order[next]]
				next += 1
				task_state.packages.append(item.id)
				task_state.circles.append(station.id)
				task_state.done.append(false)
				circle_of[item.id] = station
				targets.append({"item": item.id})
			entries.append(TasksAssignedEvent.task_entry(task.id, id, targets))
		dealt[peer] = entries
	for station: StationState in stations:
		ctx.emit(StationPlacedEvent.new(station.id, circle.id, station.colour, station.position))
	for item: ItemState in items:
		var bound := circle_of[item.id]
		ctx.emit(ItemSpawnedEvent.new(item.id, package.id, item.position, bound.id, bound.colour))
	for peer: int in peers:
		var entries: Array[Dictionary] = []
		entries.assign(dealt[peer])
		ctx.emit(TasksAssignedEvent.new(peer, entries))
	for item: ItemState in items:
		Items.raise_rested(ctx, item, Items.SPAWN)


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
		var index := task_state.packages.find(item.id)
		if index < 0 or task_state.done[index]:
			continue
		var station: StationState = ctx.state.stations.get(task_state.circles[index])
		if station == null or not rests_in(item.position, station):
			return
		item.where = ItemState.Where.LOCKED
		station.done = true
		task_state.done[index] = true
		ctx.emit(PackageDeliveredEvent.new(item.id, station.id))
		Tasks.subtask_done(ctx, task, {"subtask": index, "item": item.id})
		return


## Whether a package resting at `at` is inside `station`: within its radius horizontally, and on
## its floor, within floor_tolerance_m of its height.
func rests_in(at: Vector3, station: StationState) -> bool:
	var flat := Vector2(at.x - station.position.x, at.z - station.position.z)
	return (
		flat.length() <= station.kind.radius_m
		and absf(at.y - station.position.y) <= floor_tolerance_m
	)


## As many `circle` and `package` markers as packages, and as many palette colours as circles:
## colours never repeat (§9.4).
func add_demands(
	settings: Dictionary[StringName, int], players: int, per_player: int, into: Demands
) -> void:
	if circle == null or package == null:
		return  # ModeCheck refuses such a mode.
	var subtasks: int = settings.get(subtasks_setting, 0)
	var count := players * per_player * subtasks
	into.add_markers(circle.spawn_tag, count)
	into.add_markers(package.spawn_tag, count)
	into.add_colours(circle, count)


func emits() -> Array[Script]:
	return [
		StationPlacedEvent,
		ItemSpawnedEvent,
		TasksAssignedEvent,
		PackageDeliveredEvent,
		TaskProgressEvent,
		TaskUpdatedEvent,
	]


func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	if package == null:
		found.append("Delivery %s has no package item kind" % id)
	elif mode.find_item_kind(package.id) == null:
		found.append(
			"Delivery %s names item kind %s, which the mode does not declare" % [id, package.id]
		)
	if circle == null:
		found.append("Delivery %s has no circle station kind" % id)
	elif package != null and circle.spawn_tag == package.spawn_tag:
		# One tag would let packages spawn on circle markers, delivered before anyone moves.
		found.append(
			"Delivery %s: circle and package share spawn tag %s" % [id, circle.spawn_tag]
		)
	if subtasks_setting.is_empty():
		found.append("Delivery %s has no subtasks_setting" % id)
	if circles_rng.is_empty() or packages_rng.is_empty() or tasks_rng.is_empty():
		found.append("Delivery %s has an empty RNG purpose" % id)
	append_found(
		found, [out_of_bounds("Delivery %s floor_tolerance_m" % id, floor_tolerance_m, 0.01, 2)]
	)
	return found


## Whether the level being entered has the markers and the palette the colours for `count`
## packages; the lobby's fit check (§9.4) keeps a match from getting here without them.
func _fits(ctx: MatchContext, count: int) -> bool:
	if ctx.layout == null:
		ctx.error("Delivery: no layout for the level being entered")
		return false
	var circles := ctx.layout.count(circle.spawn_tag)
	var packages := ctx.layout.count(package.spawn_tag)
	if circles < count or packages < count or circle.palette.size() < count:
		(
			ctx
			. error(
				(
					(
						"Delivery: %d packages need as many %s and %s markers and colours; the map has %d"
						+ " and %d, the palette %d"
					)
					% [
						count,
						circle.spawn_tag,
						package.spawn_tag,
						circles,
						packages,
						circle.palette.size()
					]
				)
			)
		)
		return false
	return true


## `count` circles on distinct random markers, in spawn-point order, with distinct random colours.
func _place_circles(ctx: MatchContext, count: int) -> Array[StationState]:
	var spots := ctx.layout.positions(circle.spawn_tag)
	var markers := _pick(spots.size(), count, ctx.rng(circles_rng))
	var colours := RngStreams.shuffled_indices(circle.palette.size(), ctx.rng(circles_rng))
	var placed: Array[StationState] = []
	for i in count:
		placed.append(ctx.state.add_station(circle, spots[markers[i]], circle.palette[colours[i]]))
	return placed


## `count` packages on distinct random markers, in spawn-point order.
func _place_packages(ctx: MatchContext, count: int) -> Array[ItemState]:
	var spots := ctx.layout.positions(package.spawn_tag)
	var markers := _pick(spots.size(), count, ctx.rng(packages_rng))
	var placed: Array[ItemState] = []
	for i in count:
		placed.append(ctx.state.add_item(package, spots[markers[i]]))
	return placed


## `count` distinct indices of `available`, drawn from `rng`, in ascending (level) order.
static func _pick(available: int, count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var chosen := RngStreams.shuffled_indices(available, rng).slice(0, count)
	chosen.sort()
	return chosen
