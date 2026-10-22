class_name PhotoTaskClient
extends TaskClient
## The photo task's client (#1260, ARCHITECTURE §4.7.59; #786 and #787, §4.7.56 and §4.7.58): its
## camera, photo spot, film box, printer and board are the level's photo scenes and items
## (PhotoViews), never a circle, and E offers each as PhotoUse says.


## Every PhotoTask of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[PhotoTask]:
	var found: Array[PhotoTask] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type is PhotoTask:
			found.append(type as PhotoTask)
	return found


## Whether `kind_id` is one of `type`'s five station kinds.
func owns(type: TaskType, kind_id: StringName) -> bool:
	return PhotoUse.role_of(type as PhotoTask, kind_id) != PhotoUse.Role.NONE


## PhotoUse.usable: what E offers at the station, by its role.
func usable(model: ClientModel, type: TaskType, id: int) -> bool:
	return PhotoUse.usable(model, type as PhotoTask, id)


func make_view() -> Node3D:
	var view := PhotoViews.new()
	view.name = "PhotoViews"
	return view
