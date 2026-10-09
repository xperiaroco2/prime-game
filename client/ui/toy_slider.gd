class_name ToySlider
extends HSlider
## A Toy slider (#289): the ToySlider variation, its grabber textures from the theme (the pack's
## knobs, #520). Godot's Slider draws no focus StyleBox, so this draws the theme's
## `get_theme_stylebox(&"focus")` over itself while it shows keyboard or gamepad focus, not after
## a click (focus taken by the mouse is hidden: `has_focus(true)`).


func _init() -> void:
	theme_type_variation = &"ToySlider"
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Whether the code-drawn focus ring shows now.
func shows_ring() -> bool:
	return has_focus(true)


func _draw() -> void:
	if shows_ring():
		draw_style_box(get_theme_stylebox(&"focus"), Rect2(Vector2.ZERO, size))
