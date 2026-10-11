class_name ToyRaised
extends MarginContainer
## The toy base under a raised face (#289; prime-game-ui spec §6). A MarginContainer fits every
## child to its own rect: first the base Panel (its variation is the face's `base` hint for the
## screen's context, ToyHints; it ignores the mouse), then the face. The base's StyleBox draws the
## face's shape moved down by its depth (expand margins), so layout and the hit area are the
## face's alone. A StyleBoxFlat shadow cannot draw that hard base (godot-facts §1).
##
## The wrapper takes the placement, the size flags, the minimum size and the visibility; the face
## keeps its variation, text and signals. A button face also gets ToyPress (UiParts.button); a
## panel or a Label face (ToyPanelMenu, ToyTitlePlate) does not (UiParts.raised). The base follows
## the face's variation (a ToyToggle swap, a later `theme_type_variation`) on its theme change.

## The face: a Button, a PanelContainer or a Label.
var face: Control
## The base Panel, always the first child; hidden while the face's variation has no base hint
## (a ghost button) and while a button face is disabled ("unplugged").
var base := Panel.new()
## The screen's context the base is picked for: ToyHints.DARK or ToyHints.LIGHT.
var context := ToyHints.DARK


## `face_control` raised on a `on_context` screen.
static func wrap(face_control: Control, on_context: StringName = ToyHints.DARK) -> ToyRaised:
	var raised := ToyRaised.new()
	if not face_control.name.is_empty():
		raised.name = "%sRaised" % face_control.name
	raised.context = on_context
	raised.face = face_control
	raised.add_child(face_control)
	face_control.theme_changed.connect(raised.sync_base)
	raised.sync_base()
	return raised


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.name = "Base"
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)


## Re-reads the base's variation from the face's and shows it unless the face is unplugged.
func sync_base() -> void:
	base.theme_type_variation = ToyHints.base_for(face.theme_type_variation, context)
	var button := face as BaseButton
	show_base(button == null or not button.disabled)


## Shows the base while `plugged` and the face has one (ToyPress: `not face.disabled`).
func show_base(plugged: bool) -> void:
	var shown := plugged and not base.theme_type_variation.is_empty()
	if base.visible != shown:
		base.visible = shown
