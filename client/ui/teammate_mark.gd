class_name TeammateMark
extends Control
## The teammate mark next to a teammate's name on a name plate (#257): shown only on a dissident's
## own client, from its own Teammates knowledge (NamePlates.marked). The UI handoff (prime-game-ui
## `docs/handoff/s07-hud.md`, state `mate`) draws it as the pack's white `teammate-mark.svg` in a
## 20x20 TextureRect tinted with ToyNamePlateText's `font_color`; the pack's SVGs are not imported
## yet (#520), so until then this draws the same diamond in code, in the same tint, at the same
## size. #489 and #520 swap it for the TextureRect; nothing else depends on how it is drawn.

## The handoff's size, in px at the 1920x1080 base (layout, not style).
const SIZE := Vector2(20.0, 20.0)
## The SVG's diamond with its 2 px stroke reaches 9.5 of its 24 px viewBox from the middle.
const REACH := 9.5 / 24.0


func _init() -> void:
	name = "Mark"
	custom_minimum_size = SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The tint the handoff gives: the plate's text colour.
func tint() -> Color:
	return get_theme_color(&"font_color", &"ToyNamePlateText")


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var middle := size * 0.5
	var reach := minf(size.x, size.y) * REACH
	var corners := PackedVector2Array(
		[
			middle + Vector2(0.0, -reach),
			middle + Vector2(reach, 0.0),
			middle + Vector2(0.0, reach),
			middle + Vector2(-reach, 0.0),
		]
	)
	draw_colored_polygon(corners, tint())
