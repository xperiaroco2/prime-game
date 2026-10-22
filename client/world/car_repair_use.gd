class_name CarRepairUse
extends RefCounted
## What E offers at the car repair's stations and how high its car stands (#811, the car repair
## ADR's §8 R7, ARCHITECTURE §4.7.57), pure: from the own ClientModel and the client's own copy of
## the mode, never `core/` state. It mirrors the host's CarRepair.use_problem() on what the client
## knows and leaves the rest to the host (§7.1); it only decides what to offer:
## - the lift panel: the task not done and the car not up or going up (`up` from LiftChanged: then
##   someone holds, the host's `busy`; nothing names who);
## - the car: the task not done, the car fully up at the estimated host tick, the own hand holding
##   the part PartNeeded names now (the host's `empty_hand`, `wrong_item`), and nobody fitting
##   (FitChanged's fitter 0, the host's `busy`); no estimated tick (a client that draws nothing):
##   never;
## - a bin: always (its Cooldown is the host's `too_soon` to judge);
## - the picture: never (a display kind; StationUse already stops it).
## Nothing at the panel reads the car's fitter, fit tick or fitted count (RE16, RD14 (a)).

enum Role { NONE, CAR, PANEL, BIN, PICTURE }

## How long the client draws the car's drop from fully up to the floor: a look, not a decision (the
## host's world has no car, RE8; the drop's kill is the host's at the stop's tick).
const DROP_SECONDS := 0.25


## Every CarRepair of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[CarRepair]:
	return CarRepairClient.types_of(mode)


## The CarRepair of `mode` one of whose station kinds is `kind_id`, or null.
static func type_of(mode: GameMode, kind_id: StringName) -> CarRepair:
	for type: CarRepair in types_of(mode):
		if role_of(type, kind_id) != Role.NONE:
			return type
	return null


## Which of `type`'s station kinds `kind_id` is; NONE for none.
static func role_of(type: CarRepair, kind_id: StringName) -> Role:
	if type == null or kind_id == &"":
		return Role.NONE
	if type.car != null and type.car.id == kind_id:
		return Role.CAR
	if type.lift_panel != null and type.lift_panel.id == kind_id:
		return Role.PANEL
	if type.picture != null and type.picture.id == kind_id:
		return Role.PICTURE
	for bin: StationKind in type.bins:
		if bin != null and bin.id == kind_id:
			return Role.BIN
	return Role.NONE


## The placed stations of `type`'s kind of role `role` in `model`, in ascending id.
static func stations_of(model: ClientModel, type: CarRepair, role: Role) -> Array[int]:
	var found: Array[int] = []
	if model == null or type == null:
		return found
	for id: int in model.stations:
		if role_of(type, model.stations[id].kind) == role:
			found.append(id)
	found.sort()
	return found


## The first placed station of `type`'s role `role` (the deal places one car, panel and picture),
## or null.
static func station_of(model: ClientModel, type: CarRepair, role: Role) -> ClientModel.Station:
	var ids := stations_of(model, type, role)
	return model.stations[ids[0]] if not ids.is_empty() else null


## The part kind id the car needs now (PartNeeded on the picture), empty for none.
static func needed_part(model: ClientModel, type: CarRepair) -> StringName:
	var picture := station_of(model, type, Role.PICTURE)
	return picture.part if picture != null else &""


## Whether `type`'s task is done, by its public TaskState row (every part fitted); no row: not
## done.
static func is_done(model: ClientModel, type: CarRepair) -> bool:
	if model == null or type == null:
		return false
	for task: ClientModel.Task in model.tasks.values():
		if task.type == type.id:
			return task.done >= task.total
	return false


## How far up the car of `panel` stands at host tick `now` (a float: the frames between ticks),
## 0 lowered to 1 fully up: rising over `rise_ticks` from the hold's start (`rise_tick`); after a
## stop, falling from the height it reached at the stop (`lift_tick`) to the floor over
## `drop_ticks`. Never raised: 0.
static func lift_fraction(
	panel: ClientModel.Station, now: float, rise_ticks: int, drop_ticks: int
) -> float:
	if panel == null or panel.rise_tick < 0:
		return 0.0
	if panel.up:
		return _risen(panel.rise_tick, now, rise_ticks)
	var reached := _risen(panel.rise_tick, float(panel.lift_tick), rise_ticks)
	if drop_ticks <= 0:
		return 0.0
	var fallen := clampf((now - float(panel.lift_tick)) / float(drop_ticks), 0.0, 1.0)
	return reached * (1.0 - fallen)


## Whether the car of `type` is fully up at host tick `now`: a hold runs and began at least
## rise_ticks() ago (the host's CarRepair.is_up, from LiftChanged).
static func is_up(model: ClientModel, type: CarRepair, now: float) -> bool:
	var panel := station_of(model, type, Role.PANEL)
	return panel != null and panel.up and now - float(panel.rise_tick) >= float(type.rise_ticks())


## Whether the car of `panel` is going up at host tick `now` (a hold runs, not yet fully up): the
## lift's motor runs.
static func rising(panel: ClientModel.Station, now: float, rise_ticks: int) -> bool:
	return panel != null and panel.up and now - float(panel.rise_tick) < float(rise_ticks)


## The host ticks a fit takes: the car kind's Interact rule's HoldStation `seconds` by the
## channel's own rounding (ChannelEffect); 0 for no such rule.
static func fit_ticks(type: CarRepair) -> int:
	var hold := StationUse.hold_of(type.car if type != null else null)
	return maxi(1, Ticks.from_seconds(hold.seconds)) if hold != null else 0


## The own player's fit at host tick `now`, 0 to 1 (FitChanged's tick and the client's copy of the
## fit's seconds); -1 when the own player is not the car's fitter.
static func fit_progress(model: ClientModel, type: CarRepair, now: float) -> float:
	var car := station_of(model, type, Role.CAR)
	if car == null or model.own_peer == 0 or car.fitter != model.own_peer or car.fit_tick < 0:
		return -1.0
	var ticks := fit_ticks(type)
	if ticks <= 0:
		return -1.0
	return clampf((now - float(car.fit_tick)) / float(ticks), 0.0, 1.0)


## Whether E offers the car repair station `id` of `model` (of `type`) to the own player now (see
## the class doc); false for a station of no role of `type`.
static func usable(model: ClientModel, type: CarRepair, id: int) -> bool:
	var station: ClientModel.Station = model.stations.get(id) if model != null else null
	if station == null:
		return false
	match role_of(type, station.kind):
		Role.PANEL:
			return not is_done(model, type) and not station.up
		Role.CAR:
			if is_done(model, type) or station.fitter != 0 or not model.host_tick_now.is_valid():
				return false
			if not is_up(model, type, float(model.host_tick_now.call() as int)):
				return false
			var needed := needed_part(model, type)
			var hand: ClientModel.Item = model.items.get(model.hand_item(model.own_peer))
			return needed != &"" and hand != null and hand.kind == needed
		Role.BIN:
			return true
	return false


static func _risen(start: int, at: float, rise_ticks: int) -> float:
	if rise_ticks <= 0:
		return 1.0
	return clampf((at - float(start)) / float(rise_ticks), 0.0, 1.0)
