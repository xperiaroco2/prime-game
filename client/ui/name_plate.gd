class_name NamePlate
extends PanelContainer
## One mark over a fellow dissident's head (#257, #756): the TeammateMark and nothing else. The
## engineer's KD2 answer took the names off every player, and answer 5 on #516 kept the dissident's
## cue: so the plate holds no name, no role, no health, no life state (the M4 ADR's §3). The class
## keeps its name from #257; the tree is `Plate` ToyNamePlate > `Mark`. The look is provisional
## (the Toy round HUD, #489, restyles it); NamePlates places it and knows nothing of its look.

var mark := TeammateMark.new()


func _init() -> void:
	name = "Plate"
	theme_type_variation = &"ToyNamePlate"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mark)
	# A container only grows to its minimum on its own: a smaller one (the large-text theme swapped
	# back) shrinks the plate here.
	minimum_size_changed.connect(reset_size)


## Centres the plate on `point` (the projected point over the head, in the layer's coordinates).
func centre_on(point: Vector2) -> void:
	position = point - size * 0.5
