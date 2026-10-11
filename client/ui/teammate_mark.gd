class_name TeammateMark
extends TextureRect
## The teammate mark next to a teammate's name on a name plate (#257): shown only on a dissident's
## own client, from its own Teammates knowledge (NamePlates.marked). The UI handoff (prime-game-ui
## `docs/handoff/s07-hud.md`, state `mate`) draws the pack's white `teammate-mark.svg` (imported
## at its scale 0.84, #520) in a 20x20 TextureRect tinted with ToyNamePlateText's `font_color`
## through self_modulate, set again whenever the theme changes.

## The pack's mark, from ui-sync's imported copy (#520).
const ART := preload("res://assets/ui/toy_pack/icons/teammate-mark.svg")
## The handoff's size, in px at the 1920x1080 base (layout, not style).
const SIZE := Vector2(20.0, 20.0)


func _init() -> void:
	name = "Mark"
	texture = ART
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The tint the handoff gives: the plate's text colour.
func tint() -> Color:
	return get_theme_color(&"font_color", &"ToyNamePlateText")


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		self_modulate = tint()
