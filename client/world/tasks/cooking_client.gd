class_name CookingClient
extends TaskClient
## Cooking's client (#1260, ARCHITECTURE §4.7.59; #776, §4.7.55): its five station kinds are the
## level's cooking scenes (CookingViews), never a circle, and E offers each as CookingUse says.


## Every Cooking of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[Cooking]:
	var found: Array[Cooking] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type is Cooking:
			found.append(type as Cooking)
	return found


## Whether `kind_id` is one of `type`'s five station kinds.
func owns(type: TaskType, kind_id: StringName) -> bool:
	return CookingUse.role_of(type as Cooking, kind_id) != CookingUse.Role.NONE


## CookingUse.usable: what E offers at the station, by its role.
func usable(model: ClientModel, type: TaskType, id: int) -> bool:
	return CookingUse.usable(model, type as Cooking, id)


func make_view() -> Node3D:
	var view := CookingViews.new()
	view.name = "CookingViews"
	return view
