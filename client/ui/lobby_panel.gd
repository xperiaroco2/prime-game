class_name LobbyPanel
extends Control
## The lobby panel (ARCHITECTURE §4.7), on the right while the player walks in the lobby: the
## roster with ready flags, Ready, the countdown, and on the host one control per SettingSpec of the
## client's own mode (a whole number within its bounds, or check boxes for the banned task types)
## with the shortfalls that hold the start back. Everything shown comes from the own ClientModel
## and the own mode. A changed control sends that setting only.

signal ready_toggled(on: bool)
signal setting_changed(id: StringName, value: Variant)

var roster_label := Label.new()
var countdown_label := Label.new()
var ready_button := Button.new()
var settings_box := VBoxContainer.new()
var shortfalls_label := Label.new()

var _numbers: Dictionary[StringName, SpinBox] = {}
## Setting id -> task type id -> its check box.
var _bans: Dictionary[StringName, Dictionary] = {}


func _init() -> void:
	name = "LobbyPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UiParts.side_column(self, "Lobby")
	column.add_child(roster_label)
	column.add_child(countdown_label)
	ready_button.toggle_mode = true
	ready_button.text = "Ready"
	ready_button.toggled.connect(func(on: bool) -> void: ready_toggled.emit(on))
	column.add_child(ready_button)
	column.add_child(settings_box)
	shortfalls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shortfalls_label.modulate = Color(1.0, 0.75, 0.4)
	column.add_child(shortfalls_label)


## Builds the host's controls from the mode's settings, once per mode.
func set_mode(mode: GameMode) -> void:
	for child: Node in settings_box.get_children():
		child.queue_free()
	_numbers.clear()
	_bans.clear()
	settings_box.add_child(UiParts.heading("Settings"))
	for spec: SettingSpec in mode.settings:
		var id := spec.id
		if spec.is_number():
			var box := SpinBox.new()
			box.min_value = spec.min_value
			box.max_value = spec.max_value
			box.value = spec.default_value
			box.value_changed.connect(
				func(value: float) -> void: setting_changed.emit(id, int(value))
			)
			_numbers[id] = box
			settings_box.add_child(UiParts.labelled(spec.display_name, box))
			continue
		var boxes: Dictionary[StringName, CheckBox] = {}
		settings_box.add_child(_text(spec.display_name))
		for task: TaskType in mode.task_types:
			var check := CheckBox.new()
			check.text = task.display_name
			check.toggled.connect(func(_on: bool) -> void: setting_changed.emit(id, _banned(id)))
			boxes[task.id] = check
			settings_box.add_child(check)
		_bans[id] = boxes


## Shows what `model` knows now; `host_tick` is the newest host tick it knows (-1: none yet).
func refresh(model: ClientModel, host_tick: int) -> void:
	roster_label.text = roster_text(model)
	var own: ClientModel.Member = model.roster.get(model.own_peer)
	var is_ready := own != null and own.ready
	ready_button.set_pressed_no_signal(is_ready)
	ready_button.text = "Ready (press again to cancel)" if is_ready else "Ready"
	var left := GameFlow.seconds_left(model.end_tick, host_tick)
	countdown_label.text = "Starting in %d s" % left if left >= 0 else "Waiting for everyone"
	var hosting := model.own_peer == NetTransport.HOST_ID
	settings_box.visible = hosting
	shortfalls_label.visible = not model.shortfalls.is_empty()
	shortfalls_label.text = "\n".join(model.shortfalls)
	for id: StringName in _numbers:
		if model.settings.has(id):
			_numbers[id].set_value_no_signal(model.settings[id])
	for id: StringName in _bans:
		var banned: PackedStringArray = model.id_sets.get(id, PackedStringArray())
		var boxes: Dictionary = _bans[id]
		for task: Variant in boxes:
			(boxes[task] as CheckBox).set_pressed_no_signal(banned.has(str(task)))


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
