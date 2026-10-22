class_name CarRepairClient
extends TaskClient
## The car repair's client (#1260, ARCHITECTURE §4.7.59; #811, §4.7.57): its car, lift panel,
## picture and bins are the level's car repair scenes (CarRepairViews), never a circle, and E
## offers each as CarRepairUse says.


## Every CarRepair of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[CarRepair]:
	var found: Array[CarRepair] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type is CarRepair:
			found.append(type as CarRepair)
	return found


## Whether `kind_id` is one of `type`'s station kinds.
func owns(type: TaskType, kind_id: StringName) -> bool:
	return CarRepairUse.role_of(type as CarRepair, kind_id) != CarRepairUse.Role.NONE


## CarRepairUse.usable: what E offers at the station, by its role.
func usable(model: ClientModel, type: TaskType, id: int) -> bool:
	return CarRepairUse.usable(model, type as CarRepair, id)


func make_view() -> Node3D:
	var view := CarRepairViews.new()
	view.name = "CarRepairViews"
	return view
