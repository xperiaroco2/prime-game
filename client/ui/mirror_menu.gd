class_name MirrorMenu
extends Control
## The mirror's colour menu (#1394; GDD §3 "The mirror", in M8 only the colour), the plainest
## placeholder until #1395 builds the mirror's real menu and reflection: one Toy menu panel at the
## right with a swatch per body colour (BodyColours, in index order), no text (the copy deck has no
## mirror key yet). It shows on the lobby screen while the own player holds a mirror place as the
## last MirrorPlaces told it (shown_for); the game frees the mouse under it (GameUi.frees_mouse) and
## a click on a swatch asks the host for that colour (`colour_chosen`, sent as SetProfile with the
## own name: profile_of). The own colour's swatch is pressed; the host's ProfileChanged moves it,
## nothing is predicted. E again at the place, or walking off it, gives the place up and hides it.

## A swatch was clicked: the own player asks for body colour `colour`.
signal colour_chosen(colour: int)

## The swatches, one per body colour, in index order.
var swatches: Array[Button] = []
var panel := PanelContainer.new()
var grid := GridContainer.new()

## The own colour drawn last, -1 before any.
var _colour := -1


func _init() -> void:
	name = "MirrorMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.name = "Panel"
	panel.theme_type_variation = &"ToyPanelMenu"
	grid.name = "Swatches"
	grid.columns = 5
	panel.add_child(grid)
	for colour: int in BodyColours.HEXES.size():
		var swatch := UiParts.toggle("", _choose.bind(colour))
		swatch.name = "Swatch%d" % colour
		var dot := Panel.new()
		dot.name = "Dot"
		dot.theme_type_variation = &"ToyRosterDot"
		dot.self_modulate = BodyColours.of(colour)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiParts.sized(dot)
		dot.set_anchors_preset(Control.PRESET_CENTER)
		dot.grow_horizontal = Control.GROW_DIRECTION_BOTH
		dot.grow_vertical = Control.GROW_DIRECTION_BOTH
		swatch.add_child(dot)
		UiParts.sized(swatch)
		grid.add_child(swatch)
		swatches.append(swatch)
	var raised := UiParts.raised(panel)
	raised.name = "Raised"
	raised.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	raised.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	raised.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(raised)
	visible = false


## Whether the menu shows on screen `now` for `model`'s own player: the lobby screen, holding a
## mirror place.
static func shown_for(model: ClientModel, now: GameFlow.Screen) -> bool:
	return (
		model != null
		and now == GameFlow.Screen.LOBBY
		and model.mirror.place_of(model.own_peer) >= 0
	)


## The SetProfile fields that ask for `colour` and keep the own name as the roster has it.
static func profile_of(model: ClientModel, colour: int) -> Dictionary:
	var own: ClientModel.Member = model.roster.get(model.own_peer)
	return {"name": own.name if own != null else "", "colour": colour}


## Shows or hides it for `model` on screen `now` and presses the own colour's swatch.
func refresh(model: ClientModel, now: GameFlow.Screen) -> void:
	visible = shown_for(model, now)
	if not visible:
		return
	var colour := model.colour_of(model.own_peer)
	if colour == _colour:
		return
	_colour = colour
	for index: int in swatches.size():
		swatches[index].set_pressed_no_signal(index == colour)


func _choose(colour: int) -> void:
	# A toggle flips itself on a click; the host's answer decides which one stays pressed.
	if colour >= 0 and colour < swatches.size():
		swatches[colour].set_pressed_no_signal(colour == _colour)
	colour_chosen.emit(colour)
