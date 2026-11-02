class_name LifeScreen
extends Control
## The downed, dead and respawn screen in the Toy style (#497, #1570; ARCHITECTURE §4.7.41): the UI
## handoff's plates, node for node (prime-game-ui `ui-2.5.4` `docs/handoff/s09-downed.md`), drawing
## what LifeHud says, on the round's HUD (Hud, #489), which hides and returns its own nodes from
## HudText. Px at the 1920x1080 base (#287):
## - `Downed` (top centre, 228 px down, 900 px wide): the title, the bleed-out bar
##   (ToyBarReturnCalm, ToyBarReturnAlarm under health's alarm line 0.3) and the time left; while
##   raised, "<name> is raising you" and the raise's bar in place of the bar and the time.
## - `GiveUp` (bottom centre, 192 px up): the deck's sentence in pieces around the keycap of the
##   give-up key bound now, and the hold's bar, empty at rest so the plate never changes size;
##   hidden while raised.
## - `Spectate` (top centre, 36 px down, while dead): the game's plate (the handoff draws a dead's
##   room the game has not, #1570) in the handoff's DeadTop tile: "Back in" and the time to respawn
##   as the tile's Return row, then whom the player watches.
## - `Protect` (165 px down, 39 px under the anger meter): the respawn's protection, 3, 2, 1, then
##   hidden.
## Styled only through the shared theme's variations (no override; the keycap's `min_width`, or
## `wide_min_width` for a wide key such as Space, read into `custom_minimum_size` as UiParts.sized
## does, again after the large-text swap and a rebind); every node
## ignores the mouse and takes no focus. Texts are set from code (`auto_translate_mode` DISABLED)
## and written again on NOTIFICATION_TRANSLATION_CHANGED (#208). It reads nothing itself: the game
## feeds it.

## The plates' places and the fixed sizes the handoff gives (px; layout, not style).
const DOWNED_TOP := 228
const DOWNED_WIDTH := 900
const GIVE_UP_BOTTOM := -192
const SPECTATE_TOP := 36
const PROTECT_TOP := 165
const LINE_WIDTH := 810
const LINE_BAR := Vector2(LINE_WIDTH, 24)
const HOLD_BAR := Vector2(540, 24)
## The spacer under a bar that ends a plate (the handoff's `Pad`).
const PAD := Vector2(0, 6)
## The bleed-out bar's variations: calm, and alarm under health's alarm line.
const BLEED_CALM := &"ToyBarReturnCalm"
const BLEED_ALARM := &"ToyBarReturnAlarm"
const BLEED_ALARM_LINE := 0.3

var downed := PanelContainer.new()
var title_label := UiParts.styled_label("", &"ToyPlateTitle")
var bleed := ProgressBar.new()
var left_label := UiParts.styled_label("", &"ToyPlateTextMuted")
var raise_bar := ProgressBar.new()
var raise_pad := Control.new()
var give_up := PanelContainer.new()
var before_label := UiParts.styled_label("", &"ToyPlateText")
var key := PanelContainer.new()
var key_label := UiParts.styled_label("", &"ToyKeyText")
var after_label := UiParts.styled_label("", &"ToyPlateText")
var hold_bar := ProgressBar.new()
var spectate := PanelContainer.new()
## The DeadTop tile's Return row: "Back in" and the time to respawn.
var respawn_row := HBoxContainer.new()
var back_in_label := UiParts.styled_label("", &"ToyHudCaption")
var respawn_label := UiParts.styled_label("", &"ToyTimer")
var watching_label := UiParts.styled_label("", &"ToyPlateText")
var protect := PanelContainer.new()
var protect_label := UiParts.styled_label("", &"ToyChipLightText")
## The last state shown (a translation change writes its texts again).
var _shown := LifeHud.Shown.new()
## Whether the keycap has the wide size (the bound give_up key's, ARCHITECTURE §4.7.30 rule 7).
var _key_wide := false


func _init() -> void:
	name = "LifeScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_downed()
	_build_give_up()
	_build_spectate()
	_build_protect()
	for label: Label in [
		title_label,
		left_label,
		before_label,
		key_label,
		after_label,
		back_in_label,
		respawn_label,
		watching_label,
		protect_label,
	]:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for node: Node in find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	show_hud(_shown)


## Shows `shown`.
func show_hud(shown: LifeHud.Shown) -> void:
	_shown = shown
	var down := shown.state == LifeHud.State.DOWN
	var raised := shown.state == LifeHud.State.RAISE
	downed.visible = down or raised
	bleed.visible = down
	left_label.visible = down
	bleed.value = shown.bleed
	var alarm := down and shown.bleed < BLEED_ALARM_LINE
	bleed.theme_type_variation = BLEED_ALARM if alarm else BLEED_CALM
	raise_bar.visible = raised
	raise_pad.visible = raised
	raise_bar.value = shown.raise
	give_up.visible = down
	key_label.text = shown.give_up_key
	if shown.give_up_wide != _key_wide:
		_key_wide = shown.give_up_wide
		_size_key()
	hold_bar.value = shown.give_up
	spectate.visible = shown.state == LifeHud.State.DEAD
	respawn_row.visible = not shown.respawn.is_empty()
	watching_label.visible = not shown.watching.is_empty()
	protect.visible = shown.protected > 0
	_write()


## The give-up line as drawn: its shown pieces around the key, joined by spaces.
func give_up_text() -> String:
	var words := PackedStringArray()
	for label: Label in [before_label, key_label, after_label]:
		if label.visible and not label.text.is_empty():
			words.append(label.text)
	return " ".join(words)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_write()


## The keycap's width from its variation: `wide_min_width` for a wide key, else `min_width`.
func _size_key() -> void:
	if key.is_inside_tree():
		key.custom_minimum_size.x = UiParts.size_of(key, _key_wide).x


## The texts with data: each a deck key through tr(), then its data.
func _write() -> void:
	if _shown.state == LifeHud.State.RAISE:
		title_label.text = tr("downed.raised_by").format({"name": _shown.raiser})
	else:
		title_label.text = tr("downed.title")
	left_label.text = tr("downed.time_left").format({"time": _shown.time_left})
	var pieces := LifeHud.give_up_pieces(tr("downed.give_up_hold"))
	before_label.text = pieces[0]
	before_label.visible = not pieces[0].is_empty()
	after_label.text = pieces[1]
	after_label.visible = not pieces[1].is_empty()
	back_in_label.text = tr("dead.back_in")
	respawn_label.text = _shown.respawn
	watching_label.text = tr("dead.watching").format({"name": _shown.watching})
	protect_label.text = tr("respawn.protected").format({"count": str(_shown.protected)})


func _build_downed() -> void:
	downed.name = "Downed"
	downed.theme_type_variation = &"ToyPlate"
	downed.custom_minimum_size = Vector2(DOWNED_WIDTH, 0)
	var top := Vector2(0, DOWNED_TOP)
	_pin(downed, Control.PRESET_CENTER_TOP, top, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	var column := _column(downed, &"ToyColumnTwelve")
	title_label.name = "Title"
	title_label.custom_minimum_size = Vector2(LINE_WIDTH, 0)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title_label)
	bleed.name = "Bleed"
	bleed.custom_minimum_size = LINE_BAR
	column.add_child(_bar(bleed))
	bleed.theme_type_variation = BLEED_CALM
	left_label.name = "Left"
	left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(left_label)
	raise_bar.name = "Raise"
	raise_bar.custom_minimum_size = LINE_BAR
	column.add_child(_bar(raise_bar))
	raise_pad.name = "Pad"
	raise_pad.custom_minimum_size = PAD
	column.add_child(raise_pad)


func _build_give_up() -> void:
	give_up.name = "GiveUp"
	give_up.theme_type_variation = &"ToyPlate"
	var bottom := Vector2(0, GIVE_UP_BOTTOM)
	_pin(give_up, Control.PRESET_CENTER_BOTTOM, bottom, GROW_DIRECTION_BOTH, GROW_DIRECTION_BEGIN)
	var column := _column(give_up, &"ToyColumnTwelve")
	var line := HBoxContainer.new()
	line.name = "Line"
	line.theme_type_variation = &"ToyRowEight"
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(line)
	before_label.name = "Before"
	before_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(before_label)
	key.name = "Key"
	key.theme_type_variation = &"ToyKeyOnDark"
	# UiParts.sized() with a width that follows the binding: read again after every theme change
	# (deferred, for sized()'s cache reason) and when show_hud() is given a key of the other width.
	key.theme_changed.connect(_size_key, CONNECT_DEFERRED)
	line.add_child(key)
	key_label.name = "Text"
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.add_child(key_label)
	after_label.name = "After"
	after_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(after_label)
	hold_bar.name = "Hold"
	hold_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hold_bar.custom_minimum_size = HOLD_BAR
	column.add_child(_bar(hold_bar))
	var pad := Control.new()
	pad.name = "Pad"
	pad.custom_minimum_size = PAD
	column.add_child(pad)


func _build_spectate() -> void:
	spectate.name = "Spectate"
	spectate.theme_type_variation = &"ToyPlate"
	var top := Vector2(0, SPECTATE_TOP)
	_pin(spectate, Control.PRESET_CENTER_TOP, top, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	var column := _column(spectate, &"ToyColumnFour")
	respawn_row.name = "Return"
	respawn_row.theme_type_variation = &"ToyRowSixteen"
	respawn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(respawn_row)
	back_in_label.name = "Label"
	back_in_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	respawn_row.add_child(back_in_label)
	respawn_label.name = "Time"
	respawn_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	respawn_row.add_child(respawn_label)
	watching_label.name = "Watching"
	watching_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(watching_label)


func _build_protect() -> void:
	protect.name = "Protect"
	protect.theme_type_variation = &"ToyChipLight"
	var top := Vector2(0, PROTECT_TOP)
	_pin(protect, Control.PRESET_CENTER_TOP, top, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	protect_label.name = "Text"
	protect.add_child(protect_label)


## A ToyBarProgress bar from 0 to 1 with no percentage text.
static func _bar(bar: ProgressBar) -> ProgressBar:
	bar.theme_type_variation = &"ToyBarProgress"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	return bar


## A plate's column `V` of the spacing `variation`, added to `plate`.
static func _column(plate: PanelContainer, variation: StringName) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = variation
	plate.add_child(column)
	return column


## Adds `node` anchored at `preset` with all four offsets at `at` (a point: the node takes its
## minimum size, growing as `grow_x` and `grow_y` say).
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
