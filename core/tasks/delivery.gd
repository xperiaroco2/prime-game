class_name Delivery
extends TaskType
## The MVP's task type (ARCHITECTURE §3.3, §7.1, §9.5): one shared task of `subtasks_setting`
## packages (the engineer's decision of 2026-09-30, #79); a subtask is done when its package
## rests inside its own circle, however it got there (put down, swapped, dropped at a death or a
## leave, spawned there, later thrown). Nobody owns the task: any living player delivers any
## package.
##
## The deal (DealTasks calls deal() when the draw picks Delivery): N packages and N circles, N the
## `packages` setting. Circles on distinct random `circle.spawn_tag` markers, each with its own
## random colour of the palette (colours never repeat); packages on distinct random free
## `package.spawn_tag` markers (Items.free_markers: a deal puts at most one item on a marker,
## whichever part places first); each package bound to a random circle of its own, whose colour
## it takes. Station and item ids follow spawn-point order; StationPlaced and ItemSpawned (with the
## circle and its colour) go out in id order. Then item_rested (spawn) for each package, so one
## that spawned inside its own circle is delivered at once. With N = 0 the task has no subtasks,
## and so is done.
##
## The check (on_fact, on item_rested): a package of an undone subtask resting on the ground inside
## its circle's cylinder (rests_in) is delivered: locked (PickUp gets `unavailable`), its circle
## done, its subtask done. A held package never counts: holding raises no item_rested.
##
## Emits: StationPlaced, ItemSpawned (everyone) in the deal; PackageDelivered and TaskProgress
## (everyone) on a delivery. Raises item_rested (spawn) in the deal and subtask_done on a
## delivery.

## How far below its circle's floor a rest position still counts: float noise between a floor the
## host's physics finds and a hand-placed marker, not a tolerance for a raised marker (§9.6).
## A placeholder, not a decision.
const FLOOR_SLACK_M := 0.001


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
## The station kind of the circles: spawn tag, radius, height and colour palette. One circle per
## package, fixed (#79), not a setting.
@export var circle: StationKind
## Delivery's own subtasks setting: the packages of its task (`packages`).
@export var subtasks_setting: StringName
## The RNG purposes it draws from (§3.3): the circles' markers and colours, the packages'
## markers, and which circle each package goes to.
@export var circles_rng: StringName = &"circles"
@export var packages_rng: StringName = &"packages"
@export var tasks_rng: StringName = &"tasks"


func new_state() -> TaskState:
	return State.new()


func deal(ctx: MatchContext) -> void:
	var count := ctx.setting(subtasks_setting)
	if count <= 0:
		ctx.state.add_task(self)
		return
	if not _fits(ctx, count):
		return
	var stations := _place_circles(ctx, count)
	var items := _place_packages(ctx, count)
	# Each package, in id order, goes to a circle of its own: a random permutation of the circles.
	var circle_order := RngStreams.shuffled_indices(count, ctx.rng(tasks_rng))
	var task := ctx.state.add_task(self)
	var task_state := task.state as State
	var circle_of: Dictionary[int, StationState] = {}
	for i in count:
		var station := stations[circle_order[i]]
		task_state.packages.append(items[i].id)
		task_state.circles.append(station.id)
		task_state.done.append(false)
		circle_of[items[i].id] = station
	for station: StationState in stations:
		ctx.emit(StationPlacedEvent.new(station.id, circle.id, station.colour, station.position))
	for item: ItemState in items:
		var bound := circle_of[item.id]
		ctx.emit(ItemSpawnedEvent.new(item.id, package.id, item.position, bound.id, bound.colour))
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


## Whether a package resting at `at` is inside `station`'s cylinder (#79): the circle stands on
## the floor at its marker, `radius_m` wide and `height_m` tall. `at` is the item's rest position,
## the one point core/ knows of an item: the centre of its base on the surface it rests on, as
## WorldQuery placed it (§7.1), not the centre of its mesh. Inside means within the radius
## horizontally, edge included, and from the circle's floor (the marker's height) up to floor +
## height, both included, the floor with FLOOR_SLACK_M of float noise below it: a package on a
## crate inside the circle counts, one on a floor below the marker or above the cylinder does not.
func rests_in(at: Vector3, station: StationState) -> bool:
	var flat := Vector2(at.x - station.position.x, at.z - station.position.z)
	var rise := at.y - station.position.y
	return (
		flat.length() <= station.kind.radius_m
		and rise >= -FLOOR_SLACK_M
		and rise <= station.kind.height_m
	)


## As many `circle` and `package` markers as packages, and as many palette colours as circles:
## colours never repeat (§9.4). The player count does not matter: the task is shared.
func add_demands(settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	if circle == null or package == null:
		return  # ModeCheck refuses such a mode.
	var count: int = maxi(settings.get(subtasks_setting, 0) as int, 0)
	into.add_markers(circle.spawn_tag, count)
	into.add_markers(package.spawn_tag, count)
	into.add_colours(circle, count)


func emits() -> Array[Script]:
	return [
		StationPlacedEvent,
		ItemSpawnedEvent,
		PackageDeliveredEvent,
		TaskProgressEvent,
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
		found.append("Delivery %s: circle and package share spawn tag %s" % [id, circle.spawn_tag])
	if subtasks_setting.is_empty():
		found.append("Delivery %s has no subtasks_setting" % id)
	if circles_rng.is_empty() or packages_rng.is_empty() or tasks_rng.is_empty():
		found.append("Delivery %s has an empty RNG purpose" % id)
	return found


## Whether the level being entered has the markers and the palette the colours for `count`
## packages; the lobby's fit check (§9.4) keeps a match from getting here without them.
func _fits(ctx: MatchContext, count: int) -> bool:
	if ctx.layout == null:
		ctx.error("Delivery: no layout for the level being entered")
		return false
	var circles := ctx.layout.count(circle.spawn_tag)
	var packages := Items.free_markers(ctx, package.spawn_tag).size()
	var colours := circle.palette.size()
	if circles >= count and packages >= count and colours >= count:
		return true
	var needs := (
		"Delivery: %d packages need as many %s and free %s markers and colours"
		% [count, circle.spawn_tag, package.spawn_tag]
	)
	ctx.error("%s; the map has %d and %d, the palette %d" % [needs, circles, packages, colours])
	return false


## `count` circles on distinct random markers, in spawn-point order, with distinct random colours.
func _place_circles(ctx: MatchContext, count: int) -> Array[StationState]:
	var spots := ctx.layout.positions(circle.spawn_tag)
	var markers := _pick(spots.size(), count, ctx.rng(circles_rng))
	var colours := RngStreams.shuffled_indices(circle.palette.size(), ctx.rng(circles_rng))
	var placed: Array[StationState] = []
	for i in count:
		placed.append(ctx.state.add_station(circle, spots[markers[i]], circle.palette[colours[i]]))
	return placed


## `count` packages on distinct random free markers, in spawn-point order.
func _place_packages(ctx: MatchContext, count: int) -> Array[ItemState]:
	var spots := Items.free_markers(ctx, package.spawn_tag)
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
