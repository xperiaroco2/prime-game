class_name FirstPersonHand
extends Node3D
## The own hand item in the first-person view (ARCHITECTURE §4.7, Hands; M4-8): a child of the
## local player's camera showing the item the own ClientModel says is in the own hand, by the same
## greybox look as in the world (ItemView). A one-handed item sits low on the right; a two-handed
## one (the package) low in the middle, held with both hands. ItemViews tells it what to show; it
## reads nothing itself. The offsets are looks, placeholders until the art pass. The hand item is on
## PhotoLayers.LIVE_AVATAR, so a shot's picture never draws it beside the holder's puppet (#787).

## Where the item sits in the camera's space, in metres.
const ONE_HANDED := Vector3(0.28, -0.3, -0.55)
const TWO_HANDED := Vector3(0.0, -0.7, -1.0)
## The holder's close-up of its photo (#787): in front of the eye, turned to face it, larger. Looks,
## "not a decision".
const CLOSE := Vector3(0.0, -0.02, -0.34)
const CLOSE_SCALE := 2.2
## The card upright, its picture (the look's +Y face) towards the eye (+Z), its top up.
const CLOSE_TURN := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

var _shown_kind: StringName = &""
var _shown_colour: Color
var _shown_id := -1
var _picture: Texture2D
var _view: ItemView
var _two_handed := false
var _close := false


func _init() -> void:
	name = "FirstPersonHand"


## Shows an item of `kind` in `colour` (a package's circle colour), held with both hands when
## `two_handed`; an empty kind shows nothing. `id`, the item's, tells two photos of one kind apart
## (#787): another item rebuilds the view and drops the picture.
func show_item(kind: StringName, colour: Color, two_handed := false, id := -1) -> void:
	if kind == _shown_kind and colour == _shown_colour and id == _shown_id:
		return
	_shown_kind = kind
	_shown_colour = colour
	_shown_id = id
	_picture = null
	_two_handed = two_handed
	_close = false
	if _view != null:
		_view.queue_free()
		_view = null
	if kind.is_empty():
		return
	_view = ItemView.make(-1, kind, colour)
	_view.name = "HandItem"
	_hold()
	PhotoLayers.assign(_view, PhotoLayers.LIVE_AVATAR)
	add_child(_view)


## The kind shown, or empty.
func shown_kind() -> StringName:
	return _shown_kind


## The item id shown (-1 for none, or one shown without its id).
func shown_id() -> int:
	return _shown_id


## Shows `texture` on a photo in the hand (#787: the shot's picture; null the grey blank), kept
## until another item is shown.
func set_picture(texture: Texture2D) -> void:
	_picture = texture
	if _view != null:
		_view.set_picture(texture)


## The hand item's view, or null.
func view() -> ItemView:
	return _view


## Holds the shown item up close, facing the eye (#787: the holder looks at its photo), or back
## in the hand; nothing with no item shown. Showing another item ends it.
func set_close(on: bool) -> void:
	_close = on and _view != null
	if _view != null:
		_hold()


func is_close() -> bool:
	return _close


func _hold() -> void:
	if _close:
		_view.transform = Transform3D(CLOSE_TURN.scaled(Vector3.ONE * CLOSE_SCALE), CLOSE)
		return
	_view.transform = Transform3D(Basis.IDENTITY, TWO_HANDED if _two_handed else ONE_HANDED)
