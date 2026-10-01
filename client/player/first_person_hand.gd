class_name FirstPersonHand
extends Node3D
## The own hand item in the first-person view (ARCHITECTURE §4.7, Hands; M4-8): a child of the
## local player's camera showing the item the own ClientModel says is in the own hand, by the same
## greybox look as in the world (ItemView). A one-handed item sits low on the right; a two-handed
## one (the package) low in the middle, held with both hands. ItemViews tells it what to show; it
## reads nothing itself. The offsets are looks, placeholders until the art pass.

## Where the item sits in the camera's space, in metres.
const ONE_HANDED := Vector3(0.28, -0.3, -0.55)
const TWO_HANDED := Vector3(0.0, -0.7, -1.0)

var _shown_kind: StringName = &""
var _shown_colour: Color
var _view: ItemView


func _init() -> void:
	name = "FirstPersonHand"


## Shows an item of `kind` in `colour` (a package's circle colour), held with both hands when
## `two_handed`; an empty kind shows nothing.
func show_item(kind: StringName, colour: Color, two_handed := false) -> void:
	if kind == _shown_kind and colour == _shown_colour:
		return
	_shown_kind = kind
	_shown_colour = colour
	if _view != null:
		_view.queue_free()
		_view = null
	if kind.is_empty():
		return
	_view = ItemView.make(-1, kind, colour)
	_view.name = "HandItem"
	_view.position = TWO_HANDED if two_handed else ONE_HANDED
	add_child(_view)


## The kind shown, or empty.
func shown_kind() -> StringName:
	return _shown_kind
