class_name LobbyHud
extends Control
## The lobby's HUD in the Toy style (#495; ARCHITECTURE §4.7.42): the UI handoff's tree, node for
## node (prime-game-ui `ui-0.4.0` `docs/handoff/s04-lobby.md`), drawing what LobbyText says. HUD
## edges sit 40 px in (px at the 1920x1080 base, #287); the name plates are GameUi's `Plates`
## under it (#257), as in the round:
## - `Cross` (centre): the crosshair.
## - `Status` (top centre): the ready count, the players still missing while the lobby has fewer
##   than the mode needs, or the countdown in ToyTitleOnDark.
## - `Players` (top right, 400 px): the lobby's name and the code row (the host and every code
##   joiner; hidden for a Direct game; "…" while the code service has not made the room, "—" once
##   it is gone), then the count and one row per player, the host first, a check on each ready one.
## - `Bottom` (bottom left): the own ready chip and the microphone (on: `mic` tinted `icon_on`;
##   off: `mic-off` tinted `icon_off`). Above them, beyond the handoff, the voice hint until a
##   microphone is picked (M5-6).
## No key prompt: Ready is the bound `ready` key (F by default, #211) and the Esc Lobby tab's
## button; Copy is in that tab too. Styled only through the shared theme's variations (no
## override; size constants read into `custom_minimum_size` with UiParts.sized); every node ignores
## the mouse and takes no focus. Texts are deck keys (#208); names, the code and the counts are data
## (`auto_translate_mode` DISABLED, written again on a language change). It reads nothing itself:
## the game feeds it.

## The code's text while the code service has not made the room, and once it is gone (the handoff).
const CODE_WAITING := "…"
const CODE_GONE := "—"
## The HUD's distance from the screen's edges and the players' plate's width, px (the handoff).
const EDGE := 40
const PLAYERS_WIDTH := 400
## The ready check's and the mic icon's size, px (the handoff).
const CHECK_SIZE := Vector2(24, 24)
const MIC_ICON := Vector2(28, 28)

var cross := Panel.new()
var status := PanelContainer.new()
var status_label := UiParts.styled_label("", &"ToyPlateText")
var players := PanelContainer.new()
var lobby_name_label := UiParts.styled_label("", &"ToyTextMutedOnDark")
var code_row := HBoxContainer.new()
var code_key := PanelContainer.new()
var code_label := UiParts.styled_label("", &"ToyKeyText")
var head_label := UiParts.styled_label("", &"ToyTextOnDark")
var rows := VBoxContainer.new()
var bottom := VBoxContainer.new()
## The voice hint (show_voice_hint()); hidden when empty. Not in the handoff (M5-6's hint kept).
var voice_hint := PanelContainer.new()
var voice_label := UiParts.styled_label("", &"ToyChipPlateText")
var ready_chip := PanelContainer.new()
var ready_label := UiParts.styled_label(LobbyText.READY_NO_KEY, &"ToyChipPlateText")
var mic := PanelContainer.new()
var mic_icon := TextureRect.new()

## The last state shown (a language change writes its texts again).
var _shown := LobbyText.Shown.new()
## The rows' value when they were built: a join, a leave, a rename or a ready rebuilds them.
var _rows_key := ""
## Each row's name label and ready check, in the rows' order.
var _row_names: Array[Label] = []
var _row_checks: Array[TextureRect] = []
var _mic_on := false


func _init() -> void:
	name = "LobbyHud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_cross()
	_build_status()
	_build_players()
	_build_bottom()
	_ignore_input(self)
	theme_changed.connect(_tint, CONNECT_DEFERRED)
	show_lobby(_shown)
	show_code("", false, false)
	show_mic(false)


## Shows what `model` knows now under the client's own `mode`; `host_tick` is the newest host tick
## it knows (-1: none yet).
func refresh(model: ClientModel, mode: GameMode, host_tick: int) -> void:
	show_lobby(LobbyText.of(model, mode, host_tick))


## Shows `shown`; the rows are built again only when they changed.
func show_lobby(shown: LobbyText.Shown) -> void:
	_shown = shown
	var counting := shown.status == LobbyText.Status.COUNTDOWN
	status_label.theme_type_variation = &"ToyTitleOnDark" if counting else &"ToyPlateText"
	var key := shown.rows_key()
	if key != _rows_key:
		_rows_key = key
		_build_rows(shown.rows)
	var own_ready := shown.own_ready
	ready_chip.theme_type_variation = &"ToyChipLight" if own_ready else &"ToyChipPlate"
	ready_label.theme_type_variation = &"ToyChipLightText" if own_ready else &"ToyChipPlateText"
	ready_label.text = LobbyText.READY_YES_KEY if own_ready else LobbyText.READY_NO_KEY
	_write()


## The room's code to whoever knows it: `code`, else CODE_GONE when its service is `gone`, else
## CODE_WAITING for a host `waiting` for its service to make the room; no code row for a Direct
## game (none of them).
func show_code(code: String, gone: bool, waiting: bool) -> void:
	var text := code
	if gone:
		text = CODE_GONE
	elif code.is_empty() and waiting:
		text = CODE_WAITING
	code_label.text = text
	code_row.visible = not text.is_empty()


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


## The voice hint until a microphone is picked; "" hides it.
func show_voice_hint(text: String) -> void:
	voice_label.text = text
	voice_hint.visible = not text.is_empty()


## The rows' names as drawn, in order (the own row's `player.you` translated).
func row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for label in _row_names:
		texts.append(label.atr(label.text))
	return texts


## Whether each row shows its check, in order.
func row_checks() -> Array[bool]:
	var shown: Array[bool] = []
	for check in _row_checks:
		shown.append(check.visible)
	return shown


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_write()


## The texts with placeholders and data, in the current language.
func _write() -> void:
	status_label.text = LobbyText.status_text(_shown)
	lobby_name_label.text = LobbyText.title_text(_shown)
	head_label.text = LobbyText.head_text(_shown)
	for index in mini(_row_names.size(), _shown.rows.size()):
		var row := _shown.rows[index]
		# The own row's `player.you` is a plain key: it translates itself.
		_row_names[index].text = LobbyText.YOU_KEY if row.own else LobbyText.row_text(row)


## The rows of `shown_rows`, the host first: `HostRow`, the own `OwnRow`, the others `Row<n>`.
func _build_rows(shown_rows: Array[LobbyText.Row]) -> void:
	for child: Node in rows.get_children():
		# Freed now: nothing holds a row but the arrays cleared below.
		rows.remove_child(child)
		child.free()
	_row_names.clear()
	_row_checks.clear()
	for index in shown_rows.size():
		var row := shown_rows[index]
		var line := HBoxContainer.new()
		line.theme_type_variation = &"ToyRowTwelve"
		if row.host:
			line.name = "HostRow"
		elif row.own:
			line.name = "OwnRow"
		else:
			line.name = "Row%d" % (index + 1)
		var label := UiParts.styled_label("", &"ToyTextOnDark")
		label.name = "Name"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cut(label)
		if not row.own:
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		line.add_child(label)
		var check := _icon(TextureRect.new(), "Ready", CHECK_SIZE)
		check.texture = ToyIcons.texture(&"check")
		check.visible = row.ready
		line.add_child(check)
		_ignore_input(line)
		rows.add_child(line)
		_row_names.append(label)
		_row_checks.append(check)
	_tint()


## The icons' tints: they need the theme, so once in the tree and after every theme change.
func _tint() -> void:
	if not is_inside_tree():
		return
	var colour := &"icon_on" if _mic_on else &"icon_off"
	mic_icon.self_modulate = mic_icon.get_theme_color(colour, &"ToyMic")
	for check in _row_checks:
		check.self_modulate = check.get_theme_color(&"font_color", &"ToyTextOnDark")


func _build_cross() -> void:
	cross.name = "Cross"
	cross.theme_type_variation = &"ToyCrosshair"
	_pin(cross, Control.PRESET_CENTER, Vector2.ZERO, GROW_DIRECTION_BOTH, GROW_DIRECTION_BOTH)
	UiParts.sized(cross)


func _build_status() -> void:
	status.name = "Status"
	status.theme_type_variation = &"ToyPlate"
	var top := Vector2(0, EDGE)
	_pin(status, Control.PRESET_CENTER_TOP, top, GROW_DIRECTION_BOTH, GROW_DIRECTION_END)
	status_label.name = "Text"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	status.add_child(status_label)


func _build_players() -> void:
	players.name = "Players"
	players.theme_type_variation = &"ToyPlate"
	players.custom_minimum_size = Vector2(PLAYERS_WIDTH, 0)
	var corner := Vector2(-EDGE, EDGE)
	_pin(players, Control.PRESET_TOP_RIGHT, corner, GROW_DIRECTION_BEGIN, GROW_DIRECTION_END)
	var column := _column("V", &"ToyColumnSixteen")
	players.add_child(column)
	var info := _column("Info", &"ToyColumnEight")
	column.add_child(info)
	lobby_name_label.name = "LobbyName"
	lobby_name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_cut(lobby_name_label)
	info.add_child(lobby_name_label)
	code_row.name = "CodeRow"
	code_row.theme_type_variation = &"ToyRowEight"
	info.add_child(code_row)
	var caption := UiParts.styled_label("common.code", &"ToyTextMutedOnDark")
	caption.name = "Label"
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_row.add_child(caption)
	code_key.name = "Code"
	code_key.theme_type_variation = &"ToyKeyOnDark"
	code_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# `min_width` follows the text size (36, 42 at large text): read again on every theme change.
	UiParts.sized(code_key)
	code_row.add_child(code_key)
	code_label.name = "Text"
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	code_key.add_child(code_label)
	var list := _column("List", &"ToyColumnEight")
	column.add_child(list)
	head_label.name = "Head"
	head_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	list.add_child(head_label)
	rows.name = "Rows"
	rows.theme_type_variation = &"ToyColumnEight"
	list.add_child(rows)


func _build_bottom() -> void:
	bottom.name = "Bottom"
	bottom.theme_type_variation = &"ToyColumnTwelve"
	var corner := Vector2(EDGE, -EDGE)
	_pin(bottom, Control.PRESET_BOTTOM_LEFT, corner, GROW_DIRECTION_END, GROW_DIRECTION_BEGIN)
	voice_hint.name = "VoiceHint"
	voice_hint.theme_type_variation = &"ToyChipPlate"
	voice_hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	voice_hint.visible = false
	voice_label.name = "Text"
	voice_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	voice_hint.add_child(voice_label)
	bottom.add_child(voice_hint)
	ready_chip.name = "ReadyChip"
	ready_chip.theme_type_variation = &"ToyChipPlate"
	ready_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ready_label.name = "Text"
	ready_chip.add_child(ready_label)
	bottom.add_child(ready_chip)
	mic.name = "Mic"
	mic.theme_type_variation = &"ToyMic"
	mic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiParts.sized(mic)
	_icon(mic_icon, "Icon", MIC_ICON)
	mic_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mic.add_child(mic_icon)
	bottom.add_child(mic)


## A column `column_name` of the spacing variation `variation`.
static func _column(column_name: String, variation: StringName) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = column_name
	column.theme_type_variation = variation
	return column


## `icon`, named `icon_name`, `icon_size` big and fitting its texture, centred (a pack icon).
static func _icon(icon: TextureRect, icon_name: String, icon_size: Vector2) -> TextureRect:
	icon.name = icon_name
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.custom_minimum_size = icon_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


## A name cut with an ellipsis where its plate ends.
static func _cut(label: Label) -> void:
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


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
