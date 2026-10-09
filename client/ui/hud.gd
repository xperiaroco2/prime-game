class_name Hud
extends Control
## The round's HUD in the Toy style (#489; ARCHITECTURE §4.7.37): the UI handoff's tree, node for
## node (prime-game-ui `ui-0.4.0` `docs/handoff/s07-hud.md`), drawing what HudText says. HUD edges
## sit 40 px in (px at the 1920x1080 base, #287):
## - `Timer` (top centre): the time left as mm:ss, data; its 140 px hold the widest time,
##   "44:44", so the centred plate never changes width.
## - `Role` (top left): the own role's chip.
## - `Cross` and `Aim` (centre): the crosshair and the name of the item under it within reach;
##   `Raising`, the own raise's progress, replaces Aim (the engineer, 2026-10-06).
## - `Vitals` (bottom left): health (its fill coloured by the ramp's stop, ToyBar), stamina and the
##   microphone (on: `mic` tinted `icon_on`; off: `mic-off` tinted `icon_off`).
## - `Slots` (bottom right): the hand, always the active slot, and the belt (HudSlot).
## - `Spectate` (top centre, while dead): the handoff s09's plate naming whom the player
##   watches; the watched player's hand and belt stay in Slots (#168).
## Styled only through the shared theme's variations (no override; a size constant read into
## `custom_minimum_size` with UiParts.sized); every node ignores the mouse and takes no focus. Texts
## are deck keys (#208); the time and names are data (`auto_translate_mode` DISABLED). It reads
## nothing itself: the game feeds it.

## The HUD's distance from the screen's edges and Aim's below the centre, px (the handoff).
const EDGE := 40
const AIM_BELOW := 38
## Fixed sizes the handoff gives (px; layout, not style): the timer's minimum width, the bars'
## length, a bar fill's height, the mic icon and the raise bar.
const TIME_WIDTH := 140
const BAR_LENGTH := 320
const FILL_HEIGHT := 10
const MIC_ICON := Vector2(28, 28)
const RAISE_BAR := Vector2(240, 10)

var timer := PanelContainer.new()
var time_label := UiParts.styled_label("", &"ToyTimer")
var role := PanelContainer.new()
var role_label := UiParts.styled_label("", &"ToyChipPlateText")
var cross := Panel.new()
var aim := PanelContainer.new()
var aim_label := UiParts.styled_label("", &"ToyChipPlateText")
var vitals := VBoxContainer.new()
var health_box := VBoxContainer.new()
var health := ToyBar.new(ToyBar.HEALTH)
var stamina_box := VBoxContainer.new()
var stamina := ToyBar.new(ToyBar.STAMINA)
var mic := PanelContainer.new()
var mic_icon := TextureRect.new()
var slots := HBoxContainer.new()
var hand := HudSlot.new("Hand", &"ToySlotActive", "hud.slot.hand", &"ToySlotText")
var belt := HudSlot.new("Belt", &"ToySlot", "hud.slot.belt", &"ToyTextOnDark")
var raising := PanelContainer.new()
var raising_bar := ProgressBar.new()
var spectate := PanelContainer.new()
var watching_label := UiParts.styled_label("", &"ToyTitleOnDark")
## The crosshair, Aim and Raising show; off while the map covers the middle or the player is not
## living.
var aiming := true:
	set = set_aiming

## The last state shown (the translation change rebuilds the watched name's line from it).
var _shown := HudText.Shown.new()


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_top()
	_build_middle()
	_build_vitals()
	_build_slots()
	_build_spectate()
	for node: Node in find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	theme_changed.connect(_tint_mic, CONNECT_DEFERRED)
	show_hud(_shown)


## Shows `shown`.
func show_hud(shown: HudText.Shown) -> void:
	_shown = shown
	timer.visible = not shown.time.is_empty()
	time_label.text = shown.time
	role.visible = not shown.role.is_empty()
	role_label.text = shown.role
	vitals.visible = shown.vitals
	health.set_fraction(shown.health)
	stamina.set_fraction(shown.stamina)
	mic_icon.texture = ToyIcons.texture(&"mic" if shown.mic else &"mic-off")
	_tint_mic()
	slots.visible = shown.slots
	hand.show_slot(shown.hand)
	belt.show_slot(shown.belt)
	aim_label.text = shown.aim
	raising_bar.value = maxf(0.0, shown.raising)
	spectate.visible = not shown.watching.is_empty()
	_write_watching()
	_show_middle()


## Whether the microphone shows on (`mic` tinted `icon_on`).
func shows_mic_on() -> bool:
	return _shown.mic


func set_aiming(on: bool) -> void:
	aiming = on
	_show_middle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_write_watching()


## The crosshair, and Aim or Raising under it, while aiming.
func _show_middle() -> void:
	cross.visible = aiming
	raising.visible = aiming and _shown.raising >= 0.0
	aim.visible = aiming and not raising.visible and not _shown.aim.is_empty()


## "Watching: <name>": a key with a placeholder, set from code (auto_translate_mode DISABLED).
func _write_watching() -> void:
	if _shown.watching.is_empty():
		watching_label.text = ""
		return
	watching_label.text = tr(HudText.WATCHING_KEY).format({"name": _shown.watching})


func _tint_mic() -> void:
	if not mic_icon.is_inside_tree():
		return
	var colour := &"icon_on" if _shown.mic else &"icon_off"
	mic_icon.self_modulate = mic_icon.get_theme_color(colour, &"ToyMic")


func _build_top() -> void:
	timer.name = "Timer"
	timer.theme_type_variation = &"ToyPlate"
	_pin(
		timer, Control.PRESET_CENTER_TOP, Vector2(0, EDGE), GROW_DIRECTION_BOTH, GROW_DIRECTION_END
	)
	time_label.name = "Time"
	time_label.custom_minimum_size = Vector2(TIME_WIDTH, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	timer.add_child(time_label)
	role.name = "Role"
	role.theme_type_variation = &"ToyChipPlate"
	_pin(role, Control.PRESET_TOP_LEFT, Vector2(EDGE, EDGE), GROW_DIRECTION_END, GROW_DIRECTION_END)
	role_label.name = "Text"
	role.add_child(role_label)


func _build_middle() -> void:
	cross.name = "Cross"
	cross.theme_type_variation = &"ToyCrosshair"
	_pin(cross, Control.PRESET_CENTER, Vector2.ZERO, GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH)
	UiParts.sized(cross)
	aim.name = "Aim"
	aim.theme_type_variation = &"ToyChipPlate"
	_pin(
		aim, Control.PRESET_CENTER, Vector2(0, AIM_BELOW), GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH
	)
	aim_label.name = "Text"
	aim.add_child(aim_label)
	raising.name = "Raising"
	raising.theme_type_variation = &"ToyPlate"
	var raise_at := Vector2(0, AIM_BELOW)
	_pin(raising, Control.PRESET_CENTER, raise_at, GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH)
	raising_bar.name = "Bar"
	raising_bar.theme_type_variation = &"ToyBarProgress"
	raising_bar.custom_minimum_size = RAISE_BAR
	raising_bar.min_value = 0.0
	raising_bar.max_value = 1.0
	raising_bar.step = 0.0
	raising_bar.show_percentage = false
	raising.add_child(raising_bar)


func _build_vitals() -> void:
	vitals.name = "Vitals"
	vitals.theme_type_variation = &"ToyColumnTwelve"
	var corner := Vector2(EDGE, -EDGE)
	_pin(vitals, Control.PRESET_BOTTOM_LEFT, corner, GROW_DIRECTION_END, GROW_DIRECTION_BEGIN)
	_bar(health_box, "Health", "hud.health", health)
	_bar(stamina_box, "Stamina", "hud.stamina", stamina)
	mic.name = "Mic"
	mic.theme_type_variation = &"ToyMic"
	mic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiParts.sized(mic)
	mic_icon.name = "Icon"
	mic_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mic_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mic_icon.custom_minimum_size = MIC_ICON
	mic_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mic_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mic.add_child(mic_icon)
	vitals.add_child(health_box)
	vitals.add_child(stamina_box)
	vitals.add_child(mic)


## A bar's column `box` named `box_name`: its caption `caption` over its track `bar`.
func _bar(box: VBoxContainer, box_name: String, caption: String, bar: ToyBar) -> void:
	box.name = box_name
	box.theme_type_variation = &"ToyColumnFour"
	box.custom_minimum_size = Vector2(BAR_LENGTH, 0)
	var cap := PanelContainer.new()
	cap.name = "Cap"
	cap.theme_type_variation = &"ToyBarLabel"
	cap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var text := UiParts.styled_label(caption, &"ToyHudCaption")
	text.name = "Text"
	cap.add_child(text)
	bar.name = "Track"
	# ToyBarTrack gives the height only: the length is the handoff's (UiParts.sized keeps it).
	bar.custom_minimum_size = Vector2(BAR_LENGTH, 0)
	bar.fill.name = "Fill"
	bar.fill.custom_minimum_size = Vector2(0, FILL_HEIGHT)
	box.add_child(cap)
	box.add_child(bar)


func _build_slots() -> void:
	slots.name = "Slots"
	slots.theme_type_variation = &"ToyRowTwelve"
	var corner := Vector2(-EDGE, -EDGE)
	_pin(slots, Control.PRESET_BOTTOM_RIGHT, corner, GROW_DIRECTION_BEGIN, GROW_DIRECTION_BEGIN)
	slots.add_child(hand)
	slots.add_child(belt)


## The handoff s09's `Spectate` plate, its `Watching` line only (the respawn countdown stays on the
## life panel until the Toy downed screen, #497).
func _build_spectate() -> void:
	spectate.name = "Spectate"
	spectate.theme_type_variation = &"ToyPlate"
	var top := Vector2(0, EDGE)
	_pin(spectate, Control.PRESET_CENTER_TOP, top, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnFour"
	watching_label.name = "Watching"
	watching_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	watching_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(watching_label)
	spectate.add_child(column)


## Adds `node` anchored at `preset` with all four offsets at `at` (a point: the node takes its
## minimum size, growing as `grow_x` and `grow_y` say, and shrinks back with it).
func _pin(
	node: Control,
	preset: Control.LayoutPreset,
	at: Vector2,
	grow_x: Control.GrowDirection,
	grow_y: Control.GrowDirection
) -> void:
	node.set_anchors_preset(preset)
	node.offset_left = at.x
	node.offset_right = at.x
	node.offset_top = at.y
	node.offset_bottom = at.y
	node.grow_horizontal = grow_x
	node.grow_vertical = grow_y
	add_child(node)
