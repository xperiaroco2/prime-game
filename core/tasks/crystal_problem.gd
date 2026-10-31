class_name CrystalProblem
extends ProblemKind
## The ship engine's burnt crystal (ARCHITECTURE §9.3, §9.5.27; GDD §8 "A spent cartridge" and
## "The crystal never leaves the ship"): its sites are the hall's four cartridge sockets, its one
## fixture the chargers, one in each lens room. A socket always holds its crystal (no spare ones,
## GDD §8), spent while a problem holds the socket; the crystal is an item only while it is out.
##
## - The pull: a use of a socket with a problem whose crystal is in it spawns the `spent` crystal
##   there (ItemSpawned), CrystalSocketChanged names it, and it goes into the user's hands
##   (Items.hand_out: the crystal is two-handed, GDD §5; ItemPickedUp).
## - The charger (its phases EMPTY, LOADED, CHARGING, WAITING; ChargerChanged on each change):
##   empty, a use by a player holding a spent crystal of an open problem puts it in its one slot
##   (locked there, LOADED); loaded, a use presses it (CHARGING, for `charge_seconds`); at the end
##   the crystal becomes `charged` (ItemChanged) and waits (WAITING) until a use takes it out
##   (Items.hand_out, EMPTY). One crystal a charger; a charging one takes no use.
## - The fit: a use of its own socket by a player holding its charged crystal: the item vanishes
##   (ItemVanished), CrystalSocketChanged says the socket holds it again, fixed.
## - Never off the ship: each tick a loose crystal (carried, or lying) outside the engine's aboard
##   box slips and rolls back to where it last was aboard, on the floor there (ItemPlaced, cause
##   `slipped`; GDD §8, as the garage's tools drop at its door). A flying one is judged where it
##   lands.
## - The blast (cleared): a crystal out vanishes wherever it is, a charger holding it empties, and
##   the socket holds its crystal again.
## Refuses `unavailable` (a socket without a problem, a charging charger), `empty_hand` and
## `wrong_item` (anything but the crystal the station takes now).

## A charger's phases (ChargerChanged's `phase`).
const EMPTY := 0
const LOADED := 1
const CHARGING := 2
const WAITING := 3
## ItemPlaced's cause for a crystal that slipped back aboard.
const SLIPPED := &"slipped"
## The bounds of `charge_seconds`.
const MIN_CHARGE_SECONDS := 0.05
const MAX_CHARGE_SECONDS := 600.0

## The crystal's kind while it is spent (GDD §8: plain grey).
@export var spent: ItemKind
## Its kind once charged.
@export var charged: ItemKind
## How long the charger charges (GDD §8's placeholder: 10 s), converted once to host ticks.
@export var charge_seconds := 0.0


## A crystal problem's own state (EngineProblem.data).
class Data:
	extends RefCounted
	## The crystal's item while it is out of its socket, else -1.
	var item := -1
	## The charger holding it, else -1.
	var charger := -1
	## That charger's phase (EMPTY while none holds it).
	var phase := EMPTY
	## The host tick the charge ends on while CHARGING.
	var done_tick := -1
	## Where the crystal last was aboard (the slip's spot).
	var last_in := Vector3.ZERO


func charge_ticks() -> int:
	return maxi(1, Ticks.from_seconds(charge_seconds))


func opened(_ctx: MatchContext, _task: MatchTask, problem: EngineProblem) -> void:
	problem.data = Data.new()


## The open problem of this kind whose crystal the charger `station_id` holds, or null.
func loaded_at(task: MatchTask, station_id: int) -> EngineProblem:
	for problem: EngineProblem in (task.state as ShipEngine.State).problems:
		if problem.kind == self and (problem.data as Data).charger == station_id:
			return problem
	return null


## The open problem of this kind whose crystal is `item`, or null.
func crystal_of(task: MatchTask, item: ItemState) -> EngineProblem:
	if item == null:
		return null
	for problem: EngineProblem in (task.state as ShipEngine.State).problems:
		if problem.kind == self and (problem.data as Data).item == item.id:
			return problem
	return null


func use_problem(
	ctx: MatchContext, task: MatchTask, station: StationState, problem: EngineProblem
) -> StringName:
	var hand := Items.held_by(ctx.state, ctx.actor)
	if station.kind == site:
		if problem == null:
			return StationUsable.UNAVAILABLE
		var data := problem.data as Data
		if data.item < 0:
			return &""
		if hand == null:
			return StationUsable.EMPTY_HAND
		return &"" if hand.id == data.item and hand.kind == charged else StationUsable.WRONG_ITEM
	var held := loaded_at(task, station.id)
	if held != null:
		var phase := (held.data as Data).phase
		return StationUsable.UNAVAILABLE if phase == CHARGING else &""
	if hand == null:
		return StationUsable.EMPTY_HAND
	var mine := crystal_of(task, hand)
	if mine == null or hand.kind != spent or (mine.data as Data).charger >= 0:
		return StationUsable.WRONG_ITEM
	return &""


func use_reasons() -> Array[StringName]:
	return [StationUsable.UNAVAILABLE, StationUsable.EMPTY_HAND, StationUsable.WRONG_ITEM]


func use_station(
	ctx: MatchContext, task: MatchTask, station: StationState, problem: EngineProblem
) -> void:
	if station.kind == site:
		if problem != null:
			_use_socket(ctx, task, station, problem)
		return
	var held := loaded_at(task, station.id)
	if held != null:
		_use_loaded(ctx, station, held)
		return
	var mine := crystal_of(task, Items.held_by(ctx.state, ctx.actor))
	if mine == null:
		return  # use_problem refused it.
	var data := mine.data as Data
	Items.lock_at(ctx, ctx.state.items[data.item], station.position)
	data.charger = station.id
	data.phase = LOADED
	ctx.emit(ChargerChangedEvent.new(station.id, LOADED, data.item, 0))


## The pull, or the fit of the charged crystal.
func _use_socket(
	ctx: MatchContext, task: MatchTask, station: StationState, problem: EngineProblem
) -> void:
	var data := problem.data as Data
	if data.item >= 0:
		var crystal: ItemState = ctx.state.items.get(data.item)
		if crystal != null:
			Items.vanish(ctx, crystal)
		data.item = -1
		ctx.emit(CrystalSocketChangedEvent.new(station.id, -1))
		ShipEngine.fix(ctx, task, problem)
		return
	var made := Items.spawn(ctx, spent, station.position)
	if made == null:
		return  # Every item id is in use: logged; the crystal stays in.
	data.item = made.id
	data.last_in = station.position
	ctx.emit(ItemSpawnedEvent.new(made.id, spent.id, station.position))
	ctx.emit(CrystalSocketChangedEvent.new(station.id, made.id))
	Items.hand_out(ctx, ctx.actor, made)


## A use of the charger holding `held`'s crystal: the press, or the take.
func _use_loaded(ctx: MatchContext, station: StationState, held: EngineProblem) -> void:
	var data := held.data as Data
	if data.phase == LOADED:
		data.phase = CHARGING
		data.done_tick = ctx.tick + charge_ticks()
		ctx.emit(ChargerChangedEvent.new(station.id, CHARGING, data.item, data.done_tick))
		return
	if data.phase != WAITING:
		return  # use_problem refused it.
	data.charger = -1
	data.phase = EMPTY
	data.done_tick = -1
	data.last_in = station.position
	ctx.emit(ChargerChangedEvent.new(station.id, EMPTY, -1, 0))
	Items.hand_out(ctx, ctx.actor, ctx.state.items[data.item])


func tick_problem(ctx: MatchContext, task: MatchTask, problem: EngineProblem) -> void:
	var data := problem.data as Data
	if data.item < 0:
		return
	var crystal: ItemState = ctx.state.items.get(data.item)
	if crystal == null:
		ctx.error("CrystalProblem: problem %d lost its crystal %d" % [problem.id, data.item])
		_back_in(ctx, problem)
		return
	if data.charger >= 0:
		if data.phase == CHARGING and ctx.tick >= data.done_tick:
			Items.change_kind(ctx, crystal, charged)
			data.phase = WAITING
			data.done_tick = -1
			ctx.emit(ChargerChangedEvent.new(data.charger, WAITING, data.item, 0))
		return
	var where := crystal.position
	if crystal.is_carried():
		where = ctx.state.player(crystal.holder).position
	elif crystal.where != ItemState.Where.GROUND:
		return  # In flight: judged where it lands.
	var task_state := task.state as ShipEngine.State
	if ShipEngine.in_box(where, task_state.aboard_low, task_state.aboard_high):
		data.last_in = where
		return
	var rest := ctx.world.floor_below(Items.lifted(data.last_in))
	Items.place(ctx, crystal, data.last_in if rest == WorldQuery.NO_FLOOR else rest, SLIPPED)


## The crystal of `problem` is back in its socket: out of any charger, its item gone.
func _back_in(ctx: MatchContext, problem: EngineProblem) -> void:
	var data := problem.data as Data
	if data.charger >= 0:
		ctx.emit(ChargerChangedEvent.new(data.charger, EMPTY, -1, 0))
	var crystal: ItemState = ctx.state.items.get(data.item)
	if crystal != null:
		Items.vanish(ctx, crystal)
	data.item = -1
	data.charger = -1
	data.phase = EMPTY
	ctx.emit(CrystalSocketChangedEvent.new(problem.stations[0], -1))


func cleared(ctx: MatchContext, _task: MatchTask, problem: EngineProblem) -> void:
	if (problem.data as Data).item >= 0:
		_back_in(ctx, problem)


func use_emits() -> Array[Script]:
	return [
		ItemSpawnedEvent,
		CrystalSocketChangedEvent,
		ItemPickedUpEvent,
		ItemPlacedEvent,
		ItemVanishedEvent,
		ChargerChangedEvent,
	]


func emits() -> Array[Script]:
	return [
		ChargerChangedEvent,
		ItemChangedEvent,
		ItemPlacedEvent,
		ItemVanishedEvent,
		CrystalSocketChangedEvent,
	]


## ProblemKind's check; one fixture, the chargers; the two crystal kinds, distinct, the mode's own,
## never vanishing; a two-handed crystal's socket and charger rules without HandNotTwoHanded (it
## would refuse the crystal's own use); `charge_seconds` within bounds.
func check(mode: GameMode) -> PackedStringArray:
	var found := super(mode)
	if fixtures.size() != 1:
		found.append("problem kind %s needs one fixture, the chargers" % id)
	if spent == null or charged == null or spent == charged:
		found.append("problem kind %s needs two distinct crystal kinds" % id)
	else:
		for kind: ItemKind in [spent, charged]:
			if mode.find_item_kind(kind.id) != kind:
				found.append("problem kind %s: item kind %s is not the mode's" % [id, kind.id])
			if kind.vanish_seconds != 0:
				found.append("problem kind %s: crystal %s vanishes" % [id, kind.id])
		if spent.is_two_handed() or charged.is_two_handed():
			for station_kind: StationKind in station_kinds():
				if _refuses_two_hands(station_kind):
					found.append(
						(
							"problem kind %s: station kind %s refuses the two-handed crystal"
							% [id, station_kind.id]
						)
					)
	append_found(
		found,
		[
			out_of_bounds(
				"problem kind %s charge_seconds" % id,
				charge_seconds,
				MIN_CHARGE_SECONDS,
				MAX_CHARGE_SECONDS
			)
		]
	)
	return found


static func _refuses_two_hands(station_kind: StationKind) -> bool:
	for rule: Rule in station_kind.actions:
		if rule == null:
			continue
		for condition: Condition in rule.conditions:
			if condition is HandNotTwoHanded:
				return true
	return false
