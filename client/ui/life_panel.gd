class_name LifePanel
extends Control
## The life panel of the round (ARCHITECTURE §4.7, M4-9): what LifeHud says about the own player's
## life, at the bottom centre: a title, a few lines and a progress bar (a raise, the give-up hold).
## Styled only through the shared theme on the Ui (GameUi.THEME: the type variations LifePanel,
## LifeTitle and LifeText), no inline colours, sizes or fonts. Hidden when LifeHud shows nothing.
## Never M4-8's HUD scene: a panel of its own under Ui.

## Distance from the bottom edge of the screen, in pixels of the layout.
const BOTTOM_MARGIN := 96

var panel := PanelContainer.new()
var title_label := Label.new()
var lines_label := Label.new()
var bar := ProgressBar.new()
var bar_label := Label.new()


func _init() -> void:
	name = "LifePanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	panel.theme_type_variation = &"LifePanel"
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(panel)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, BOTTOM_MARGIN)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(gap)
	var column := VBoxContainer.new()
	panel.add_child(column)
	title_label.theme_type_variation = &"LifeTitle"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)
	lines_label.theme_type_variation = &"LifeText"
	lines_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(lines_label)
	bar_label.theme_type_variation = &"LifeText"
	bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(bar_label)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(320, 14)
	column.add_child(bar)
	show_hud(LifeHud.Shown.new())


## Shows `shown`; nothing when its title is empty.
func show_hud(shown: LifeHud.Shown) -> void:
	panel.visible = not shown.title.is_empty()
	title_label.text = shown.title
	lines_label.text = "\n".join(shown.lines)
	lines_label.visible = not shown.lines.is_empty()
	var has_bar := shown.progress >= 0.0
	bar.visible = has_bar
	bar_label.visible = has_bar and not shown.progress_label.is_empty()
	bar.value = maxf(0.0, shown.progress)
	bar_label.text = shown.progress_label
