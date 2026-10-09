class_name LobbyPanel
extends VBoxContainer
## The Esc menu's Lobby tab (ARCHITECTURE §4.7, #169): the roster with ready flags, the countdown,
## the Ready toggle, the match's map (one of the mode's maps, #627), and one control per SettingSpec
## of the client's own mode (a whole number within its bounds, or check boxes for the banned task
## types) with the shortfalls that hold the start back. Everyone sees the settings; only the host
## changes them, and only in a phase that accepts its ChangeSettings
## (EscMenuState.may_change_settings): for everyone else they are read-only.
## Everything shown comes from the own ClientModel and the own mode. A changed control sends that
## setting only. The room's code with Copy, to whoever knows it (the M6 design §3 item 2). The
## lobby's name (#214): the host edits it (sent when submitted or left, cleaned, only when it
## differs), everyone else reads it; empty shows the default as its placeholder. The map's picker
## sits right under the name, the two things that name the match (#694).

signal ready_toggled(on: bool)
signal setting_changed(id: StringName, value: Variant)
## The host's new lobby name, LobbyName-cleaned ("" asks for the default again).
signal lobby_name_changed(text: String)
## The host's pick of the match's map, one of the own mode's maps (#627).
signal map_changed(map: String)

const READ_ONLY := "The settings below: only the host changes them, in the lobby."
const NAME_LABEL := "lobby.setting.name"
## Plain text, as "Settings": the UI deck has no key for it yet (a change goes to prime-game-ui).
const MAP_LABEL := "Map"
const DEFAULT_NAME := "lobby.default_name"

var code_label := Label.new()
var copy_button := Button.new()
var name_edit := LineEdit.new()
var roster_label := Label.new()
var countdown_label := Label.new()
var ready_button := Button.new()
var settings_box := VBoxContainer.new()
var read_only_label := Label.new()
var shortfalls_label := Label.new()
## The map choice, under the lobby's name; its items rebuilt by set_mode.
var map_picker := OptionButton.new()

## Whether the settings take a change now: a read-only control that still changes sends nothing.
var _may_change := false
var _numbers: Dictionary[StringName, SpinBox] = {}
## Setting id -> task type id -> its check box.
var _bans: Dictionary[StringName, Dictionary] = {}
## The mode's maps, in the picker's order.
var _maps := PackedStringArray()
## The code Copy puts on the clipboard; empty hides the row.
var _code := ""
var _code_row := HBoxContainer.new()
## The lobby's name as the model last had it: a submit of the same name sends nothing.
var _lobby_name := ""
## A name the host sent that the model does not show yet (its SettingsChanged is a round trip
## away): the field keeps it, so it never flicks back to the old name, and a second submit of it
## sends nothing. Settled once the model's name moves off `_name_at_send` or the host may no longer
## change it.
var _pending := ""
var _awaiting := false
var _name_at_send := ""


func _init() -> void:
	name = "LobbyPanel"
	theme_type_variation = &"EscPage"
	_code_row.add_child(code_label)
	copy_button.text = "Copy"
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(_code))
	_code_row.add_child(copy_button)
	_code_row.visible = false
	add_child(_code_row)
	name_edit.max_length = LobbyName.MAX_CHARS
	name_edit.text_submitted.connect(func(_submitted: String) -> void: _submit_name())
	name_edit.focus_exited.connect(_submit_name)
	add_child(UiParts.labelled(NAME_LABEL, name_edit))
	map_picker.item_selected.connect(_send_map)
	add_child(UiParts.labelled(MAP_LABEL, map_picker))
	add_child(roster_label)
	add_child(countdown_label)
	ready_button.toggle_mode = true
	ready_button.text = "Ready"
	ready_button.toggled.connect(func(on: bool) -> void: ready_toggled.emit(on))
	add_child(ready_button)
	read_only_label.text = READ_ONLY
	read_only_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(read_only_label)
	add_child(settings_box)
	shortfalls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shortfalls_label.theme_type_variation = &"Shortfalls"
	add_child(shortfalls_label)


## The code line (JoinProgress.code_text) and the `code` Copy puts on the clipboard; Copy shows
## only with a code, the row only with a line.
func show_code(text: String, code: String) -> void:
	_code = code
	code_label.text = text
	copy_button.visible = not code.is_empty()
	_code_row.visible = not text.is_empty()


## Builds the settings' controls from the mode's settings, once per mode.
func set_mode(mode: GameMode) -> void:
	for child: Node in settings_box.get_children():
		child.queue_free()
	_numbers.clear()
	_bans.clear()
	settings_box.add_child(UiParts.heading("Settings"))
	_maps = mode.maps.duplicate()
	map_picker.clear()
	for map in _maps:
		map_picker.add_item(map_name(map))
	for spec: SettingSpec in mode.settings:
		var id := spec.id
		if spec.is_number():
			var box := SpinBox.new()
			box.min_value = spec.min_value
			box.max_value = spec.max_value
			box.value = spec.default_value
			box.value_changed.connect(func(value: float) -> void: _send(id, int(value)))
			_numbers[id] = box
			settings_box.add_child(UiParts.labelled(spec.display_name, box))
			continue
		var boxes: Dictionary[StringName, CheckBox] = {}
		settings_box.add_child(_text(spec.display_name))
		for task: TaskType in mode.task_types:
			var check := CheckBox.new()
			check.text = task.display_name
			check.toggled.connect(func(_on: bool) -> void: _send(id, _banned(id)))
			boxes[task.id] = check
			settings_box.add_child(check)
		_bans[id] = boxes


## Shows what `model` knows now; `host_tick` is the newest host tick it knows (-1: none yet);
## `may_change` makes the settings editable (the host in the lobby).
func refresh(model: ClientModel, host_tick: int, may_change: bool) -> void:
	roster_label.text = roster_text(model)
	var own: ClientModel.Member = model.roster.get(model.own_peer)
	var is_ready := own != null and own.ready
	ready_button.set_pressed_no_signal(is_ready)
	ready_button.text = "Ready (press again to cancel)" if is_ready else "Ready"
	countdown_label.text = countdown_text(model, host_tick)
	_may_change = may_change
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
	read_only_label.visible = not may_change
	shortfalls_label.visible = not model.shortfalls.is_empty()
	shortfalls_label.text = "\n".join(model.shortfalls)
	map_picker.disabled = not may_change or _maps.size() < 2
	# A map not in the own mode's list (none yet, before the Welcome) shows no map, never a wrong one.
	map_picker.select(_maps.find(model.map))
	for id: StringName in _numbers:
		var box := _numbers[id]
		box.editable = may_change
		if model.settings.has(id):
			box.set_value_no_signal(model.settings[id])
	for id: StringName in _bans:
		var banned: PackedStringArray = model.id_sets.get(id, PackedStringArray())
		var boxes: Dictionary = _bans[id]
		for task: Variant in boxes:
			var check := boxes[task] as CheckBox
			check.disabled = not may_change
			check.set_pressed_no_signal(banned.has(str(task)))


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


## Whether any settings control takes a change now.
func settings_editable() -> bool:
	if not map_picker.disabled:
		return true
	for id: StringName in _numbers:
		if _numbers[id].editable:
			return true
	for id: StringName in _bans:
		var boxes: Dictionary = _bans[id]
		for task: Variant in boxes:
			if not (boxes[task] as CheckBox).disabled:
				return true
	return false


func _send(id: StringName, value: Variant) -> void:
	if _may_change:
		setting_changed.emit(id, value)


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


func _banned(id: StringName) -> PackedStringArray:
	var banned := PackedStringArray()
	var boxes: Dictionary = _bans[id]
	for task: Variant in boxes:
		if (boxes[task] as CheckBox).button_pressed:
			banned.append(str(task))
	return banned


static func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
