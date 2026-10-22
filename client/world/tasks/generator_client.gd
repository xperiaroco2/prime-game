class_name GeneratorClient
extends TaskClient
## The Generator's client (#1260, ARCHITECTURE §4.7.59; #801, §4.7.54): its generator and switch
## kinds are the level's station scenes (StationViews), never a circle, and E offers each until
## the charge is done (the host's StationUsable): nothing here reads a switch's `on`.


## Every Generator of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[Generator]:
	var found: Array[Generator] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type is Generator:
			found.append(type as Generator)
	return found


## Whether `kind_id` is `type`'s generator or switch kind.
func owns(type: TaskType, kind_id: StringName) -> bool:
	var generator := type as Generator
	if generator == null:
		return false
	for kind: StationKind in [generator.generator, generator.switch]:
		if kind != null and kind.id == kind_id:
			return true
	return false


## Until the charge is done: then neither the generator nor a switch can be used (StationUsable).
func usable(model: ClientModel, type: TaskType, _id: int) -> bool:
	var charged: ClientModel.Station = model.stations.get(
		StationUse.generator_station(model, type as Generator)
	)
	return charged == null or not charged.done


func make_view() -> Node3D:
	var view := StationViews.new()
	view.name = "StationViews"
	return view
