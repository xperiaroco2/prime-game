class_name Cooking
extends TaskType
## Cooking (#682; ARCHITECTURE §3.3, §9.5; the cooking ADR, 2026-10-10-cooking-task.md):
## one shared task whose subtasks are its N burgers, N the subtasks setting. Nobody owns it: any
## living player of any role takes from a box, picks a herb, uses the grill and fills a place.
## C3 (#772) built the data, the deal and the board events; C4 (#773) the uses of the grill, the
## beds and the places (use_problem, use_station) and the grill's tick (tick, through TaskTicks).
##
## The deal (DealTasks calls deal() when the draw picks it, on a map its `maps` lists; ADR §2.1,
## CE8): with N = 0 nothing at all is placed (no station, no box, no order, no HerbsDealt) and the
## task, with no subtasks, is done (#79). Otherwise the stations on fixed markers, so they draw
## nothing: the order board, the herb board and the grill on the first marker of their tags, a bed
## on each of the first `herbs.size()` `herb_bed` markers (the demands ask for exactly that many),
## then N places on the first N `place` markers, all in level order; station ids follow that order.
## Then one box per box kind on a random free marker of its own tag (`boxes_rng`), in the boxes'
## order. Then per place, in station order, its order: a bun, a raw patty kind and a herb, each
## drawn independently (`orders_rng`, CD11 (a): two orders may share a kind). Then the code, a
## random permutation of the herbs over the icons (`code_rng`), and the beds, a random permutation
## of the herbs over the beds (`beds_rng`, CD13 (b)). A map without the markers deals nothing and
## logs a match error (the fit check keeps a match from getting there).
##
## Emits, all to everyone and in this order: StationPlaced per station in id order, ItemSpawned
## per box in id order, OrderPosted per order in place order, then HerbsDealt; DealTasks then
## sends the task's TaskState and TaskProgress. Then item_rested (spawn) for each box, as
## Delivery's packages. An order carries its fried patty and its herb's icon, never the herb
## (CE9); no event names a player. Nothing reads a role.

## The bounds of `fry_seconds` and `burn_seconds`: ZoneTask's.
const MIN_SECONDS := ZoneTask.MIN_SECONDS
const MAX_SECONDS := ZoneTask.MAX_SECONDS
## The most herbs: an order's icon is a u8, and so is the length of HerbsDealt's lists (§4.3).
const MAX_HERBS := 255


## One burger (ADR CE12 (a)): its place, its order, the right items locked on its three slots and
## whether it is done. Red (wrong) ingredients are not tracked: they lie on the ground.
class Order:
	extends RefCounted

	## The place's station id.
	var station := -1
	var bun: ItemKind
	## The order's patty, raw: its fried kind (Cooking.fried_of) is the one the place takes.
	var raw_patty: ItemKind
	var herb: ItemKind
	## The right items on the slots, by item id (-1: the slot is empty).
	var bun_item := -1
	var patty_item := -1
	var herb_item := -1
	var done := false


## Cooking's state (§9.1, ADR CE12 (a)): the boards' and the grill's station ids, the beds' with
## each bed's herb of the round, the code, the orders in place order, and the grill's patty with
## its fried and burnt ticks. Only Cooking reads and writes it.
class State:
	extends TaskState

	var order_board := -1
	var herb_board := -1
	var grill := -1
	## The beds' station ids, in station order.
	var beds := PackedInt32Array()
	## The herb of the round on each bed, in the beds' order.
	var bed_herbs: Array[ItemKind] = []
	## The herb each icon means: code[icon].
	var code: Array[ItemKind] = []
	## One per place, in station order: subtask i is orders[i].
	var orders: Array[Order] = []
	## The patty on the grill, by item id (-1: the grill is empty), and the host ticks it turns
	## fried and burnt at (C4).
	var grill_item := -1
	var fried_tick := -1
	var burnt_tick := -1

	func done_count() -> int:
		var count := 0
		for order: Order in orders:
			if order.done:
				count += 1
		return count

	func total() -> int:
		return orders.size()


## The station kinds (CE6 (a)): the two boards are display kinds with no rule; the grill, the bed
## and the place each have an Interact rule ending in UseStation.
@export var order_board: StationKind
@export var herb_board: StationKind
@export var grill: StationKind
@export var herb_bed: StationKind
@export var place: StationKind
## The ingredient kinds, each one-handed: the buns, the raw patties, their fried kinds (index for
## index: fried_patties[i] is raw_patties[i] fried), the one burnt kind and the herbs.
@export var buns: Array[ItemKind] = []
@export var raw_patties: Array[ItemKind] = []
@export var fried_patties: Array[ItemKind] = []
@export var burnt: ItemKind
@export var herbs: Array[ItemKind] = []
## The box kinds (CE7 (a)), each two-handed, on markers of its own spawn tag, each with
## `target_actions` giving one bun or raw patty kind (GiveItem).
@export var boxes: Array[ItemKind] = []
## Cooking's own subtasks setting: its burgers.
@export var subtasks_setting: StringName
## How long a patty on the grill takes to turn fried from going on, and then to turn burnt from
## turning fried (ADR row 14: 10 s and 5 s, 200 and 100 ticks; §2.4: burnt at now plus 300): each
## 0.05 to 600. The neutral defaults are out of bounds on purpose: the data sets them.
@export var fry_seconds := 0.0
@export var burn_seconds := 0.0
## The RNG purposes it draws from (§3.3, CE8; provisional ids): the boxes' markers, the orders, the
## code and the beds.
@export var boxes_rng: StringName = &"cooking_boxes"
@export var orders_rng: StringName = &"cooking_orders"
@export var code_rng: StringName = &"herb_code"
@export var beds_rng: StringName = &"herb_beds"


func new_state() -> TaskState:
	return State.new()


## The host ticks from a patty going on the grill to its turning fried: `fry_seconds` by the one
## rounding rule (Ticks), at least 1.
func fried_ticks() -> int:
	return maxi(1, Ticks.from_seconds(fry_seconds))


## The host ticks from a patty going on the grill to its turning burnt: the fried ticks plus
## `burn_seconds` by the one rounding rule, at least 1, so a patty is always fried first.
func burnt_ticks() -> int:
	return fried_ticks() + maxi(1, Ticks.from_seconds(burn_seconds))


## The fried kind of the raw patty kind `raw` (the same index), or null for any other kind.
func fried_of(raw: ItemKind) -> ItemKind:
	var index := raw_patties.find(raw)
	if index < 0 or index >= fried_patties.size():
		return null
	return fried_patties[index]


## Every ingredient kind, in the lists' order: the buns, the raw and the fried patties, the burnt
## one and the herbs (the 15 that vanish when left lying, CD6 (c)).
func ingredients() -> Array[ItemKind]:
	var found: Array[ItemKind] = []
	found.append_array(buns)
	found.append_array(raw_patties)
	found.append_array(fried_patties)
	if burnt != null:
		found.append(burnt)
	found.append_array(herbs)
	return found


## The kinds a take gives (the buns, the raw patties, the herbs): each capped (CE3).
func given_kinds() -> Array[ItemKind]:
	var found: Array[ItemKind] = []
	found.append_array(buns)
	found.append_array(raw_patties)
	found.append_array(herbs)
	return found


func deal(ctx: MatchContext) -> void:
	var count := maxi(ctx.setting(subtasks_setting), 0)
	if count == 0:
		ctx.state.add_task(self)
		return
	if not _fits(ctx, count):
		return
	var stations := _place_stations(ctx, count)
	var boxes_placed := _place_boxes(ctx)
	# Every item id in use (Items.spawn logged it): no deal comes near that.
	if boxes_placed.size() < boxes.size():
		return
	var task := ctx.state.add_task(self)
	var task_state := task.state as State
	task_state.order_board = stations[0].id
	task_state.herb_board = stations[1].id
	task_state.grill = stations[2].id
	for i in herbs.size():
		task_state.beds.append(stations[3 + i].id)
	var orders := ctx.rng(orders_rng)
	for i in count:
		var order := Order.new()
		order.station = stations[3 + herbs.size() + i].id
		order.bun = buns[orders.randi_range(0, buns.size() - 1)]
		order.raw_patty = raw_patties[orders.randi_range(0, raw_patties.size() - 1)]
		order.herb = herbs[orders.randi_range(0, herbs.size() - 1)]
		task_state.orders.append(order)
	for index: int in RngStreams.shuffled_indices(herbs.size(), ctx.rng(code_rng)):
		task_state.code.append(herbs[index])
	for index: int in RngStreams.shuffled_indices(herbs.size(), ctx.rng(beds_rng)):
		task_state.bed_herbs.append(herbs[index])
	for station: StationState in stations:
		ctx.emit(
			StationPlacedEvent.new(station.id, station.kind.id, station.colour, station.position)
		)
	for item: ItemState in boxes_placed:
		ctx.emit(ItemSpawnedEvent.new(item.id, item.kind.id, item.position))
	for order: Order in task_state.orders:
		var fried := fried_of(order.raw_patty)
		var icon := task_state.code.find(order.herb)
		ctx.emit(OrderPostedEvent.new(order.station, order.bun.id, fried.id, icon))
	ctx.emit(HerbsDealtEvent.new(_ids(task_state.code), _ids(task_state.bed_herbs)))
	for item: ItemState in boxes_placed:
		Items.raise_rested(ctx, item, Items.SPAWN)


func has_tick() -> bool:
	return true


## Why the actor's use of `station` is refused (StationUsable, after AtStation and StationInSight;
## the ADR's §2.3 to §2.5, CE11), from what lies on the station and what the actor holds, never a
## role:
## - the grill, empty: a two-handed hand item `two_handed` (a put is not a take, CD3 (b); the
##   grill's rule has no HandNotTwoHanded, which would refuse the take-off too), no hand item
##   `empty_hand`, anything but a raw patty `wrong_item` (CD7 (a)); occupied, nothing: taking its
##   patty off is a take, which makes its own room (CD3 (b), CD5 (b));
## - a bed: `unavailable` only when its herb is at its cap with none loose (CE3, GiveItem's);
## - a place: `unavailable` once its burger is done, `empty_hand`, or `wrong_item` for a hand item
##   that is none of the buns, the fried patties and the herbs (a knife, a raw or burnt patty, CD8
##   (b)); its rule's HandNotTwoHanded refuses `two_handed` before.
## Any other station of the task, or no task, `unavailable`.
func use_problem(ctx: MatchContext, task: MatchTask, station: StationState) -> StringName:
	if task == null:
		return StationUsable.UNAVAILABLE
	var task_state := task.state as State
	var hand := Items.held_by(ctx.state, ctx.actor)
	if station.id == task_state.grill:
		return _grill_problem(task_state, hand)
	var bed := task_state.beds.find(station.id)
	if bed >= 0:
		return GiveItem.cap_problem(ctx.state, task_state.bed_herbs[bed])
	return _place_problem(_order_at(task_state, station.id), hand)


func use_reasons() -> Array[StringName]:
	return [
		StationUsable.UNAVAILABLE,
		StationUsable.TWO_HANDED,
		StationUsable.EMPTY_HAND,
		StationUsable.WRONG_ITEM,
	]


## The use itself, after use_problem() passed (the ADR's §2.3 to §2.5):
## - the grill, empty: the hand's raw patty is locked on it (Items.lock_at), fried and burnt at
##   now plus fried_ticks() and burnt_ticks(), with GrillLoaded; occupied: its patty, whatever its
##   kind, goes to the actor (Items.give, which makes room: the belt, or the feet; a box carrier's
##   onto the belt), and the grill is empty;
## - a bed: a new item of the bed's herb of the round, spawned at the bed and given to the actor
##   (GiveItem.give_new: the cap, ItemSpawned, Items.give);
## - a place: the hand item goes on. Right (the order's bun, fried patty or herb, its slot still
##   empty): locked there, the slot filled; wrong (anything else the place takes, or a second one
##   for a filled slot): it lies on the ground at the place (Items.lay_on_station, `on_station`),
##   where PickUp takes it back. IngredientPlaced either way, first (CE13); the third right one
##   makes the place done (StationState.done), then Tasks.subtask_done (CE13; the detail: the
##   order's index and the place).
func use_station(ctx: MatchContext, task: MatchTask, station: StationState) -> void:
	if task == null:
		return  # StationUsable refused it.
	var task_state := task.state as State
	if station.id == task_state.grill:
		_use_grill(ctx, task_state, station)
		return
	var bed := task_state.beds.find(station.id)
	if bed >= 0:
		GiveItem.give_new(ctx, task_state.bed_herbs[bed], station.position)
		return
	var index := task_state.orders.find(_order_at(task_state, station.id))
	if index < 0:
		ctx.error("Cooking: station %d is neither its grill, a bed nor a place" % station.id)
		return
	_use_place(ctx, task, index, station)


func use_emits() -> Array[Script]:
	return [
		GrillLoadedEvent,
		IngredientPlacedEvent,
		ItemSpawnedEvent,
		ItemVanishedEvent,
		ItemPlacedEvent,
		ItemPickedUpEvent,
		TaskStateEvent,
		TaskProgressEvent,
	]


## The grill's patty turns fried when its fried tick has come and burnt when its burnt tick has
## (the ADR's §2.4, CE4, CE10): Items.change_kind, ItemChanged to everyone. A burnt one stays as it
## is until someone takes it off. Through TaskTicks, in the phases that list it (Round).
func tick(ctx: MatchContext) -> void:
	for task_id: int in ctx.state.tasks:
		var task := ctx.state.tasks[task_id]
		if task.type != self:
			continue
		var task_state := task.state as State
		if task_state.grill_item < 0:
			continue
		var patty: ItemState = ctx.state.items.get(task_state.grill_item)
		if patty == null:
			ctx.error("Cooking: the grill's patty %d is gone" % task_state.grill_item)
			_empty_grill(task_state)
			continue
		if patty.kind == burnt:
			continue
		if ctx.tick >= task_state.burnt_tick:
			Items.change_kind(ctx, patty, burnt)
		elif ctx.tick >= task_state.fried_tick and raw_patties.has(patty.kind):
			Items.change_kind(ctx, patty, fried_of(patty.kind))


func _use_grill(ctx: MatchContext, task_state: State, station: StationState) -> void:
	if task_state.grill_item >= 0:
		var patty: ItemState = ctx.state.items.get(task_state.grill_item)
		_empty_grill(task_state)
		if patty == null:
			ctx.error("Cooking: the grill's patty is gone")
			return
		Items.give(ctx, ctx.actor, patty)
		return
	var hand := Items.held_by(ctx.state, ctx.actor)
	if hand == null:
		ctx.error("Cooking: player %d put nothing on the grill" % ctx.actor)
		return
	Items.lock_at(ctx, hand, station.position)
	task_state.grill_item = hand.id
	task_state.fried_tick = ctx.tick + fried_ticks()
	task_state.burnt_tick = ctx.tick + burnt_ticks()
	ctx.emit(
		GrillLoadedEvent.new(station.id, hand.id, task_state.fried_tick, task_state.burnt_tick)
	)


func _use_place(ctx: MatchContext, task: MatchTask, index: int, station: StationState) -> void:
	var task_state := task.state as State
	var order := task_state.orders[index]
	var hand := Items.held_by(ctx.state, ctx.actor)
	if hand == null:
		ctx.error("Cooking: player %d put nothing on place %d" % [ctx.actor, station.id])
		return
	var right := true
	if hand.kind == order.bun and order.bun_item < 0:
		order.bun_item = hand.id
	elif hand.kind == fried_of(order.raw_patty) and order.patty_item < 0:
		order.patty_item = hand.id
	elif hand.kind == order.herb and order.herb_item < 0:
		order.herb_item = hand.id
	else:
		right = false
	ctx.emit(IngredientPlacedEvent.new(hand.id, station.id, right))
	if not right:
		Items.lay_on_station(ctx, hand, station.position)
		return
	Items.lock_at(ctx, hand, station.position)
	if order.bun_item < 0 or order.patty_item < 0 or order.herb_item < 0:
		return
	order.done = true
	station.done = true
	Tasks.subtask_done(ctx, task, {"subtask": index, "station": station.id})


## The grill's refusal (use_problem()): none when occupied, the take-off being a take.
func _grill_problem(task_state: State, hand: ItemState) -> StringName:
	if task_state.grill_item >= 0:
		return &""
	if hand == null:
		return StationUsable.EMPTY_HAND
	if hand.kind.is_two_handed():
		return StationUsable.TWO_HANDED
	if not raw_patties.has(hand.kind):
		return StationUsable.WRONG_ITEM
	return &""


## A place's refusal (use_problem()); `order` null: the station is no place of the task.
func _place_problem(order: Order, hand: ItemState) -> StringName:
	if order == null or order.done:
		return StationUsable.UNAVAILABLE
	if hand == null:
		return StationUsable.EMPTY_HAND
	if not _takes(hand.kind):
		return StationUsable.WRONG_ITEM
	return &""


static func _empty_grill(task_state: State) -> void:
	task_state.grill_item = -1
	task_state.fried_tick = -1
	task_state.burnt_tick = -1


## The order on the place `station_id`, or null.
static func _order_at(task_state: State, station_id: int) -> Order:
	for order: Order in task_state.orders:
		if order.station == station_id:
			return order
	return null


## Whether a place takes `kind` at all (right or wrong): a bun, a fried patty or a herb.
func _takes(kind: ItemKind) -> bool:
	return buns.has(kind) or fried_patties.has(kind) or herbs.has(kind)


## Exactly one marker each for the boards and the grill, and exactly as many `herb_bed` markers
## as herbs (exact counts, as the Generator's GE10: a second board or grill scene, or a bed no herb
## grows on, would stand unused), at least N `place` markers (N the setting; an unused place hides
## its plate, CE15) and at least one marker per box kind's tag (the box drawn among them). Asked
## whatever the setting, as the Generator's: the level's scenes stand there either way. DealTasks
## asks only a map Cooking plays on (G8). No colours.
func add_demands(settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	for kind: StationKind in [order_board, herb_board, grill, herb_bed, place]:
		if kind == null:
			return  # The check refuses such a mode.
	into.add_markers(order_board.spawn_tag, 1, true)
	into.add_markers(herb_board.spawn_tag, 1, true)
	into.add_markers(grill.spawn_tag, 1, true)
	into.add_markers(herb_bed.spawn_tag, herbs.size(), true)
	into.add_markers(place.spawn_tag, maxi(settings.get(subtasks_setting, 0) as int, 0))
	for box: ItemKind in boxes:
		if box != null and not box.spawn_tag.is_empty():
			into.add_markers(box.spawn_tag, 1)


func emits() -> Array[Script]:
	return [
		StationPlacedEvent,
		ItemSpawnedEvent,
		OrderPostedEvent,
		HerbsDealtEvent,
		GrillLoadedEvent,
		IngredientPlacedEvent,
		ItemChangedEvent,
		ItemVanishedEvent,
		TaskStateEvent,
		TaskProgressEvent,
	]


## CE14: every station kind set (the boards display kinds, the others with an Interact rule ending
## in UseStation; their spawn tags distinct across the mode is ModeCheck's, ZE3); the lists; every
## kind distinct, listed in the mode, one-handed but the boxes, which are two-handed and placed on
## tags of their own; each box giving one bun or raw patty kind, and each of those given by a box;
## at most MAX_HERBS herbs; the seconds within bounds; the subtasks setting from
## at least 0 (ModeCheck checks it names a declared whole-number setting); non-empty RNG purposes;
## the cap on every given kind (CE3) and `vanish_seconds` on every ingredient (CD6 (c)).
func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	_check_station_kinds(found)
	_check_lists(found)
	if mode != null:
		_check_listed(mode, found)
		_check_setting(mode, found)
		_check_caps(mode, found)
	_check_boxes(found)
	if herbs.size() > MAX_HERBS:
		found.append("Cooking %s has %d herbs, more than %d" % [id, herbs.size(), MAX_HERBS])
	append_found(
		found,
		[
			out_of_bounds("Cooking %s fry_seconds" % id, fry_seconds, MIN_SECONDS, MAX_SECONDS),
			out_of_bounds("Cooking %s burn_seconds" % id, burn_seconds, MIN_SECONDS, MAX_SECONDS),
		]
	)
	if subtasks_setting.is_empty():
		found.append("Cooking %s has no subtasks_setting" % id)
	if boxes_rng.is_empty() or orders_rng.is_empty() or code_rng.is_empty() or beds_rng.is_empty():
		found.append("Cooking %s has an empty RNG purpose" % id)
	for kind: ItemKind in ingredients():
		if kind != null and not kind.vanishes():
			(
				found
				. append(
					(
						"Cooking %s: ingredient kind %s sets no vanish_seconds: left lying, it would stay"
						% [id, kind.id]
					)
				)
			)
	return found


func _check_station_kinds(found: PackedStringArray) -> void:
	var named := {
		"order_board": order_board,
		"herb_board": herb_board,
		"grill": grill,
		"herb_bed": herb_bed,
		"place": place,
	}
	for property: String in named:
		var kind: StationKind = named[property]
		if kind == null:
			found.append("Cooking %s has no %s station kind" % [id, property])
		elif property.ends_with("_board"):
			if not kind.display:
				found.append("Cooking %s: station kind %s is not a display kind" % [id, kind.id])
		elif kind.display:
			found.append(
				"Cooking %s: station kind %s is a display kind, never used" % [id, kind.id]
			)
		elif not _ends_in_use(kind):
			found.append(
				(
					"Cooking %s: station kind %s has no Interact rule ending in UseStation"
					% [id, kind.id]
				)
			)
		elif property == "herb_bed" and not _has_cooldown(kind):
			found.append(
				"Cooking %s: station kind %s has no Interact rule with a Cooldown" % [id, kind.id]
			)


func _check_lists(found: PackedStringArray) -> void:
	var lists := {"buns": buns, "raw_patties": raw_patties, "herbs": herbs, "boxes": boxes}
	for list_name: String in lists:
		if (lists[list_name] as Array).is_empty():
			found.append("Cooking %s has no %s" % [id, list_name])
	if fried_patties.size() != raw_patties.size():
		found.append(
			(
				"Cooking %s has %d fried_patties for %d raw_patties"
				% [id, fried_patties.size(), raw_patties.size()]
			)
		)
	if burnt == null:
		found.append("Cooking %s has no burnt item kind" % id)
	var seen: Array[ItemKind] = []
	var every: Array[ItemKind] = ingredients()
	every.append_array(boxes)
	for kind: ItemKind in every:
		if kind == null:
			found.append("Cooking %s names an empty item kind" % id)
			continue
		if seen.has(kind):
			found.append("Cooking %s names item kind %s twice" % [id, kind.id])
		seen.append(kind)
		if boxes.has(kind):
			if not kind.is_two_handed():
				found.append("Cooking %s: box kind %s is not two-handed" % [id, kind.id])
		elif kind.is_two_handed():
			found.append("Cooking %s: ingredient kind %s is two-handed" % [id, kind.id])


## A kind it names that the mode does not list is refused (CE18): the client resolves kind ids,
## WireBudget sizes them and ModeCheck walks their rules through the mode's `item_kinds`.
func _check_listed(mode: GameMode, found: PackedStringArray) -> void:
	var every: Array[ItemKind] = ingredients()
	every.append_array(boxes)
	for kind: ItemKind in every:
		if kind != null and mode.find_item_kind(kind.id) != kind:
			found.append(
				"Cooking %s names item kind %s, which the mode does not declare" % [id, kind.id]
			)


func _check_setting(mode: GameMode, found: PackedStringArray) -> void:
	if subtasks_setting.is_empty():
		return
	var spec := mode.find_setting(subtasks_setting)
	if spec != null and spec.is_number() and spec.min_value < 0:
		found.append("Cooking %s: setting %s goes below 0" % [id, subtasks_setting])


## Every given kind capped at least twice the mode's most players (a hand and a belt each) plus
## the most burgers (one locked per place) plus 1 (the grill's patty), so a take at the cap always
## finds a loose one (CE3, CE14).
func _check_caps(mode: GameMode, found: PackedStringArray) -> void:
	var most_burgers := 0
	var spec := mode.find_setting(subtasks_setting) if not subtasks_setting.is_empty() else null
	if spec != null and spec.is_number():
		most_burgers = maxi(spec.max_value, 0)
	var least := 2 * mode.max_players + most_burgers + 1
	for kind: ItemKind in given_kinds():
		if kind != null and kind.max_items < least:
			(
				found
				. append(
					(
						"Cooking %s: given kind %s has max_items %d, below %d (twice %d players, %d burgers, 1)"
						% [id, kind.id, kind.max_items, least, mode.max_players, most_burgers]
					)
				)
			)


## Each box on a spawn tag of its own (none of another box or of the station kinds), never
## vanishing, its target_actions giving one bun or raw patty kind; each bun and raw patty kind
## given by a box, so every order can be cooked.
func _check_boxes(found: PackedStringArray) -> void:
	var tags: Array[StringName] = []
	for kind: StationKind in [order_board, herb_board, grill, herb_bed, place]:
		if kind != null:
			tags.append(kind.spawn_tag)
	var sources: Array[ItemKind] = []
	sources.append_array(buns)
	sources.append_array(raw_patties)
	var given: Array[ItemKind] = []
	for box: ItemKind in boxes:
		if box == null:
			continue
		if box.spawn_tag.is_empty():
			found.append("Cooking %s: box kind %s has no spawn_tag to place it on" % [id, box.id])
		elif tags.has(box.spawn_tag):
			found.append(
				"Cooking %s: box kind %s shares the spawn tag %s" % [id, box.id, box.spawn_tag]
			)
		else:
			tags.append(box.spawn_tag)
		if box.vanishes():
			found.append("Cooking %s: box kind %s must not vanish" % [id, box.id])
		var gives := _gives(box)
		if gives.size() != 1 or not sources.has(gives[0]):
			found.append(
				(
					"Cooking %s: box kind %s does not give exactly one bun or raw patty kind"
					% [id, box.id]
				)
			)
		else:
			given.append(gives[0])
	for kind: ItemKind in sources:
		if kind != null and not given.has(kind):
			found.append("Cooking %s: no box gives item kind %s" % [id, kind.id])


## The kinds the GiveItem effects of `box`'s target_actions give.
static func _gives(box: ItemKind) -> Array[ItemKind]:
	var found: Array[ItemKind] = []
	for rule: Rule in box.target_actions:
		if rule == null:
			continue
		for effect: RuleEffect in rule.effects:
			if effect is GiveItem:
				found.append((effect as GiveItem).kind)
	return found


## Whether the Interact rule of `kind` that ends in UseStation holds a Cooldown (CE17: a bed's
## `too_soon`, the flood guard of a take): the cooldown and the use are one rule.
static func _has_cooldown(kind: StationKind) -> bool:
	for rule: Rule in kind.actions:
		if rule == null or rule.trigger != Intents.INTERACT or rule.effects.is_empty():
			continue
		if not rule.effects[-1] is UseStation:
			continue
		for condition: Condition in rule.conditions:
			if condition is Cooldown and not condition.negate:
				return true
	return false


## Whether `kind` has an Interact rule whose last effect is UseStation.
static func _ends_in_use(kind: StationKind) -> bool:
	for rule: Rule in kind.actions:
		if rule == null or rule.trigger != Intents.INTERACT or rule.effects.is_empty():
			continue
		if rule.effects[-1] is UseStation:
			return true
	return false


static func _ids(kinds: Array[ItemKind]) -> PackedStringArray:
	var found := PackedStringArray()
	for kind: ItemKind in kinds:
		found.append(String(kind.id))
	return found


## Whether the level being entered has the markers for `count` burgers: a board, the herb board,
## the grill, a bed per herb, `count` places and a free marker per box. The lobby's fit check
## (§9.4) keeps a match from getting here without them.
func _fits(ctx: MatchContext, count: int) -> bool:
	if ctx.layout == null:
		ctx.error("Cooking: no layout for the level being entered")
		return false
	var short := PackedStringArray()
	var needs := {
		order_board.spawn_tag: 1,
		herb_board.spawn_tag: 1,
		grill.spawn_tag: 1,
		herb_bed.spawn_tag: herbs.size(),
		place.spawn_tag: count,
	}
	for tag: StringName in needs:
		var have := ctx.layout.count(tag)
		if have < (needs[tag] as int):
			short.append("%d %s markers, the map has %d" % [needs[tag], tag, have])
	for box: ItemKind in boxes:
		if Items.free_markers(ctx, box.spawn_tag).is_empty():
			short.append("a free %s marker, the map has none" % box.spawn_tag)
	if short.is_empty():
		return true
	ctx.error("Cooking: %d burgers need %s" % [count, "; ".join(short)])
	return false


## The stations in id order: the order board, the herb board, the grill, a bed per herb, then
## `count` places, each on its tag's markers in level order.
func _place_stations(ctx: MatchContext, count: int) -> Array[StationState]:
	var placed: Array[StationState] = []
	for kind: StationKind in [order_board, herb_board, grill]:
		placed.append(
			ctx.state.add_station(kind, ctx.layout.positions(kind.spawn_tag)[0], Color.WHITE)
		)
	var beds := ctx.layout.positions(herb_bed.spawn_tag)
	for i in herbs.size():
		placed.append(ctx.state.add_station(herb_bed, beds[i], Color.WHITE))
	var places := ctx.layout.positions(place.spawn_tag)
	for i in count:
		placed.append(ctx.state.add_station(place, places[i], Color.WHITE))
	return placed


## One box per box kind, in the boxes' order, on a random free marker of its tag; stops short when
## every item id is in use (Items.spawn logs it).
func _place_boxes(ctx: MatchContext) -> Array[ItemState]:
	var rng := ctx.rng(boxes_rng)
	var placed: Array[ItemState] = []
	for box: ItemKind in boxes:
		var spots := Items.free_markers(ctx, box.spawn_tag)
		var item := Items.spawn(ctx, box, spots[rng.randi_range(0, spots.size() - 1)])
		if item == null:
			break
		placed.append(item)
	return placed
