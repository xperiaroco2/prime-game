class_name ShipEngineClient
extends TaskClient
## The ship engine's client (#1260, ARCHITECTURE §4.7.59; the core: #1453): E is answered for the
## console and for every kind's site and fixture station (ShipEngine.station_kinds). The client does
## not know whether the engine has started or a site holds a problem, so it always offers the use
## and the host's StationUsable refuses it (`unavailable`). No circle and no view yet: the ship's
## stations and lamps are the level's scenes and a view is part 3 of #1225 (#1453).


## Every ShipEngine of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[ShipEngine]:
	var found: Array[ShipEngine] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type is ShipEngine:
			found.append(type as ShipEngine)
	return found


## Whether `kind_id` is the console's or a problem kind's station kind of `type`.
func owns(type: TaskType, kind_id: StringName) -> bool:
	var engine := type as ShipEngine
	if engine == null:
		return false
	for kind: StationKind in engine.station_kinds():
		if kind != null and kind.id == kind_id:
			return true
	return false


## Always: the host refuses a use that no start or no problem answers.
func usable(_model: ClientModel, _type: TaskType, _id: int) -> bool:
	return true
