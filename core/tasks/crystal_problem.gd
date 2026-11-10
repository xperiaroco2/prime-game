class_name CrystalProblem
extends ProblemKind
## The ship engine's burnt crystal (ARCHITECTURE §9.3, §9.5.27; GDD §8 "A spent cartridge" and
## "The crystal never leaves the ship"): its sites are the hall's four cartridge sockets, its one
## fixture the chargers, one in each lens room. A socket always holds its crystal (no spare ones,
## GDD §8), spent while a problem holds the socket; the crystal is an item only while it is out.
##
## - The pull: a use of a socket with a problem whose crystal is in it spawns the `spent` crystal
##   there (ItemSpawned), CrystalChanged names it, and it goes into the user's hands
##   (Items.hand_out: the crystal is two-handed, GDD §5; ItemPickedUp).
## - The charger (its phases EMPTY, LOADED, CHARGING, WAITING):
##   empty, a use by a player holding a spent crystal of an open problem puts it in its one slot
##   (locked there, LOADED); loaded, a use presses it (CHARGING, for `charge_seconds`); at the end
##   the crystal becomes `charged` (ItemChanged) and waits (WAITING) until a use takes it out
##   (Items.hand_out, EMPTY). One crystal a charger; a charging one takes no use.
## - The fit: a use of its own socket by a player holding its charged crystal: the item vanishes
##   (ItemVanished), CrystalChanged says the socket holds it again, fixed.
## - Never off the ship: each tick a loose crystal (carried, or lying) outside the engine's aboard
##   box slips and rolls back to where it last was aboard, on the floor there (ItemPlaced, cause
##   `slipped`; GDD §8, as the garage's tools drop at its door). A flying one is judged where it
##   lands. A crystal lying on that spot already stays: a socket or charger a level put outside
##   the box would else slip it again every tick.
##   A crystal slipping from a carrier's hands zaps the carrier instead (GDD §8 "The ship is in an
##   emergency mode", #1585): the same slip with the cause `zapped` (the world's zap sound), then
##   ShipZapped to the carrier and `zap_damage` health off, never below ZAP_HEALTH_FLOOR (no
##   knockdown). Only a crystal that really crossed: its last aboard spot is in the box (a level's
##   station outside it just slips). One thrown or put down over the edge slips as before, no zap.
## - The blast (cleared): a crystal out vanishes wherever it is, a charger holding it empties, and
##   the socket holds its crystal again. CrystalChanged follows each change of the crystal.
## Refuses `unavailable` (a socket without a problem, a charging charger), `empty_hand` and
## `wrong_item` (anything but the crystal the station takes now).

## A charger's phases (CrystalChanged's `phase`).
const EMPTY := 0
const LOADED := 1
const CHARGING := 2
const WAITING := 3
## ItemPlaced's cause for a crystal that slipped back aboard.
const SLIPPED := &"slipped"
## ItemPlaced's cause for a crystal the ship knocked out of its carrier's hands (#1585).
const ZAPPED := &"zapped"
## The health a zap leaves at the least, whole points: it never kills or knocks down (#1585).
const ZAP_HEALTH_FLOOR := 1
## The bounds of `charge_seconds`.
const MIN_CHARGE_SECONDS := 0.05
const MAX_CHARGE_SECONDS := 600.0
## The bounds of `zap_damage` (0: none), `zap_flash_seconds` and `zap_notice_seconds`.
const MAX_ZAP_DAMAGE := 100
const MIN_ZAP_FLASH_SECONDS := 0.05
const MAX_ZAP_FLASH_SECONDS := 5.0
const MIN_ZAP_NOTICE_SECONDS := 0.5
const MAX_ZAP_NOTICE_SECONDS := 30.0

## The crystal's kind while it is spent (GDD §8: plain grey).
@export var spent: ItemKind
## Its kind once charged.
@export var charged: ItemKind
## How long the charger charges (GDD §8's placeholder: 10 s), converted once to host ticks.
@export var charge_seconds := 0.0
## The zap's damage, whole points (GDD §8, #1585: 1, "for fun"); it stops at ZAP_HEALTH_FLOOR.
@export var zap_damage := 0
## How long the carrier's blue flash and camera shake last (#1585: 0.4, a placeholder until a
## playtest, "not a decision"). The client's copy of the mode is where they are read.
@export var zap_flash_seconds := 0.0
## How long the carrier's HUD shows the notice (#1585: 3, a placeholder until a playtest).
@export var zap_notice_seconds := 0.0


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
		return _socket_refusal(hand, problem)
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


## Why a socket takes no use from a player holding `hand` (null: an empty hand), or "".
func _socket_refusal(hand: ItemState, problem: EngineProblem) -> StringName:
	if problem == null:
		return StationUsable.UNAVAILABLE
	var data := problem.data as Data
	if data.item < 0:
		return &""
	if hand == null:
		return StationUsable.EMPTY_HAND
	return &"" if hand.id == data.item and hand.kind == charged else StationUsable.WRONG_ITEM


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
	_announce(ctx, mine)


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
		_announce(ctx, problem)
		ShipEngine.fix(ctx, task, problem)
		return
	var made := Items.spawn(ctx, spent, station.position)
	if made == null:
		return  # Every item id is in use: logged; the crystal stays in.
	data.item = made.id
	data.last_in = station.position
	ctx.emit(ItemSpawnedEvent.new(made.id, spent.id, station.position))
	_announce(ctx, problem)
	Items.hand_out(ctx, ctx.actor, made)


## A use of the charger holding `held`'s crystal: the press, or the take.
func _use_loaded(ctx: MatchContext, station: StationState, held: EngineProblem) -> void:
	var data := held.data as Data
	if data.phase == LOADED:
		data.phase = CHARGING
		data.done_tick = ctx.tick + charge_ticks()
		_announce(ctx, held)
		return
	if data.phase != WAITING:
		return  # use_problem refused it.
	data.charger = -1
	data.phase = EMPTY
	data.done_tick = -1
	data.last_in = station.position
	_announce(ctx, held)
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
			_announce(ctx, problem)
		return
	var where := crystal.position
	var carrier := -1
	if crystal.is_carried():
		carrier = crystal.holder
		where = ctx.state.player(carrier).position
	elif crystal.where != ItemState.Where.GROUND:
		return  # In flight: judged where it lands.
	var task_state := task.state as ShipEngine.State
	if ShipEngine.in_box(where, task_state.aboard_low, task_state.aboard_high):
		data.last_in = where
		return
	var rest := ctx.world.floor_below(Items.lifted(data.last_in))
	var spot := data.last_in if rest == WorldQuery.NO_FLOOR else rest
	if crystal.where == ItemState.Where.GROUND and crystal.position == spot:
		return  # Slipped already: its last aboard spot is out of the box (a level's station).
	var aboard_once := ShipEngine.in_box(
		data.last_in, task_state.aboard_low, task_state.aboard_high
	)
	var zapped := carrier >= 0 and aboard_once
	Items.place(ctx, crystal, spot, ZAPPED if zapped else SLIPPED)
	if zapped:
		_zap(ctx, carrier)


## The ship zaps `carrier`, whose hands just lost the crystal: ShipZapped, then `zap_damage` off
## its health, what is left of it at least ZAP_HEALTH_FLOOR: a Damaged only if any comes off.
func _zap(ctx: MatchContext, carrier: int) -> void:
	ctx.emit(ShipZappedEvent.new(carrier))
	var player := ctx.state.player(carrier)
	if not player.is_alive():
		return
	var spare := player.health - Ticks.thousandths(ZAP_HEALTH_FLOOR)
	var taken := mini(Ticks.thousandths(zap_damage), spare)
	if taken > 0:
		LifeRules.damage(ctx, carrier, taken)


## The crystal of `problem` is back in its socket: out of any charger, its item gone.
func _back_in(ctx: MatchContext, problem: EngineProblem) -> void:
	var data := problem.data as Data
	var crystal: ItemState = ctx.state.items.get(data.item)
	if crystal != null:
		Items.vanish(ctx, crystal)
	data.item = -1
	data.charger = -1
	data.phase = EMPTY
	data.done_tick = -1
	_announce(ctx, problem)


## CrystalChanged: `problem`'s crystal as it is now.
func _announce(ctx: MatchContext, problem: EngineProblem) -> void:
	var data := problem.data as Data
	var end := data.done_tick if data.phase == CHARGING else -1
	ctx.emit(CrystalChangedEvent.new(problem.stations[0], data.charger, data.phase, data.item, end))


func cleared(ctx: MatchContext, _task: MatchTask, problem: EngineProblem) -> void:
	if (problem.data as Data).item >= 0:
		_back_in(ctx, problem)


func use_emits() -> Array[Script]:
	return [
		ItemSpawnedEvent,
		CrystalChangedEvent,
		ItemPickedUpEvent,
		ItemPlacedEvent,
		ItemVanishedEvent,
	]


func emits() -> Array[Script]:
	return [
		CrystalChangedEvent,
		ItemChangedEvent,
		ItemPlacedEvent,
		ItemVanishedEvent,
		ShipZappedEvent,
		DamagedEvent,
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
			),
			out_of_bounds("problem kind %s zap_damage" % id, zap_damage, 0, MAX_ZAP_DAMAGE),
			out_of_bounds(
				"problem kind %s zap_flash_seconds" % id,
				zap_flash_seconds,
				MIN_ZAP_FLASH_SECONDS,
				MAX_ZAP_FLASH_SECONDS
			),
			out_of_bounds(
				"problem kind %s zap_notice_seconds" % id,
				zap_notice_seconds,
				MIN_ZAP_NOTICE_SECONDS,
				MAX_ZAP_NOTICE_SECONDS
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
