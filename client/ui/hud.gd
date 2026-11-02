class_name Hud
extends Control
## The round's HUD (#489, #1570; ARCHITECTURE §4.7.37): the UI handoff's tree, node for node
## (prime-game-ui `ui-2.5.4` `docs/handoff/s07-hud.md`), drawing what HudText says (px at the
## 1920x1080 base, #287):
## - `Role` (top left, 39 px in): the own side's word tile, ToySticker, or ToyStickerAlert (the
##   danger outline) for a role whose players know each other (the handoff's human).
## - `Time` (top centre, 36 px down): `Row` > `Timer` (m:ss, data), `Divider` and `AngerColumn`
##   (the neighbours' anger: `Caption`, `Anger` > `Bar` and `Siren`). The meter and its divider
##   show only while HudText gives an anger (no mode has one yet, #1312); the cops' minute hides
##   the timer and its divider (one clock, the engineer 2026-10-22) and shows `Edge` (the danger
##   edge, under the tiles) and `Cops` (the banner, 168 px down, with the countdown).
## - `Roster` (top right, 39 px in): every player with the body colour, the own row first
##   (hud.roster.self), the dead dim (hud.roster.dead), the own role's tag on the own and the known
##   teammates' rows (the own Teammates knowledge only).
## - `Cross` and `Aim` (centre, Aim 64 px under it): the crosshair and the name of the item under
##   it within reach, or a cue with a key (the rescuer's #497, the hand-over's #1411, the chair's
##   #1420); `Raising`, the own raise's progress, replaces Aim (the engineer, 2026-10-06).
## - `Vitals` (bottom left, 39 px in): `Suit` (ToyPlate > `Rows`: `Title`, `Health` and `Stamina`,
##   each a caption and ten pips, ToyPips) and `Mic` beside it (on: `mic` tinted `icon_on`; off:
##   `mic-off` tinted `icon_off`).
## - `Notice` (under the top tile): the ship zap's notice (#1585), hidden but for its seconds; not
##   in the handoff (the engineer approved it on #1585's card).
## - `Slots` (bottom right, 36 px in): the three places, the one in the hand the handoff's Hand
##   tile (HudSlot; GDD §6, #1218).
## Downed, only the microphone shows; dead, nothing (the handoff s09, #497: LifeScreen draws the
## downed, spectating and respawn plates over it).
## Styled only through the shared theme's variations (no override; a size constant read into
## `custom_minimum_size` with UiParts.sized); every node ignores the mouse and takes no focus. Texts
## are deck keys (#208); the time and names are data (`auto_translate_mode` DISABLED). It reads
## nothing itself: the game feeds it.

## The HUD's distances from the screen's edges (the corner tiles, the slots and the top tile) and
## Aim's and the cops' banner's below the centre and the top, px (the handoff).
const EDGE := 39
const SLOTS_EDGE := 36
const TIME_DOWN := 36
const AIM_BELOW := 64
const COPS_DOWN := 168
## Fixed sizes the handoff gives (px; layout, not style): the timer's minimum width, the pips'
## captions, the siren, the mic icon and the raise bar.
const TIME_WIDTH := 120
const CAPTION_WIDTH := 150
const SIREN := Vector2(36, 36)
const MIC_ICON := Vector2(42, 42)
const RAISE_BAR := Vector2(360, 24)
const ANGER_CALM := &"ToyBarAngerCalm"
const ANGER_ALARM := &"ToyBarAngerAlarm"
## The anger meter's alarm line (the handoff: past 70 % the danger fill and caption).
const ANGER_ALARM_LINE := 0.7
## The zap notice's distance from the top: under the top tile (#1585).
const NOTICE_TOP := 120

var edge := Panel.new()
## The top tile (the handoff's `Time`): the timer and the anger meter.
var timer := PanelContainer.new()
var time_row := HBoxContainer.new()
var time_label := UiParts.styled_label("", &"ToyTimer")
var divider := Panel.new()
var anger_column := VBoxContainer.new()
var anger_caption := UiParts.styled_label("hud.anger", &"ToyHudCaption")
var anger_bar := ProgressBar.new()
var siren := TextureRect.new()
var role := PanelContainer.new()
var role_label := UiParts.styled_label("", &"ToyStickerText")
var roster := PanelContainer.new()
var roster_rows := VBoxContainer.new()
var cross := Panel.new()
var aim := PanelContainer.new()
var aim_label := UiParts.styled_label("", &"ToyChipPlateText")
var vitals := HBoxContainer.new()
var suit := PanelContainer.new()
var health_box := HBoxContainer.new()
var health_label := UiParts.styled_label("hud.health", &"ToyHudCaption")
var health := ToyPips.new(ToyPips.HEALTH, ToyPips.HEALTH_ALARM)
var stamina_box := HBoxContainer.new()
var stamina := ToyPips.new(ToyPips.STAMINA)
var mic := PanelContainer.new()
var mic_icon := TextureRect.new()
var slots := HBoxContainer.new()
## The three places (GDD §6), numbered 1 to 3, the one in the hand lit (HudSlot).
var places: Array[HudSlot] = [HudSlot.new(1), HudSlot.new(2), HudSlot.new(3)]
## The place in the hand now.
var hand: HudSlot:
	get:
		return places[_shown.selected]
## The first belt place now (the lowest place not in the hand).
var belt: HudSlot:
	get:
		return places[1 if _shown.selected == 0 else 0]
var raising := PanelContainer.new()
var raising_bar := ProgressBar.new()
## The notice under the top tile (#1585): the ship zap's, a plate with the text HudText gives.
var notice := PanelContainer.new()
var notice_label := UiParts.styled_label("", &"ToyChipPlateText")
var cops := PanelContainer.new()
var cops_count := UiParts.styled_label("", &"ToyPlateAlertCountdown")
## The crosshair, Aim and Raising show; off while the map covers the middle or the player is not
## living.
var aiming := true:
	set = set_aiming
## The role tile hides while the map is open (#491, the engineer on #652): at once, not at the
## next show_hud. The Esc menu's Role tab holds the role and the team.
var role_hidden := false:
	set(value):
		role_hidden = value
		role.visible = not role_hidden and not _shown.role.is_empty()

## The last state shown.
var _shown := HudText.Shown.new()


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_edge()
	_build_top()
	_build_roster()
	_build_middle()
	_build_notice()
	_build_vitals()
	_build_slots()
	_build_cops()
	_ignore_input(self)
	theme_changed.connect(_tint, CONNECT_DEFERRED)
	theme_changed.connect(_fit_timer, CONNECT_DEFERRED)
	show_hud(_shown)


## Shows `shown`.
func show_hud(shown: HudText.Shown) -> void:
	_shown = shown
	var in_cops := not shown.cops.is_empty()
	var angered := shown.anger >= 0.0
	time_label.text = shown.time
	time_label.visible = not shown.time.is_empty() and not in_cops
	anger_column.visible = angered
	divider.visible = time_label.visible and angered
	timer.visible = time_label.visible or angered
	_show_anger()
	edge.visible = in_cops
	cops.visible = in_cops
	cops_count.text = shown.cops
	role.visible = not role_hidden and not shown.role.is_empty()
	role.theme_type_variation = &"ToyStickerAlert" if shown.role_alert else &"ToySticker"
	role_label.text = shown.role
	_show_roster()
	vitals.visible = shown.vitals
	suit.visible = shown.bars
	health.set_fraction(shown.health)
	health_label.theme_type_variation = (
		&"ToyTextAlertOnLight" if health.alarmed() else &"ToyHudCaption"
	)
	stamina.set_fraction(shown.stamina)
	mic_icon.texture = ToyIcons.texture(&"mic" if shown.mic else &"mic-off")
	slots.visible = shown.slots
	for place in places.size():
		places[place].light(place == shown.selected)
		places[place].show_slot(shown.places[place])
	_show_aim_text()
	notice.visible = not shown.notice.is_empty()
	notice_label.text = shown.notice
	raising_bar.value = maxf(0.0, shown.raising)
	_show_middle()
	_tint()


## Whether the microphone shows on (`mic` tinted `icon_on`).
func shows_mic_on() -> bool:
	return _shown.mic


## The roster's rows shown now (each an HBoxContainer `Row<n>` > `Dot`, `Name` and `Tag`).
func roster_row(index: int) -> HBoxContainer:
	return roster_rows.get_child(index) as HBoxContainer


func set_aiming(on: bool) -> void:
	aiming = on
	_show_middle()


## The crosshair, and Aim or Raising under it, while aiming.
func _show_middle() -> void:
	cross.visible = aiming
	raising.visible = aiming and _shown.raising >= 0.0
	var named := not _shown.aim.is_empty() or _keyed()
	aim.visible = aiming and not raising.visible and named


## The anger meter: the bar's value and look (the danger fill and caption past the alarm line or in
## the cops' minute) and the siren.
func _show_anger() -> void:
	var anger := clampf(_shown.anger, 0.0, 1.0)
	var alarm := anger >= ANGER_ALARM_LINE or not _shown.cops.is_empty()
	anger_bar.value = anger
	anger_bar.theme_type_variation = ANGER_ALARM if alarm else ANGER_CALM
	anger_caption.theme_type_variation = &"ToyTextAlertOnLight" if alarm else &"ToyHudCaption"
	siren.texture = ToyIcons.texture(&"siren-on" if _shown.siren else &"siren-off")


## The roster's rows from `_shown.roster`, one HBoxContainer per player, rebuilt when the count
## changes; the names are set from code (data and placeholders) and again on a language change.
func _show_roster() -> void:
	roster.visible = not _shown.roster.is_empty()
	while roster_rows.get_child_count() > _shown.roster.size():
		var gone := roster_rows.get_child(roster_rows.get_child_count() - 1)
		# Freed now: a row out of the tree would be an orphan until the frame ends.
		gone.free()
	while roster_rows.get_child_count() < _shown.roster.size():
		roster_rows.add_child(_roster_row(roster_rows.get_child_count() + 1))
	for index in _shown.roster.size():
		var row := _shown.roster[index]
		var node := roster_row(index)
		(node.get_node(^"Dot") as Panel).self_modulate = row.colour
		var label := node.get_node(^"Name") as Label
		label.text = HudText.roster_name(row)
		if row.own:
			label.theme_type_variation = &"ToyRosterNameSelf"
		elif row.dead:
			label.theme_type_variation = &"ToyRosterNameDead"
		else:
			label.theme_type_variation = &"ToyRosterName"
		var tag := node.get_node(^"Tag") as PanelContainer
		tag.visible = not row.tag.is_empty()
		(tag.get_node(^"Text") as Label).text = row.tag


## Whether Aim shows a cue with a key in it (the rescuer's, the hand-over's #1411 or the chair's
## #1420).
func _keyed() -> bool:
	return (
		not _shown.raise_key.is_empty()
		or not _shown.hand_over_key.is_empty()
		or not _shown.sit_key.is_empty()
	)


## Aim's text: the item's deck key, translated by the label, or the rescuer's cue with the raise
## key in it, or the hand-over's with the interact key (#1411), set in code (data inside) and
## again when the language changes.
func _show_aim_text() -> void:
	if not _keyed():
		aim_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
		aim_label.text = _shown.aim
		return
	aim_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if not _shown.raise_key.is_empty():
		aim_label.text = HudText.raise_cue(_shown.raise_key)
	elif not _shown.hand_over_key.is_empty():
		aim_label.text = HudText.hand_over_cue(_shown.hand_over_key, _shown.hand_over_cue_key)
	else:
		aim_label.text = HudText.sit_cue(_shown.sit_key)


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED:
		return
	if _keyed():
		_show_aim_text()
	_show_roster()


## The icons' tints from the theme (the mic's on and off colours; the siren keeps its own colours).
func _tint() -> void:
	if not mic_icon.is_inside_tree():
		return
	var colour := &"icon_on" if _shown.mic else &"icon_off"
	mic_icon.self_modulate = mic_icon.get_theme_color(colour, &"ToyMic")


## The timer's width: the handoff's 120 px, or the widest m:ss of the theme's digits when that is
## wider (Unbounded's digits differ in width), so the centred tile never changes width with the
## time (#489).
func _fit_timer() -> void:
	if not time_label.is_inside_tree():
		return
	var font := time_label.get_theme_font(&"font")
	var font_size := time_label.get_theme_font_size(&"font_size")
	var widest := 0.0
	for digit in 10:
		widest = maxf(
			widest, font.get_string_size(str(digit), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	var colon := font.get_string_size(":", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	time_label.custom_minimum_size.x = maxf(TIME_WIDTH, ceilf(widest * 4.0 + colon))


func _build_edge() -> void:
	edge.name = "Edge"
	edge.theme_type_variation = &"ToyScreenEdgeAlert"
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.visible = false
	add_child(edge)


func _build_top() -> void:
	role.name = "Role"
	role.theme_type_variation = &"ToySticker"
	_pin(role, Control.PRESET_TOP_LEFT, Vector2(EDGE, EDGE), GROW_DIRECTION_END, GROW_DIRECTION_END)
	role_label.name = "Text"
	role.add_child(role_label)
	timer.name = "Time"
	timer.theme_type_variation = &"ToyPlate"
	var top := Vector2(0, TIME_DOWN)
	_pin(timer, Control.PRESET_CENTER_TOP, top, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	time_row.name = "Row"
	time_row.theme_type_variation = &"ToyRowTwentyFour"
	timer.add_child(time_row)
	time_label.name = "Timer"
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_label.custom_minimum_size = Vector2(TIME_WIDTH, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	time_row.add_child(time_label)
	divider.name = "Divider"
	divider.theme_type_variation = &"ToyTileDivider"
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_row.add_child(UiParts.sized(divider))
	anger_column.name = "AngerColumn"
	anger_column.theme_type_variation = &"ToyColumnFour"
	anger_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_row.add_child(anger_column)
	anger_caption.name = "Caption"
	anger_column.add_child(anger_caption)
	var anger_row := HBoxContainer.new()
	anger_row.name = "Anger"
	anger_row.theme_type_variation = &"ToyRowEight"
	anger_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	anger_column.add_child(anger_row)
	anger_bar.name = "Bar"
	anger_bar.theme_type_variation = ANGER_CALM
	anger_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fraction_bar(anger_bar)
	anger_row.add_child(UiParts.sized(anger_bar))
	siren.name = "Siren"
	siren.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	siren.custom_minimum_size = SIREN
	_icon(siren)
	anger_row.add_child(siren)


func _build_roster() -> void:
	roster.name = "Roster"
	roster.theme_type_variation = &"ToyRoster"
	var corner := Vector2(-EDGE, EDGE)
	_pin(roster, Control.PRESET_TOP_RIGHT, corner, GROW_DIRECTION_BEGIN, GROW_DIRECTION_END)
	UiParts.sized(roster)
	roster_rows.name = "Rows"
	roster_rows.theme_type_variation = &"ToyColumnEight"
	roster.add_child(roster_rows)


## A roster row `Row<number>`: `Dot` (the body colour, set per show), `Name` and `Tag` (hidden).
func _roster_row(number: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row%d" % number
	row.theme_type_variation = &"ToyRowTwelve"
	var dot := Panel.new()
	dot.name = "Dot"
	dot.theme_type_variation = &"ToyRosterDot"
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(UiParts.sized(dot))
	var label := UiParts.styled_label("", &"ToyRosterName")
	label.name = "Name"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var tag := PanelContainer.new()
	tag.name = "Tag"
	tag.theme_type_variation = &"ToyRosterTag"
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.visible = false
	var tag_text := UiParts.styled_label("", &"ToyRosterTagText")
	tag_text.name = "Text"
	tag_text.uppercase = true
	tag.add_child(tag_text)
	row.add_child(tag)
	_ignore_input(row)
	return row


func _build_middle() -> void:
	cross.name = "Cross"
	cross.theme_type_variation = &"ToyCrosshair"
	_pin(cross, Control.PRESET_CENTER, Vector2.ZERO, GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH)
	UiParts.sized(cross)
	aim.name = "Aim"
	aim.theme_type_variation = &"ToyChipPlate"
	var below := Vector2(0, AIM_BELOW)
	_pin(aim, Control.PRESET_CENTER, below, GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH)
	aim_label.name = "Text"
	aim.add_child(aim_label)
	raising.name = "Raising"
	raising.theme_type_variation = &"ToyPlate"
	_pin(raising, Control.PRESET_CENTER, below, GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH)
	raising_bar.name = "Bar"
	raising_bar.theme_type_variation = &"ToyBarProgress"
	raising_bar.custom_minimum_size = RAISE_BAR
	_fraction_bar(raising_bar)
	raising.add_child(raising_bar)


func _build_notice() -> void:
	notice.name = "Notice"
	notice.theme_type_variation = &"ToyChipPlate"
	var at := Vector2(0, NOTICE_TOP)
	_pin(notice, Control.PRESET_CENTER_TOP, at, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	notice_label.name = "Text"
	notice_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	notice.add_child(notice_label)


func _build_vitals() -> void:
	vitals.name = "Vitals"
	vitals.theme_type_variation = &"ToyRowTwentyFour"
	var corner := Vector2(EDGE, -EDGE)
	_pin(vitals, Control.PRESET_BOTTOM_LEFT, corner, GROW_DIRECTION_END, GROW_DIRECTION_BEGIN)
	suit.name = "Suit"
	suit.theme_type_variation = &"ToyPlate"
	suit.size_flags_vertical = Control.SIZE_SHRINK_END
	vitals.add_child(suit)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.theme_type_variation = &"ToyColumnEight"
	suit.add_child(rows)
	var title := UiParts.styled_label("hud.suit", &"ToyKicker")
	title.name = "Title"
	title.uppercase = true
	rows.add_child(title)
	_pips_row(rows, health_box, "Health", health_label, health)
	var stamina_label := UiParts.styled_label("hud.stamina", &"ToyHudCaption")
	_pips_row(rows, stamina_box, "Stamina", stamina_label, stamina)
	mic.name = "Mic"
	mic.theme_type_variation = &"ToyMic"
	mic.size_flags_vertical = Control.SIZE_SHRINK_END
	UiParts.sized(mic)
	mic_icon.name = "Icon"
	mic_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mic_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mic_icon.custom_minimum_size = MIC_ICON
	_icon(mic_icon)
	mic.add_child(mic_icon)
	vitals.add_child(mic)


## A pips row `box` named `box_name` in `rows`: its caption `label` (150 px) and its pips.
func _pips_row(
	rows: VBoxContainer, box: HBoxContainer, box_name: String, label: Label, pips: ToyPips
) -> void:
	box.name = box_name
	box.theme_type_variation = &"ToyRowSixteen"
	label.name = "Label"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size = Vector2(CAPTION_WIDTH, 0)
	box.add_child(label)
	box.add_child(pips)
	rows.add_child(box)


func _build_slots() -> void:
	slots.name = "Slots"
	slots.theme_type_variation = &"ToyRowSixteen"
	var corner := Vector2(-SLOTS_EDGE, -SLOTS_EDGE)
	_pin(slots, Control.PRESET_BOTTOM_RIGHT, corner, GROW_DIRECTION_BEGIN, GROW_DIRECTION_BEGIN)
	for place: HudSlot in places:
		place.light(place == hand)
		slots.add_child(place)


func _build_cops() -> void:
	cops.name = "Cops"
	cops.theme_type_variation = &"ToyPlateBanner"
	cops.visible = false
	var down := Vector2(0, COPS_DOWN)
	_pin(cops, Control.PRESET_CENTER_TOP, down, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnFour"
	cops.add_child(column)
	var title := UiParts.styled_label("hud.cops.title", &"ToyPlateAlertTitle")
	title.name = "Title"
	var arrive := UiParts.styled_label("hud.cops.in", &"ToyPlateAlertText")
	arrive.name = "In"
	cops_count.name = "Count"
	cops_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for label: Label in [title, arrive, cops_count]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)


## A 0-to-1 bar with no percentage.
static func _fraction_bar(bar: ProgressBar) -> void:
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false


## An icon drawn at its node's size, its aspect kept.
static func _icon(icon: TextureRect) -> void:
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


## `root` and every Control under it ignore the mouse and take no focus.
static func _ignore_input(root: Control) -> void:
	for node: Node in root.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.focus_mode = Control.FOCUS_NONE


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
