class_name ToyBar
extends PanelContainer
## A Toy bar (#289; prime-game-ui spec §5): a ToyBarTrack holding a fill-only ProgressBar,
## ToyBarHealth or ToyBarStamina, with no percentage text. The health fill's StyleBox is white and
## takes the ramp's stop as its `self_modulate`: the 21 stops `ramp_stop_00` … `ramp_stop_20` are
## mixed once, in Oklab, by the UI build, so no colour is mixed here (no `Color.lerp`, which would
## not match the mock-ups). The downed screen's bleed-out bar uses the same ramp. The stamina fill
## keeps its own colour. The track's height comes from its `height` constant (UiParts.sized).

const HEALTH := &"ToyBarHealth"
const STAMINA := &"ToyBarStamina"
const STEPS := 20

var fill := ProgressBar.new()


func _init(variation: StringName = HEALTH) -> void:
	theme_type_variation = &"ToyBarTrack"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.theme_type_variation = variation
	fill.min_value = 0.0
	fill.max_value = 1.0
	fill.step = 0.0
	fill.show_percentage = false
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Deferred, as in UiParts.sized: the theme cache is still the old one while it is emitted.
	fill.theme_changed.connect(_tint, CONNECT_DEFERRED)
	add_child(fill)
	UiParts.sized(self)


## The ramp's stop for a fraction `hp` (0 to 1): the nearest of 21, the same expression as the
## UI pack's JavaScript.
static func step_of(hp: float) -> int:
	return clampi(floori(hp * STEPS + 0.5), 0, STEPS)


## Shows `hp` (0 to 1) and, for health, its stop's colour.
func set_fraction(hp: float) -> void:
	fill.value = clampf(hp, 0.0, 1.0)
	_tint()


func _tint() -> void:
	if fill.theme_type_variation == HEALTH:
		fill.self_modulate = fill.get_theme_color("ramp_stop_%02d" % step_of(fill.value), HEALTH)
