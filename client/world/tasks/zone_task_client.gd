class_name ZoneTaskClient
extends TaskClient
## The zone task's client (#1260, ARCHITECTURE §4.7.59): its zones and their fill are ZoneViews'
## (#650, §4.7.51), never a circle; E offers none of its stations (a zone counts presence).


## Every ZoneTask of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[ZoneTask]:
	var found: Array[ZoneTask] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type is ZoneTask:
			found.append(type as ZoneTask)
	return found


func make_view() -> Node3D:
	var view := ZoneViews.new()
	view.name = "ZoneViews"
	return view
