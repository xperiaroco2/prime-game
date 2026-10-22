class_name DeliveryByMeaningClient
extends TaskClient
## Delivery by meaning's client (#1260, ARCHITECTURE §4.7.59): each of its station kinds is a
## drop-off, drawn by CircleViews (DE11), whose one view Delivery's client makes, so this client
## makes none. E offers none of its stations (a drop-off is walked into, never used).


## Every DeliveryByMeaning of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[DeliveryByMeaning]:
	var found: Array[DeliveryByMeaning] = []
	if mode == null:
		return found
	for type: TaskType in mode.task_types:
		if type is DeliveryByMeaning:
			found.append(type as DeliveryByMeaning)
	return found


func draws_circle(_kind_id: StringName) -> bool:
	return true
