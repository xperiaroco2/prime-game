class_name LobbyHud
extends Control
## The lobby's HUD in the Toy style (#495, #1571; ARCHITECTURE §4.7.47): the UI handoff's tree,
## node for node (prime-game-ui `ui-2.5.4` `docs/handoff/s04-lobby.md`), drawing what LobbyText
## says, thin and calm over the ship (px at the 1920x1080 base, #287); the name plates are
## GameUi's `Plates` under it (#257), as in the round:
## - `Cross` (centre): the crosshair.
## - `Aim` (under the crosshair, as the round HUD's; not in the handoff, #1408, #1411): the name of
##   the item E picks up or of the station E uses there (the bar's tap), HudText.aim_of, or, while
##   E would hand the hand item to the living player under the crosshair, the hand-over's cue
##   (HudText.hand_over_cue; the bar's mug to a friend); hidden when empty.
## - `Status` (top centre, 36 px down, 360 x 66 at least): `Row` > `Text` (the ready count, what the
##   host says holds the start back, #548, or the countdown, all in the same calm text) and `Pips`,
##   one per player, the ready ones full and first (hidden while the plate says what is missing).
## - `Players` (top right, 36 px in, 330 px): the roster as in the round, `Rows` > `Head` (the
##   count of the limit in small capitals), then one row per player, the host first: `Dot` (the body
##   colour), `Name` (the own "Zinga (you)", cut with an ellipsis), the host's `HostTag`, `Ready`
##   (a full pip while ready).
## - `Bottom` (bottom left, 36 px in): `Hint` (the Esc key and "Menu", only with no session: the
##   ship at the boot, #1285), `Ready` (a pip and "Ready: yes/no") and `Mic` (on: `mic` tinted
##   `icon_on`; off: `mic-off` tinted `icon_off`). Above it, beyond the handoff, the voice hint
##   until a microphone is picked (M5-6).
## The lobby's name and the code are not on this HUD (the handoff): the code is the Esc menu's head
## (s05). Ready is the bound `ready` key (F by default, #211). Styled only through the shared
## theme's variations (no override; size constants read into `custom_minimum_size` with
## UiParts.sized); every node ignores the mouse and takes no focus. Texts are deck keys (#208);
## names and the counts are data (`auto_translate_mode` DISABLED, written again on a language
## change). It reads nothing itself: the game feeds it.

## The HUD's distances from the screen's edges and the plates' fixed sizes, px (the handoff).
const EDGE := 36
const STATUS_SIZE := Vector2(360, 66)
const PLAYERS_WIDTH := 330
const MIC_ICON := Vector2(42, 42)
## The voice hint's gap above the bottom row (layout; the hint is the game's, not the handoff's).
const VOICE_GAP := 16
## The pips: ready (the suit's health pip) and not.
const PIP_ON := &"ToyPipHealth"
const PIP_OFF := &"ToyPip"

var cross := Panel.new()
## Aim (show_aim(), show_hand_over()): the round HUD's chip; an item's or station's deck key
## translated by the label, or the hand-over's cue written in code (#1411).
var aim := PanelContainer.new()
var aim_label := UiParts.styled_label("", &"ToyChipPlateText")
var status := PanelContainer.new()
var status_label := UiParts.styled_label("", &"ToyPlateText")
var status_pips := HBoxContainer.new()
var players := PanelContainer.new()
var rows := VBoxContainer.new()
var head_label := UiParts.styled_label("", &"ToyKicker")
var bottom := HBoxContainer.new()
## The boot's hint (show_hint()): the menu key and its word; hidden in a session.
var hint := PanelContainer.new()
var hint_key := PanelContainer.new()
var hint_key_label := UiParts.styled_label("", &"ToyKeyText")
## The voice hint (show_voice_hint()); hidden when empty. Not in the handoff (M5-6's hint kept).
var voice_hint := PanelContainer.new()
var voice_label := UiParts.styled_label("", &"ToyChipPlateText")
var ready_tile := PanelContainer.new()
var ready_pip := Panel.new()
var ready_label := UiParts.styled_label(LobbyText.READY_NO_KEY, &"ToyPlateText")
var mic := PanelContainer.new()
var mic_icon := TextureRect.new()

## The last state shown (a language change writes its texts again).
var _shown := LobbyText.Shown.new()
## The rows' value when they were built: a join, a leave, a rename or a ready rebuilds them.
var _rows_key := ""
## Each row's name label and ready pip, in the rows' order.
var _row_names: Array[Label] = []
var _row_pips: Array[Panel] = []
var _mic_on := false
## The interact key's label in the hand-over's cue; "" for none.
var _hand_over_key := ""
var _hand_over_cue_key := ""
## Aim's text from show_aim(): a deck key or a name; "" for none.
var _aim_text := ""
## The own ship with no session (set_ship()).
var _ship := false


func _init() -> void:
	name = "LobbyHud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_cross()
	_build_aim()
	_build_status()
	_build_players()
	_build_bottom()
	_build_voice_hint()
	_ignore_input(self)
	theme_changed.connect(_tint, CONNECT_DEFERRED)
	show_lobby(_shown)
	show_hint("")
	show_mic(false)


## Shows what `model` knows now under the client's own `mode`; `host_tick` is the newest host tick
## it knows (-1: none yet).
func refresh(model: ClientModel, mode: GameMode, host_tick: int) -> void:
	show_lobby(LobbyText.of(model, mode, host_tick))


## Shows `shown`; the rows and the pips are built again only when they changed.
func show_lobby(shown: LobbyText.Shown) -> void:
	_shown = shown
	var key := shown.rows_key()
	if key != _rows_key:
		_rows_key = key
		_build_rows(shown.rows)
		_build_status_pips(shown.rows)
	status_pips.visible = shown.status != LobbyText.Status.SHORT and not shown.rows.is_empty()
	var own_ready := shown.own_ready
	ready_pip.theme_type_variation = PIP_ON if own_ready else PIP_OFF
	ready_label.text = LobbyText.READY_YES_KEY if own_ready else LobbyText.READY_NO_KEY
	_write()


## The boot's hint with the menu key's label `key` (KeyLabel's, the binding now); "" hides it (a
## session runs). Not shown before #1285 boots into the ship.
func show_hint(key: String) -> void:
	hint_key_label.text = key
	hint.visible = not key.is_empty()


## The own ship with no session (#1285, s04 `boot`): no HUD but the hint with the bound Esc key at
## the bottom left; off: the session's HUD again.
func set_ship(on: bool) -> void:
	_ship = on
	show_hint(KeyLabel.of_action(&"ui_cancel") if on else "")
	for node: Control in [cross, status, players, ready_tile, mic]:
		node.visible = not on
	if on:
		voice_hint.visible = false


## The microphone: on while anybody may hear the own player (VoiceSender.live()).
func show_mic(on: bool) -> void:
	if on == _mic_on and mic_icon.texture != null:
		return
	_mic_on = on
	mic_icon.texture = ToyIcons.texture(&"mic" if on else &"mic-off")
	_tint()


## Whether the microphone shows on.
func shows_mic_on() -> bool:
	return _mic_on


## Aim's text under the crosshair (HudText.aim_of: a deck key, else a name); "" hides it. The
## hand-over's cue, while there is one, takes its place (show_hand_over()).
func show_aim(text: String) -> void:
	if text == _aim_text:
		return
	_aim_text = text
	_show_aim()


## The hand-over's cue in Aim with the interact key's label `key` (HandOverUse.cue(), #1411),
## worded by the deck key `cue_key` (HandOverUse.cue_key(), #1434; "" the hand-over's own);
## "" gives Aim back to show_aim()'s text.
func show_hand_over(key: String, cue_key: String = "") -> void:
	if key == _hand_over_key and cue_key == _hand_over_cue_key:
		return
	_hand_over_key = key
	_hand_over_cue_key = cue_key
	_show_aim()


## The voice hint until a microphone is picked; "" hides it, and so does the own ship (nobody
## hears there).
func show_voice_hint(text: String) -> void:
	voice_label.text = text
	voice_hint.visible = not text.is_empty() and not _ship


## The rows' names as drawn, in order (the own row's "<name> (you)").
func row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for label in _row_names:
		texts.append(label.text)
	return texts


## Whether each row shows its pip full (that player is ready), in order.
func row_checks() -> Array[bool]:
	var shown: Array[bool] = []
	for pip in _row_pips:
		shown.append(pip.theme_type_variation == PIP_ON)
	return shown


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_write()


## Aim: the hand-over's cue (set in code, data inside, again on a language change) over the
## item's or station's deck key (the label translates it).
func _show_aim() -> void:
	if _hand_over_key.is_empty():
		aim_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
		aim_label.text = _aim_text
		aim.visible = not _aim_text.is_empty()
		return
	aim_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	aim_label.text = HudText.hand_over_cue(_hand_over_key, _hand_over_cue_key)
	aim.visible = true


## The texts with placeholders and data, in the current language.
func _write() -> void:
	status_label.text = LobbyText.status_text(_shown)
	head_label.text = LobbyText.head_text(_shown)
	_show_aim()
	for index in mini(_row_names.size(), _shown.rows.size()):
		_row_names[index].text = LobbyText.row_text(_shown.rows[index])


## The rows of `shown_rows`, the host first: `Host`, the own `Self`, the others `Row<n>`, each
## `Dot`, `Name`, the host's `HostTag` and `Ready`; after `Head`.
func _build_rows(shown_rows: Array[LobbyText.Row]) -> void:
	for child: Node in rows.get_children():
		if child == head_label:
			continue
		# Freed now: nothing holds a row but the arrays cleared below.
		rows.remove_child(child)
		child.free()
	_row_names.clear()
	_row_pips.clear()
	for index in shown_rows.size():
		var row := shown_rows[index]
		var line := HBoxContainer.new()
		line.theme_type_variation = &"ToyRowTwelve"
		if row.host:
			line.name = "Host"
		elif row.own:
			line.name = "Self"
		else:
			line.name = "Row%d" % (index + 1)
		var dot := Panel.new()
		dot.name = "Dot"
		dot.theme_type_variation = &"ToyRosterDot"
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.self_modulate = row.colour
		line.add_child(UiParts.sized(dot))
		var label := UiParts.styled_label("", &"ToyRosterNameSelf" if row.own else &"ToyRosterName")
		label.name = "Name"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(label)
		if row.host:
			var tag := PanelContainer.new()
			tag.name = "HostTag"
			tag.theme_type_variation = &"ToyRosterTagHost"
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var tag_text := UiParts.styled_label(LobbyText.HOST_TAG_KEY, &"ToyRosterTagHostText")
			tag_text.name = "Text"
			tag.add_child(tag_text)
			line.add_child(tag)
		var pip := Panel.new()
		pip.name = "Ready"
		pip.theme_type_variation = PIP_ON if row.ready else PIP_OFF
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(UiParts.sized(pip))
		_ignore_input(line)
		rows.add_child(line)
		_row_names.append(label)
		_row_pips.append(pip)


## One pip per player in the status plate, the ready ones full and first.
func _build_status_pips(shown_rows: Array[LobbyText.Row]) -> void:
	for child: Node in status_pips.get_children():
		status_pips.remove_child(child)
		child.free()
	var ready_count := 0
	for row in shown_rows:
		if row.ready:
			ready_count += 1
	for index in shown_rows.size():
		var pip := Panel.new()
		pip.name = "P%d" % (index + 1)
		pip.theme_type_variation = PIP_ON if index < ready_count else PIP_OFF
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_pips.add_child(UiParts.sized(pip))


## The icons' tints: they need the theme, so once in the tree and after every theme change.
func _tint() -> void:
	if not is_inside_tree():
		return
	var colour := &"icon_on" if _mic_on else &"icon_off"
	mic_icon.self_modulate = mic_icon.get_theme_color(colour, &"ToyMic")


func _build_cross() -> void:
	cross.name = "Cross"
	cross.theme_type_variation = &"ToyCrosshair"
	_pin(cross, Control.PRESET_CENTER, Vector2.ZERO, GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH)
	UiParts.sized(cross)


func _build_aim() -> void:
	aim.name = "Aim"
	aim.theme_type_variation = &"ToyChipPlate"
	var below := Vector2(0, Hud.AIM_BELOW)
	_pin(aim, Control.PRESET_CENTER, below, GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH)
	aim_label.name = "Text"
	aim.add_child(aim_label)
	aim.visible = false


func _build_status() -> void:
	status.name = "Status"
	status.theme_type_variation = &"ToyPlate"
	status.custom_minimum_size = STATUS_SIZE
	var top := Vector2(0, EDGE)
	_pin(status, Control.PRESET_CENTER_TOP, top, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.theme_type_variation = &"ToyRowTwentyFour"
	status.add_child(row)
	status_label.name = "Text"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(status_label)
	status_pips.name = "Pips"
	status_pips.theme_type_variation = &"ToyRowFour"
	status_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status_pips)


func _build_players() -> void:
	players.name = "Players"
	players.theme_type_variation = &"ToyRoster"
	players.custom_minimum_size = Vector2(PLAYERS_WIDTH, 0)
	var corner := Vector2(-EDGE, EDGE)
	_pin(players, Control.PRESET_TOP_RIGHT, corner, GROW_DIRECTION_BEGIN, GROW_DIRECTION_END)
	rows.name = "Rows"
	rows.theme_type_variation = &"ToyColumnEight"
	players.add_child(rows)
	head_label.name = "Head"
	head_label.uppercase = true
	head_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	rows.add_child(head_label)


func _build_bottom() -> void:
	bottom.name = "Bottom"
	bottom.theme_type_variation = &"ToyRowSixteen"
	var corner := Vector2(EDGE, -EDGE)
	_pin(bottom, Control.PRESET_BOTTOM_LEFT, corner, GROW_DIRECTION_END, GROW_DIRECTION_BEGIN)
	hint.name = "Hint"
	hint.theme_type_variation = &"ToyPlate"
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(hint)
	var hint_row := HBoxContainer.new()
	hint_row.name = "Row"
	hint_row.theme_type_variation = &"ToyRowTwelve"
	hint.add_child(hint_row)
	hint_key.name = "Key"
	hint_key.theme_type_variation = &"ToyKeyOnDark"
	hint_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_row.add_child(UiParts.sized(hint_key))
	hint_key_label.name = "Text"
	hint_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_key_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hint_key.add_child(hint_key_label)
	var hint_text := UiParts.styled_label("tutorial.list.menu", &"ToyPlateTextMuted")
	hint_text.name = "Text"
	hint_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_row.add_child(hint_text)
	ready_tile.name = "Ready"
	ready_tile.theme_type_variation = &"ToyPlate"
	ready_tile.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(ready_tile)
	var ready_row := HBoxContainer.new()
	ready_row.name = "Row"
	ready_row.theme_type_variation = &"ToyRowTwelve"
	ready_tile.add_child(ready_row)
	ready_pip.name = "Pip"
	ready_pip.theme_type_variation = PIP_OFF
	ready_pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ready_row.add_child(UiParts.sized(ready_pip))
	ready_label.name = "Text"
	ready_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ready_row.add_child(ready_label)
	mic.name = "Mic"
	mic.theme_type_variation = &"ToyMic"
	mic.size_flags_vertical = Control.SIZE_SHRINK_END
	UiParts.sized(mic)
	mic_icon.name = "Icon"
	mic_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mic_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mic_icon.custom_minimum_size = MIC_ICON
	mic_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mic_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mic.add_child(mic_icon)
	bottom.add_child(mic)


## The voice hint, the game's own (M5-6), above the bottom row: its bottom VOICE_GAP over the
## mic's top, whatever the large-text theme makes the row's height.
func _build_voice_hint() -> void:
	voice_hint.name = "VoiceHint"
	voice_hint.theme_type_variation = &"ToyChipPlate"
	voice_hint.visible = false
	var corner := Vector2(EDGE, -EDGE)
	_pin(voice_hint, Control.PRESET_BOTTOM_LEFT, corner, GROW_DIRECTION_END, GROW_DIRECTION_BEGIN)
	voice_label.name = "Text"
	voice_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	voice_hint.add_child(voice_label)
	bottom.resized.connect(_place_voice_hint)


func _place_voice_hint() -> void:
	var above := -EDGE - bottom.size.y - VOICE_GAP
	voice_hint.offset_top = above
	voice_hint.offset_bottom = above


## `root` and every Control under it ignore the mouse and take no focus.
static func _ignore_input(root: Control) -> void:
	var all: Array[Node] = root.find_children("*", "Control", true, false)
	all.append(root)
	for node: Node in all:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE


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
