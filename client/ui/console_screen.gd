class_name ConsoleScreen
extends PanelContainer
## The ship's match console's own screen (prime-game-ui `ui-2.5.4` `docs/handoff/s04-lobby.md`,
## states `console-host` and `console-guest`; #1604, ARCHITECTURE §4.7.67): not an overlay but the
## root of the console's SubViewport (MatchConsole), 960 x 540, drawn on the console's screen
## mesh for whoever looks at it. `Console` (ToyPanelDialog) holds:
## - `V/Top`: the title `console.title` and, for the host, `HostNote` (`esc.lobby.you_host`); for
##   everyone else `HostOnly`, the lock and `esc.lobby.host_only` with the host's name.
## - `V/Rows`: a 72 px ToySettingRow per match setting the own mode shows on the picked map
##   (MatchRows, the same answer as the Esc menu's Lobby page since #1601): a whole number's
##   stepper (Less and More with the pack's minus and plus, the 156 px Value), the banned task
##   types' chips (selected = allowed). The host gets the steppers and chips; everyone else the
##   values and plates only.
## - `V/Code`: the room's code to read out (`common.code` and the code, or `esc.lobby.code_gone`);
##   no Copy (the crosshair is no clipboard): hidden in a Direct session.
## Everything comes from the own ClientModel and the own mode; a change only emits
## setting_changed, which the game sends as ChangeSettings (the host checks it). Styled only
## through the shared theme's variations; texts are deck keys, the numbers and names data.

## The host changed setting `id` to `value` (a whole number, or the banned types' ids).
signal setting_changed(id: StringName, value: Variant)

## The screen's size: the SubViewport's (the handoff's 960 x 540).
const SIZE := Vector2(960, 540)
const HOST_ONLY_KEY := "esc.lobby.host_only"
## Sizes in px (the handoff's; layout).
const ROW_HEIGHT := 72.0
const NAME_WIDTH := Vector2(240, 0)
const VALUE_WIDTH := Vector2(156, 0)
const NOTE_WIDTH := Vector2(420, 0)
const HOST_ONLY_WIDTH := Vector2(378, 0)
const LOCK_SIZE := Vector2(30, 30)
const LESS_ICON := preload("res://assets/ui/toy_pack/icons/minus.svg")
const MORE_ICON := preload("res://assets/ui/toy_pack/icons/plus.svg")
const LOCK := preload("res://assets/ui/toy_pack/icons/lock.svg")

var title := UiParts.styled_label("console.title", &"ToyTitleMachine")
var host_note := UiParts.styled_label("esc.lobby.you_host", &"ToyTextMutedOnLight")
var host_only := HBoxContainer.new()
var host_only_text := UiParts.styled_label("", &"ToyTextMutedOnLight")
var lock := TextureRect.new()
var rows := VBoxContainer.new()
var code_row := HBoxContainer.new()
var code_label := UiParts.styled_label("", &"ToyTextOnLight")
var code_gone := UiParts.styled_label("esc.lobby.code_gone", &"ToyTextMutedOnLight")

var _mode: GameMode
var _model: ClientModel
var _match_rows: MatchRows
## Whether the settings take a change now (the host in the lobby of a shared session).
var _may_change := false
## Whether the lock line names the host (a shared session; never the own ship).
var _shared := false
var _steppers: Dictionary[StringName, SettingStepper] = {}
## Each whole-number setting's row.
var _rows: Dictionary[StringName, PanelContainer] = {}
## Setting id -> task type id -> its toggle chip (the host's) and its plate (everyone else's).
var _bans: Dictionary[StringName, Dictionary] = {}
var _plates: Dictionary[StringName, Dictionary] = {}
## Setting id -> [the host's chips box, the plates box].
var _ban_boxes: Dictionary[StringName, Array] = {}
var _host_name := ""


func _init() -> void:
	name = "Console"
	theme_type_variation = &"ToyPanelDialog"
	custom_minimum_size = SIZE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.name = "V"
	v.theme_type_variation = &"ToyColumnSixteen"
	add_child(v)
	var top := HBoxContainer.new()
	top.name = "Top"
	top.theme_type_variation = &"ToyRowSixteen"
	v.add_child(top)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title)
	host_note.name = "HostNote"
	host_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host_note.custom_minimum_size = NOTE_WIDTH
	host_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	host_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(host_note)
	host_only.name = "HostOnly"
	host_only.theme_type_variation = &"ToyRowTwelve"
	host_only.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(host_only)
	lock.name = "Lock"
	lock.texture = LOCK
	lock.custom_minimum_size = LOCK_SIZE
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	host_only.add_child(lock)
	host_only_text.name = "Text"
	host_only_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host_only_text.custom_minimum_size = HOST_ONLY_WIDTH
	host_only_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	host_only_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_only_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	host_only.add_child(host_only_text)
	rows.name = "Rows"
	rows.theme_type_variation = &"ToyColumnFour"
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(rows)
	code_row.name = "Code"
	code_row.theme_type_variation = &"ToyRowTwelve"
	v.add_child(code_row)
	var code_name := UiParts.styled_label("common.code", &"ToyTextMutedOnLight")
	code_name.name = "Label"
	code_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_row.add_child(code_name)
	code_label.name = "Value"
	code_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	code_row.add_child(code_label)
	code_gone.name = "Gone"
	v.add_child(code_gone)
	code_row.visible = false
	code_gone.visible = false
	host_note.visible = false
	host_only.visible = false


## Builds a row per setting of `mode`, once per mode.
func set_mode(mode: GameMode) -> void:
	_mode = mode
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.free()
	_steppers.clear()
	_rows.clear()
	_bans.clear()
	_plates.clear()
	_ban_boxes.clear()
	_match_rows = MatchRows.new(mode)
	if mode == null:
		return
	for spec: SettingSpec in mode.settings:
		var row := MatchRows.row_of(spec.id)
		if spec.is_number():
			var stepper := _stepper(str(row[2]), spec)
			var made := _row(str(row[0]), spec.id, stepper)
			_rows[spec.id] = made
			rows.add_child(made)
		else:
			rows.add_child(_task_row(str(row[0]), spec.id, mode))
	_write_names()
	var on_map := HowtoCards.shown_map(mode, _model.map if _model != null else "")
	_show_rows(on_map)
	_show_bans(on_map)
	_size_arrows()


## Shows what `model` knows now: `may_change` gives the steppers and chips (the host, in a phase
## taking its changes); `hosting` is the own player hosting, whose note shows (the countdown's
## read-only values too) where everyone else reads the lock line; `shared` is a session other
## players share (the own ship's and the tutorial's have no host to name).
func refresh(model: ClientModel, may_change: bool, hosting: bool, shared: bool) -> void:
	_model = model
	_may_change = may_change
	_shared = shared
	host_note.visible = shared and hosting
	host_only.visible = shared and not hosting
	var host := model.host_name() if model != null else ""
	if host != _host_name:
		_host_name = host
		_write_host_only()
	if model == null:
		return
	for id: StringName in _steppers:
		_steppers[id].set_editable(may_change)
		if model.settings.has(id):
			_steppers[id].show_value(model.settings[id] as int)
	var on_map := HowtoCards.shown_map(_mode, model.map)
	_show_rows(on_map)
	_show_bans(on_map)


## The banned types' chips (the host's) or plates (everyone else's), those playing on `on_map`
## alone (DE16), selected and full for an allowed type.
func _show_bans(on_map: String) -> void:
	for id: StringName in _bans:
		var banned: PackedStringArray = (
			_model.id_sets.get(id, PackedStringArray()) if _model != null else PackedStringArray()
		)
		var chips: Dictionary = _bans[id]
		(_ban_boxes[id][0] as Control).visible = _may_change
		(_ban_boxes[id][1] as Control).visible = not _may_change
		for task: Variant in chips:
			var allowed := not banned.has(str(task))
			var type := _mode.find_task_type(task as StringName) if _mode != null else null
			var plays := type == null or type.plays_on(on_map)
			(chips[task] as Button).visible = plays
			SettingRows.set_pressed(chips[task] as Button, allowed)
			var plate := _plates[id][task] as PanelContainer
			plate.visible = plays
			plate.theme_type_variation = &"ToyChipLight" if allowed else &"ToyChipLineOnLight"
			(plate.get_child(0) as Label).theme_type_variation = (
				&"ToyChipLightText" if allowed else &"ToyChipLineOnLightText"
			)


## The room's code (JoinProgress.code_text's `line` and the code): the row shows with a code, the
## code service's absence in its place for a code host whose service is gone.
func show_code(line: String, code: String) -> void:
	code_gone.visible = line == JoinProgress.CODE_GONE
	var waiting := line == JoinProgress.CODE_WAITING
	code_label.text = EscMenu.CODE_WAITING if waiting else code
	code_row.visible = (waiting or not code.is_empty()) and not code_gone.visible


## The stepper of setting `id`, or null.
func stepper_of(id: StringName) -> SettingStepper:
	return _steppers.get(id)


## The row of setting `id` (a whole number), or null.
func row_of(id: StringName) -> PanelContainer:
	return _rows.get(id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and lock != null:
		lock.self_modulate = get_theme_color(&"font_color", &"ToyTextMutedOnLight")
		_size_arrows()
	if what == NOTIFICATION_TRANSLATION_CHANGED and host_only_text != null:
		_write_host_only()
		_write_names()


func _write_host_only() -> void:
	host_only_text.text = String(TranslationServer.translate(HOST_ONLY_KEY)).format(
		{"name": _host_name}
	)


## The rows named after their one task type, in the language now (MatchRows.label).
func _write_names() -> void:
	if _match_rows == null:
		return
	for id: StringName in _rows:
		if _match_rows.names_task(id):
			var label := _rows[id].get_node(^"H/Name") as Label
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			label.text = _match_rows.label(id)


func _show_rows(on_map: String) -> void:
	if _match_rows == null:
		return
	for id: StringName in _rows:
		_rows[id].visible = _match_rows.shown_on(id, on_map)


## The arrows' size is the ToyStepper variation's (the handoff's 51 x 51), read again on a theme
## change.
func _size_arrows() -> void:
	if not is_inside_tree():
		return
	var arrow := Vector2(
		get_theme_constant(&"width", &"ToyStepper"), get_theme_constant(&"height", &"ToyStepper")
	)
	for id: StringName in _steppers:
		_steppers[id].less.custom_minimum_size = arrow
		_steppers[id].more.custom_minimum_size = arrow


## A 72 px row named `row_name`: the Name (the setting's, MatchRows.label) and `control`.
func _row(row_name: String, id: StringName, control: Control) -> PanelContainer:
	var made := PanelContainer.new()
	made.name = row_name
	made.theme_type_variation = &"ToySettingRow"
	made.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var line := HBoxContainer.new()
	line.name = "H"
	line.theme_type_variation = &"ToyRowSixteen"
	made.add_child(line)
	var label := Label.new()
	label.name = "Name"
	label.theme_type_variation = &"ToySettingRowText"
	label.text = _match_rows.label(id)
	label.custom_minimum_size = NAME_WIDTH
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)
	return made


## SettingStepper in the console's look: the pack's minus and plus, the 156 px value, at the end.
func _stepper(format_key: String, spec: SettingSpec) -> SettingStepper:
	var stepper := SettingStepper.new()
	stepper.theme_type_variation = &"ToyRowTwelve"
	stepper.alignment = BoxContainer.ALIGNMENT_END
	stepper.less.icon = LESS_ICON
	stepper.more.icon = MORE_ICON
	stepper.value_label.custom_minimum_size = VALUE_WIDTH
	stepper.format_key = format_key
	stepper.set_bounds(spec.min_value, spec.max_value)
	stepper.show_value(spec.default_value)
	var id := spec.id
	stepper.stepped.connect(func(value: int) -> void: _send(id, value))
	_steppers[spec.id] = stepper
	return stepper


func _send(id: StringName, value: Variant) -> void:
	if _may_change:
		setting_changed.emit(id, value)


## The banned task types' row: the host's toggle chips (selected = allowed) and everyone else's
## plates, one per task type of the mode (refresh shows those playing on the map).
func _task_row(row_name: String, id: StringName, mode: GameMode) -> PanelContainer:
	var allowed := HBoxContainer.new()
	allowed.name = "Allowed"
	allowed.theme_type_variation = &"ToyRowEight"
	var made := _row(row_name, id, allowed)
	var shown := HBoxContainer.new()
	shown.name = "Shown"
	shown.theme_type_variation = &"ToyRowEight"
	shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	made.get_node(^"H").add_child(shown)
	var chips := {}
	var plates := {}
	for task: TaskType in mode.task_types:
		if task == null:
			continue
		var words := ContentNames.task(task.id, mode)
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


## A chip changed: the types not selected, plus a ban on a type the map hides (DE16: no chip shows
## to undo it), as the Lobby page sends them.
func _send_bans(id: StringName) -> void:
	var banned := PackedStringArray()
	var chips: Dictionary = _bans[id]
	if _model != null:
		for task: String in _model.id_sets.get(id, PackedStringArray()):
			var chip: Button = chips.get(StringName(task))
			if chip == null or not chip.visible:
				banned.append(task)
	for task: Variant in chips:
		var chip := chips[task] as Button
		if chip.visible and not chip.button_pressed:
			banned.append(str(task))
	_send(id, banned)
