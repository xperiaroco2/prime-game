class_name LobbyPanel
extends VBoxContainer
## The Esc menu's Lobby tab (ARCHITECTURE §4.7, #169), in the Toy style of #491 (prime-game-ui
## handoff s05 `lobby-*` at ui-0.4.0). Presets: the preset cards (LobbyPresets; the pressed one is
## derived from the model) and Save your own, for the host; a player reads "Preset: …". Body:
## SettingList (784 px) with the lobby's name (#214), the match's map (#627, #694: under the name),
## then Settings, one row per SettingSpec of the client's own mode (a SettingStepper for a whole
## number, chips for the banned task types: selected = allowed); Side with the room's code and
## Copy (the M6 design §3 item 2) or the code service's absence, the players (scrolling rows: the
## own one "You", the host's marked, a ready check), the shortfalls that hold the start back and
## Ready. Everyone sees the settings; only the host changes them, and only in a phase that accepts
## its ChangeSettings (EscMenuState.may_change_settings): a player sees values without steppers and
## tasks as static chips. Everything shown comes from the own ClientModel and the own mode. A
## changed control sends that setting only; a preset sends every value it changes in one
## ChangeSettings (settings_changed), so the host never checks a half-applied preset.

signal ready_toggled(on: bool)
signal setting_changed(id: StringName, value: Variant)
## Several settings at once (a preset card): one ChangeSettings.
signal settings_changed(values: Dictionary)
## The host's new lobby name, LobbyName-cleaned ("" asks for the default again).
signal lobby_name_changed(text: String)
## The host's pick of the match's map, one of the own mode's maps (#627).
signal map_changed(map: String)
## Save your own: the settings now, to keep as the player's own preset.
signal preset_saved(values: Dictionary)

const NAME_LABEL := "lobby.setting.name"
## Plain text, as before: the UI deck has no key for it yet (a change goes to prime-game-ui).
const MAP_LABEL := "Map"
const DEFAULT_NAME := "lobby.default_name"
## Each known setting's row: its node name, its deck key ("": the spec's name) and the key its
## value reads with ("": the number).
const ROWS: Dictionary[StringName, Array] = {
	&"match_duration": ["Duration", "lobby.setting.duration", "unit.minutes"],
	&"packages": ["Packages", "lobby.setting.packages", ""],
	&"dissidents": ["Dissidents", "lobby.setting.dissidents", ""],
	&"knives": ["Knives", "lobby.setting.knives", ""],
	&"tasks": ["TaskCount", "", ""],
	&"banned_task_types": ["Tasks", "lobby.setting.tasks", ""],
}
## Sizes in px at the 1920x1080 base (the handoff's; layout).
const LIST_WIDTH := Vector2(784, 0)
const CARD_SIZE := Vector2(184, 96)
const CARD_MARGIN := 14.0
const SAVE_NAME_WIDTH := Vector2(120, 0)
const FIELD_WIDTH := Vector2(500, 0)
const GONE_WIDTH := Vector2(360, 0)
const CHECK_SIZE := Vector2(24, 24)
const COPIED_SECONDS := 1.5
const CHECK := preload("res://assets/ui/toy_pack/icons/check.svg")

## The room's code, as a keycap.
var code_label := UiParts.styled_label("", &"ToyKeyText")
var copy_button := Button.new()
var code_row := HBoxContainer.new()
var code_gone := UiParts.styled_label("esc.lobby.code_gone", &"ToyTextMutedOnLight")
var name_edit := LineEdit.new()
var map_picker := SettingRows.dropdown("Picker")
## The mode's setting rows.
var settings_box := VBoxContainer.new()
var presets := HBoxContainer.new()
var preset_label := UiParts.styled_label("", &"ToyTextOnLight")
var count_label := UiParts.styled_label("", &"ToyTextMutedOnLight")
var player_rows := VBoxContainer.new()
var shortfalls_label := UiParts.styled_label("", &"ToyTextMutedOnLight")
## Ready: the face of a raised ToyButtonPrimary toggle.
var ready_button: Button
## Each preset's card (the face), by LobbyPresets id.
var cards: Dictionary[StringName, Button] = {}

## Whether the settings take a change now: a read-only control that still changes sends nothing.
var _may_change := false
## Everyone's read-only view in a round: the ready marks hide.
var _in_round := false
var _mode: GameMode
var _model: ClientModel
## The own preset's values (Save your own); empty hides its card.
var _own: Dictionary = {}
var _steppers: Dictionary[StringName, SettingStepper] = {}
## Setting id -> task type id -> its toggle chip (the host's) and its plate (a player's).
var _bans: Dictionary[StringName, Dictionary] = {}
var _plates: Dictionary[StringName, Dictionary] = {}
## Setting id -> [the host's chips box, a player's plates box].
var _ban_boxes: Dictionary[StringName, Array] = {}
## The mode's maps, in the picker's order.
var _maps := PackedStringArray()
## The code Copy puts on the clipboard; empty hides the row.
var _code := ""
## The roster as the rows show it, so a frame's refresh rebuilds them only on a change.
var _roster_key := ""
## The lobby's name as the model last had it: a submit of the same name sends nothing.
var _lobby_name := ""
## A name the host sent that the model does not show yet (its SettingsChanged is a round trip
## away): the field keeps it, so it never flicks back to the old name, and a second submit of it
## sends nothing. Settled once the model's name moves off `_name_at_send` or the host may no longer
## change it.
var _pending := ""
var _awaiting := false
var _name_at_send := ""
## The timer of the latest Copy press.
var _copied_timer: SceneTreeTimer


func _init() -> void:
	name = "Lobby"
	theme_type_variation = &"ToyColumnSixteen"
	presets.name = "Presets"
	presets.theme_type_variation = &"ToyRowSixteen"
	add_child(presets)
	preset_label.name = "Preset"
	preset_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(preset_label)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.theme_type_variation = &"ToyRowThirtyTwo"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var list := VBoxContainer.new()
	list.name = "SettingList"
	list.theme_type_variation = &"ToyColumnEight"
	list.custom_minimum_size = LIST_WIDTH
	body.add_child(list)
	name_edit.name = "Field"
	name_edit.theme_type_variation = &"ToyField"
	name_edit.custom_minimum_size = FIELD_WIDTH
	name_edit.context_menu_enabled = false
	name_edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_edit.max_length = LobbyName.MAX_CHARS
	name_edit.text_submitted.connect(func(_submitted: String) -> void: _submit_name())
	name_edit.focus_exited.connect(_submit_name)
	list.add_child(SettingRows.row("Name", NAME_LABEL, name_edit))
	map_picker.item_selected.connect(_send_map)
	list.add_child(SettingRows.row("Map", MAP_LABEL, map_picker))
	settings_box.name = "Settings"
	settings_box.theme_type_variation = &"ToyColumnEight"
	list.add_child(settings_box)
	body.add_child(_build_side())


## The code line (JoinProgress.code_text) and the `code` Copy puts on the clipboard: the code row
## shows with a code; the code service's absence in its place for a code host whose service is gone.
func show_code(text: String, code: String) -> void:
	_code = code
	code_label.text = code
	code_gone.visible = text == JoinProgress.CODE_GONE
	code_row.visible = not code.is_empty() and not code_gone.visible


## Builds the cards and the settings' rows from the mode's settings, once per mode.
func set_mode(mode: GameMode) -> void:
	_mode = mode
	for child: Node in settings_box.get_children():
		settings_box.remove_child(child)
		child.free()
	_steppers.clear()
	_bans.clear()
	_plates.clear()
	_ban_boxes.clear()
	_maps = mode.maps.duplicate()
	map_picker.clear()
	for map in _maps:
		map_picker.add_item(map_name(map))
	for spec: SettingSpec in mode.settings:
		var row: Array = ROWS.get(spec.id, [String(spec.id).to_pascal_case(), "", ""])
		var key := str(row[1]) if not str(row[1]).is_empty() else spec.display_name
		if spec.is_number():
			var stepper := SettingStepper.new()
			stepper.format_key = str(row[2])
			stepper.set_bounds(spec.min_value, spec.max_value)
			stepper.show_value(spec.default_value)
			var id := spec.id
			stepper.stepped.connect(func(value: int) -> void: _send(id, value))
			_steppers[spec.id] = stepper
			var made := SettingRows.row(str(row[0]), key, stepper)
			# A setting with one allowed value (the base mode's task count) has nothing to show.
			made.visible = spec.min_value < spec.max_value
			settings_box.add_child(made)
		else:
			settings_box.add_child(_task_row(str(row[0]), key, spec.id, mode))
	_build_cards()


## The player's own preset (Save your own; UserSettings keeps it): its card shows before Save.
func set_own_preset(values: Dictionary) -> void:
	_own = values.duplicate()
	if cards.has(LobbyPresets.OWN):
		(cards[LobbyPresets.OWN].get_parent() as Control).visible = not _own.is_empty()
		_note(LobbyPresets.OWN)


## Shows what `model` knows now; `host_tick` is the newest host tick it knows (-1: none yet);
## `may_change` makes the settings editable (the host in the lobby); `in_round` is everyone's
## read-only view in a round (#491): no Ready, no ready marks, no shortfalls.
func refresh(model: ClientModel, _host_tick: int, may_change: bool, in_round := false) -> void:
	_model = model
	_may_change = may_change
	_in_round = in_round
	(ready_button.get_parent() as Control).visible = not in_round
	_refresh_players(model)
	var own: ClientModel.Member = model.roster.get(model.own_peer)
	var is_ready := own != null and own.ready
	ready_button.set_pressed_no_signal(is_ready)
	ready_button.icon = CHECK if is_ready else null
	_lobby_name = model.lobby_name
	if _awaiting and (not may_change or _lobby_name != _name_at_send):
		_awaiting = false
	var shown := _pending if _awaiting else _lobby_name
	name_edit.editable = may_change
	name_edit.placeholder_text = default_name(model)
	# Refreshed every frame: never over what the host is typing. A player's read-only field can
	# hold the focus too (a click, the keyboard), and still follows every rename.
	var typing := may_change and (name_edit.has_focus() or name_edit.is_editing())
	if not typing and name_edit.text != shown:
		name_edit.text = shown
	shortfalls_label.visible = not in_round and not model.shortfalls.is_empty()
	shortfalls_label.text = HostTextView.shortfalls(model.shortfalls)
	map_picker.disabled = not may_change or _maps.size() < 2
	# A map not in the own mode's list (none yet, before the Welcome) shows no map, never a wrong one.
	map_picker.select(_maps.find(model.map))
	for id: StringName in _steppers:
		_steppers[id].set_editable(may_change)
		if model.settings.has(id):
			_steppers[id].show_value(model.settings[id])
	for id: StringName in _bans:
		var banned: PackedStringArray = model.id_sets.get(id, PackedStringArray())
		var chips: Dictionary = _bans[id]
		(_ban_boxes[id][0] as Control).visible = may_change
		(_ban_boxes[id][1] as Control).visible = not may_change
		for task: Variant in chips:
			var allowed := not banned.has(str(task))
			SettingRows.set_pressed(chips[task] as Button, allowed)
			var plate := _plates[id][task] as PanelContainer
			plate.theme_type_variation = &"ToyChipLight" if allowed else &"ToyChipLineOnLight"
			(plate.get_child(0) as Label).theme_type_variation = (
				&"ToyChipLightText" if allowed else &"ToyChipLineOnLightText"
			)
	_show_presets()


## The roster by name, one per line, with the host and the ready flags.
static func roster_text(model: ClientModel) -> String:
	var peers: Array[int] = []
	peers.assign(model.roster.keys())
	peers.sort()
	var lines := PackedStringArray()
	for peer in peers:
		var member: ClientModel.Member = model.roster[peer]
		var marks := PackedStringArray()
		if peer == NetTransport.HOST_ID:
			marks.append("host")
		if peer == model.own_peer:
			marks.append("you")
		var who := member.name + (" (%s)" % ", ".join(marks) if not marks.is_empty() else "")
		lines.append("%s  %s" % [who, "ready" if member.ready else "not ready"])
	return "\n".join(lines)


## The lobby's name as shown: the host's, or while it is the default, `lobby.default_name` with the
## host's name in the current language (#214).
static func lobby_title(model: ClientModel) -> String:
	return model.lobby_name if not model.lobby_name.is_empty() else default_name(model)


## The default lobby name: `lobby.default_name` with the host's name, or "" while the roster has no
## host (never "'s lobby"), as ConnectingScreen.set_lobby does.
static func default_name(model: ClientModel) -> String:
	var host := model.host_name()
	if host.is_empty():
		return ""
	return String(TranslationServer.translate(DEFAULT_NAME)).format({"name": host})


## The countdown in words, or that the start waits for everyone.
static func countdown_text(model: ClientModel, host_tick: int) -> String:
	var left := GameFlow.seconds_left(model.end_tick, host_tick)
	return "Starting in %d s" % left if left >= 0 else "Waiting for everyone"


## A map's name for the picker: its scene's file name until maps have names ("House").
static func map_name(map: String) -> String:
	return map.get_file().get_basename().capitalize()


## A player's row name: the own "You", the host's marked, the others' names (data).
static func row_text(model: ClientModel, peer: int) -> String:
	if peer == model.own_peer:
		return KeyLabel.word(&"player.you")
	var member: ClientModel.Member = model.roster[peer]
	if peer == NetTransport.HOST_ID:
		return KeyLabel.word(&"lobby.host_mark").format({"name": member.name})
	return member.name


## Whether any settings control takes a change now.
func settings_editable() -> bool:
	if not map_picker.disabled:
		return true
	for id: StringName in _steppers:
		if _steppers[id].more.visible:
			return true
	for id: StringName in _bans:
		if _may_change and not (_bans[id] as Dictionary).is_empty():
			return true
	return _may_change and presets.visible


## The preset the model's settings are now (&"" for none).
func applied_preset() -> StringName:
	if _model == null or _mode == null:
		return &""
	return LobbyPresets.applied(_model.settings, _model.id_sets, _mode, _own)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and player_rows != null:
		_tint_marks()
	if what == NOTIFICATION_TRANSLATION_CHANGED and count_label != null:
		_roster_key = ""
		if _model != null:
			_refresh_players(_model)
		for preset: StringName in cards:
			_note(preset)
		_show_presets()


func _send(id: StringName, value: Variant) -> void:
	if _may_change:
		setting_changed.emit(id, value)


## A card: the preset's values that differ from the model's, in one ChangeSettings.
func _apply_preset(preset: StringName) -> void:
	if not _may_change or _model == null:
		_show_presets()
		return
	var values := LobbyPresets.values_of(preset, _mode, _own)
	var changes := LobbyPresets.changes_from(values, _model.settings, _model.id_sets)
	if not changes.is_empty():
		settings_changed.emit(changes)


func _save_preset() -> void:
	if not _may_change or _model == null:
		return
	var values := {}
	for spec: SettingSpec in _mode.settings:
		if spec.is_number():
			values[spec.id] = _model.settings.get(spec.id, spec.default_value) as int
		else:
			values[spec.id] = _model.id_sets.get(spec.id, PackedStringArray())
	set_own_preset(values)
	preset_saved.emit(values)


## The host's typed name, cleaned as the host will (the wire refuses an invisible character, so a
## pasted one must not make the send fail), sent only when it changes the lobby's name.
func _submit_name() -> void:
	if not _may_change:
		return
	var wanted := LobbyName.clean(name_edit.text)
	if name_edit.text != wanted:
		name_edit.text = wanted
	if wanted == (_pending if _awaiting else _lobby_name):
		return
	if not _awaiting:
		_name_at_send = _lobby_name
	_pending = wanted
	_awaiting = true
	lobby_name_changed.emit(wanted)


func _send_map(index: int) -> void:
	if _may_change and index >= 0 and index < _maps.size():
		map_changed.emit(_maps[index])


func _send_bans(id: StringName) -> void:
	var banned := PackedStringArray()
	var chips: Dictionary = _bans[id]
	for task: Variant in chips:
		if not (chips[task] as Button).button_pressed:
			banned.append(str(task))
	_send(id, banned)


func _copy() -> void:
	DisplayServer.clipboard_set(_code)
	copy_button.text = "esc.lobby.copied"
	if is_inside_tree():
		var timer := get_tree().create_timer(COPIED_SECONDS)
		_copied_timer = timer
		timer.timeout.connect(_end_copied.bind(timer))


## Takes the "Copied" text back, unless a later press started a timer of its own.
func _end_copied(timer: SceneTreeTimer) -> void:
	if timer == _copied_timer:
		copy_button.text = "esc.lobby.copy"


## The pressed card follows the model; the host sees the cards, a player the applied preset's name.
func _show_presets() -> void:
	var applied := applied_preset()
	for preset: StringName in cards:
		if preset != &"save":
			SettingRows.set_pressed(cards[preset], preset == applied)
	presets.visible = _may_change
	preset_label.visible = not _may_change and _model != null
	var key: String = LobbyPresets.NAME_KEYS.get(applied, "preset.custom")
	preset_label.text = tr("esc.lobby.preset").format({"preset": tr(key)})


func _refresh_players(model: ClientModel) -> void:
	var peers: Array[int] = []
	peers.assign(model.roster.keys())
	peers.sort()
	# The own row first in the own view.
	peers.erase(model.own_peer)
	if model.roster.has(model.own_peer):
		peers.push_front(model.own_peer)
	var key := "round;" if _in_round else ""
	for peer: int in peers:
		var member: ClientModel.Member = model.roster[peer]
		key += "%d:%s:%s;" % [peer, member.name, member.ready]
	if key == _roster_key:
		return
	_roster_key = key
	var total := _mode.max_players if _mode != null else peers.size()
	count_label.text = tr("lobby.player_count").format({"count": peers.size(), "total": total})
	for child: Node in player_rows.get_children():
		player_rows.remove_child(child)
		child.free()
	for peer: int in peers:
		var row := SettingRows.row("You" if peer == model.own_peer else "Player%d" % peer, "")
		var label := SettingRows.name_of(row)
		label.text = row_text(model, peer)
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var line := row.get_node(^"H")
		var mark := TextureRect.new()
		mark.name = "Ready"
		mark.texture = CHECK
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = CHECK_SIZE
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.visible = not _in_round and (model.roster[peer] as ClientModel.Member).ready
		line.add_child(mark)
		player_rows.add_child(row)
		mark.self_modulate = mark.get_theme_color(&"font_color", &"ToySettingRowText")


func _build_side() -> VBoxContainer:
	var side := VBoxContainer.new()
	side.name = "Side"
	side.theme_type_variation = &"ToyColumnSixteen"
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.name = "CodeRow"
	code_row.theme_type_variation = &"ToyRowEight"
	code_row.visible = false
	var label := UiParts.styled_label("common.code", &"ToyTextMutedOnLight")
	label.name = "Label"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_row.add_child(label)
	var keycap := PanelContainer.new()
	keycap.name = "Code"
	keycap.theme_type_variation = &"ToyKeyOnLight"
	keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiParts.sized(keycap)
	code_label.name = "Text"
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	keycap.add_child(code_label)
	code_row.add_child(keycap)
	copy_button.name = "Copy"
	copy_button.text = "esc.lobby.copy"
	copy_button.theme_type_variation = &"ToyButtonGhostOnLight"
	copy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy_button.pressed.connect(_copy)
	ToyPress.attach(copy_button)
	code_row.add_child(copy_button)
	side.add_child(code_row)
	code_gone.name = "CodeGone"
	code_gone.custom_minimum_size = GONE_WIDTH
	code_gone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_gone.visible = false
	side.add_child(code_gone)
	var players := VBoxContainer.new()
	players.name = "Players"
	players.theme_type_variation = &"ToyColumnEight"
	players.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_label.name = "Count"
	count_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	players.add_child(count_label)
	var scroll := UiParts.scroll()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players.add_child(scroll)
	player_rows.name = "Rows"
	player_rows.theme_type_variation = &"ToyColumnEight"
	player_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(player_rows)
	side.add_child(players)
	shortfalls_label.name = "Shortfalls"
	shortfalls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Worded by HostTextView in the current language (#548), every refresh: never a key itself.
	shortfalls_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	side.add_child(shortfalls_label)
	var ready_raised := UiParts.button(
		"esc.lobby.ready", Callable(), &"ToyButtonPrimary", ToyHints.LIGHT
	)
	ready_raised.name = "ReadyRaised"
	ready_button = ready_raised.face as Button
	ready_button.name = "Ready"
	ready_button.toggle_mode = true
	ready_button.toggled.connect(func(on: bool) -> void: ready_toggled.emit(on))
	side.add_child(ready_raised)
	return side


## The preset cards and Save your own, rebuilt for the mode.
func _build_cards() -> void:
	for child: Node in presets.get_children():
		presets.remove_child(child)
		child.free()
	cards.clear()
	var group := ButtonGroup.new()
	var shown: Array[StringName] = LobbyPresets.shown(_mode)
	shown.append(LobbyPresets.OWN)
	for preset: StringName in shown:
		var card := _card(preset, String(preset).to_pascal_case(), LobbyPresets.NAME_KEYS[preset])
		cards[preset].toggle_mode = true
		cards[preset].button_group = group
		cards[preset].pressed.connect(_apply_preset.bind(preset))
		presets.add_child(card)
		_note(preset)
	(cards[LobbyPresets.OWN].get_parent() as Control).visible = not _own.is_empty()
	var save := _card(&"save", "Save", "preset.save_own")
	cards[&"save"].pressed.connect(_save_preset)
	presets.add_child(save)


## A raised card face named `node_name`, its content V: the preset's Name and its Note.
func _card(preset: StringName, node_name: String, key: String) -> ToyRaised:
	var raised := UiParts.button("", Callable(), &"ToyPresetCard", ToyHints.LIGHT)
	raised.name = node_name + "Raised"
	raised.custom_minimum_size = CARD_SIZE
	var face := raised.face as Button
	face.name = node_name
	cards[preset] = face
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnFour"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = CARD_MARGIN
	column.offset_top = CARD_MARGIN
	column.offset_right = -CARD_MARGIN
	column.offset_bottom = -CARD_MARGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(column)
	var title := UiParts.styled_label(key, &"ToyPresetCardName")
	title.name = "Name"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	if preset == &"save":
		title.custom_minimum_size = SAVE_NAME_WIDTH
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return raised
	var note := UiParts.styled_label("", &"ToyPresetCardNote")
	note.name = "Note"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(note)
	for inner: Node in face.get_children(true):
		if inner is ToyToggle:
			(inner as ToyToggle).companion(note, &"ToyPresetCardNote", &"ToyPresetCardNoteSelected")
	return raised


## A card's note: its match duration.
func _note(preset: StringName) -> void:
	if not cards.has(preset) or _mode == null:
		return
	var note := cards[preset].get_node_or_null(^"V/Note") as Label
	if note == null:
		return
	var minutes := LobbyPresets.duration_of(LobbyPresets.values_of(preset, _mode, _own))
	note.text = tr("unit.minutes").format({"count": minutes}) if minutes >= 0 else ""


## The task types' row: the host's toggle chips (Allowed; selected = allowed) and a player's plates
## (Shown), both straight in the row's H, as the handoff has them.
func _task_row(row_name: String, label: String, id: StringName, mode: GameMode) -> PanelContainer:
	var allowed := HBoxContainer.new()
	allowed.name = "Allowed"
	allowed.theme_type_variation = &"ToyRowEight"
	var made := SettingRows.row(row_name, label, allowed)
	var shown := HBoxContainer.new()
	shown.name = "Shown"
	shown.theme_type_variation = &"ToyRowEight"
	shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	made.get_node(^"H").add_child(shown)
	var chips := {}
	var plates := {}
	for task: TaskType in mode.task_types:
		var key := "task." + String(task.id)
		var words := key if KeyLabel.word(StringName(key)) != key else task.display_name
		var node_name := String(task.id).to_pascal_case()
		var chip := UiParts.toggle(words, _send_bans.bind(id), &"ToyChipToggleOnLight")
		chip.name = node_name
		allowed.add_child(chip)
		chips[task.id] = chip
		var plate := PanelContainer.new()
		plate.name = node_name
		plate.theme_type_variation = &"ToyChipLight"
		var text := UiParts.styled_label(words, &"ToyChipLightText")
		text.name = "Text"
		plate.add_child(text)
		shown.add_child(plate)
		plates[task.id] = plate
	_bans[id] = chips
	_plates[id] = plates
	_ban_boxes[id] = [allowed, shown]
	return made


## The ready marks take the row text's colour (again after a theme swap such as large text).
func _tint_marks() -> void:
	for mark: Node in player_rows.find_children("Ready", "TextureRect", true, false):
		var texture := mark as TextureRect
		texture.self_modulate = texture.get_theme_color(&"font_color", &"ToySettingRowText")
