class_name DeliveryClient
extends TaskClient
## Delivery's client (#1260, ARCHITECTURE §4.7.59): each of its station kinds is a circle, drawn
## by CircleViews, the one view of the circles and of Delivery by meaning's drop-offs, so this
## client makes it. E offers none of its stations (a circle is walked into, never used).


func draws_circle(_kind_id: StringName) -> bool:
	return true


func make_view() -> Node3D:
	var view := CircleViews.new()
	view.name = "CircleViews"
	return view
