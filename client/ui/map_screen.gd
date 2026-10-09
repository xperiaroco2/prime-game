class_name MapScreen
extends Control
## The map and tasks screen (#253, ARCHITECTURE §4.7.33), opened and closed with the `map` action
## (M) in the round, for the living, the downed and the dead alike; it replaced the hold-Tab task
## screen of M4-8. Left, the tasks: one row per task of the match (TaskState) with its type's name
## and its shared counter, no description, and a «?» that asks for the type's how-to card
## (howto_requested; the card is #254). Right, the level's map (MapData): the rooms by name, the
## own place and heading as a pin with "you are here", and while a task row is hovered the zones
## where that type's items may lie. Then the match clock.
##
## Never another player's place, an item's or a circle's: the screen reads only the model's tasks
## and clock, and the own place the game passes in (HudText.Local); zones are level data (the M4
## ADR's §3 item 4 as revised by #253). Styled only through the shared theme's Toy variations; the
## final look is #490.

## Asked when a task row's «?» is pressed: the how-to card of `task_type` (#254 connects it).
signal howto_requested(task_type: StringName)

## The board's size in pixels at the 1920x1080 base (layout, not style).
const BOARD_SIZE := Vector2(1040, 720)
## The task list's width in pixels (layout).
const TASKS_WIDTH := 520.0
## The "you are here" chip's gap to the pin, in pixels (layout).
const HERE_GAP := Vector2(8, -3)
## The zone's chip's inset from its room's top-left corner, in pixels (layout).
const ZONE_HINT_GAP := 12.0


## One row of the task list: a task's type, its name and its shared counter.
class Row:
	extends RefCounted
	var type: StringName
	## The type's display name in the client's own mode, or its id: the deck's `task.<id>` wins.
	var fallback: String
	var done := 0
	var total := 0


var title := UiParts.styled_label("map.tasks", &"ToyTitleOnLight")
var rows_box := VBoxContainer.new()
var time_label := UiParts.styled_label("", &"ToyTextMutedOnLight")
var board := PanelContainer.new()
## The rooms, the zones, the zone's chip and the pin, placed in board pixels.
var plan := Control.new()
var pin := Panel.new()
var here := PanelContainer.new()
var zone_hint := PanelContainer.new()

var _data := MapData.new()
## Room id -> its lit zone panel, and its name's label.
var _zones: Dictionary[StringName, Panel] = {}
var _room_labels: Dictionary[StringName, Label] = {}
var _zone_hint_label := UiParts.styled_label("", &"ToyChipLightText")
var _lit: StringName = &""
## The task type of the row under the mouse in the last frame, so a hover lights it once.
var _hovered: StringName = &""
## The rows last built, so a refresh with the same rows builds nothing.
var _shown: Array[Row] = []
var _model: ClientModel
var _mode: GameMode
var _host_tick := 0.0
var _local := HudText.Local.new()


func _init() -> void:
	name = "MapScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiParts.backdrop(self, &"ToyBackdropDeep").mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var row := HBoxContainer.new()
	row.theme_type_variation = &"ToyRowThirtyTwo"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	row.add_child(_tasks_panel())
	board.theme_type_variation = &"ToyMapBoard"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(board)
	plan.custom_minimum_size = BOARD_SIZE
	plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(plan)
	_build_marks()
	set_data(_data)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var hovered := _row_type_under_mouse()
	if hovered == _hovered:
		return
	_hovered = hovered
	if hovered.is_empty():
		unlight()
	else:
		light(hovered)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_place_pin()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		# The words in place: nothing is freed while the notification walks the tree.
		_retext()


## The level's map; an empty MapData (no level, or a level with no rooms) hides the board.
func set_data(data: MapData) -> void:
	_data = data
	_rebuild_rooms()
	var was_lit := _lit
	unlight()
	if not was_lit.is_empty():
		light(was_lit)
	_place_pin()


## The rows, the counters, the clock and the pin from `model` (its tasks and clock only), the own
## mode (the types' names), the newest host tick and the own place in `local`.
func refresh(model: ClientModel, mode: GameMode, host_tick: float, local: HudText.Local) -> void:
	_model = model
	_mode = mode
	_host_tick = host_tick
	_local = local
	_refresh_now()


## What the last refresh was given besides the model: the own place and heading.
func local() -> HudText.Local:
	return _local


## Lights the zones of `task_type` (the rooms where its items may lie) and the chip that says so.
func light(task_type: StringName) -> void:
	_lit = task_type
	var rooms := _data.zone_of(task_type)
	for room: StringName in _zones:
		_zones[room].visible = rooms.has(String(room))
	_show_zone_hint()


func unlight() -> void:
	_lit = &""
	for room: StringName in _zones:
		_zones[room].visible = false
	_show_zone_hint()


## The task type whose zones are lit; empty for none.
func lit() -> StringName:
	return _lit


## One row per task of the match, by task id: its type, the type's name in the own mode and its
## shared counter.
static func rows(model: ClientModel, mode: GameMode) -> Array[Row]:
	var ids: Array[int] = []
	ids.assign(model.tasks.keys())
	ids.sort()
	var made: Array[Row] = []
	for id: int in ids:
		var task := model.tasks[id]
		var type := mode.find_task_type(task.type) if mode != null else null
		var row := Row.new()
		row.type = task.type
		row.fallback = type.display_name if type != null else String(task.type)
		row.done = task.done
		row.total = task.total
		made.append(row)
	return made


## A row's name: the deck's `task.<id>` in the language now, else the mode's display name.
static func name_of(row: Row) -> String:
	return _translated("task.%s" % row.type, row.fallback)


## "3 of 6" in the language now.
static func counter_text(row: Row) -> String:
	return TranslationServer.translate("map.progress").format(
		{"count": row.done, "total": row.total}
	)


## "Time: 4:31" in the language now, or empty before the match clock runs.
static func time_text(model: ClientModel, host_tick: float) -> String:
	var left := GameFlow.seconds_left(model.end_tick, floori(host_tick))
	if left < 0:
		return ""
	var clock := "%d:%02d" % [floori(left / 60.0), left % 60]
	return TranslationServer.translate("map.time").format({"time": clock})


## The deck's `key` in the language now, or `fallback` when the deck has no such key.
static func _translated(key: String, fallback: String) -> String:
	var text := String(TranslationServer.translate(key))
	return fallback if text == key else text


func _tasks_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToyPanelMenu"
	panel.custom_minimum_size = Vector2(TASKS_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var column := VBoxContainer.new()
	column.theme_type_variation = &"ToyColumnSixteen"
	panel.add_child(column)
	column.add_child(title)
	rows_box.theme_type_variation = &"ToyColumnTwelve"
	column.add_child(rows_box)
	time_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(time_label)
	return panel


## The pin, its "you are here" chip and the zone's chip, above the rooms.
func _build_marks() -> void:
	pin.name = "Pin"
	pin.theme_type_variation = &"ToyMapPin"
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiParts.sized(pin)
	plan.add_child(pin)
	here.name = "Here"
	here.theme_type_variation = &"ToyChipPlate"
	here.mouse_filter = Control.MOUSE_FILTER_IGNORE
	here.add_child(UiParts.styled_label("map.you_are_here", &"ToyChipPlateText"))
	plan.add_child(here)
	zone_hint.name = "ZoneHint"
	zone_hint.theme_type_variation = &"ToyChipLight"
	zone_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_hint_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	zone_hint.add_child(_zone_hint_label)
	plan.add_child(zone_hint)


func _refresh_now() -> void:
	if _model == null:
		return
	time_label.text = time_text(_model, _host_tick)
	time_label.visible = not time_label.text.is_empty()
	var made := rows(_model, _mode)
	if not _same_rows(made):
		_shown = made
		_rebuild_rows()
	_place_pin()


func _same_rows(made: Array[Row]) -> bool:
	if made.size() != _shown.size():
		return false
	for i in made.size():
		var a := made[i]
		var b := _shown[i]
		if a.type != b.type or a.fallback != b.fallback or a.done != b.done or a.total != b.total:
			return false
	return true


## The words built in code again, in the language now: the rows', the rooms', the clock's and
## the zone's chip.
func _retext() -> void:
	var plates := rows_box.get_children()
	for i in mini(plates.size(), _shown.size()):
		(plates[i].find_child("Name", true, false) as Label).text = name_of(_shown[i])
		(plates[i].find_child("Count", true, false) as Label).text = counter_text(_shown[i])
	for id: StringName in _room_labels:
		_room_labels[id].text = _room_name(id)
	if _model != null:
		time_label.text = time_text(_model, _host_tick)
	_show_zone_hint()


func _rebuild_rows() -> void:
	for child: Node in rows_box.get_children():
		rows_box.remove_child(child)
		child.free()
	for row: Row in _shown:
		rows_box.add_child(_task_row(row))


## A task row: its name, its counter and its «?»; hovering the row lights its zones.
func _task_row(row: Row) -> Control:
	var plate := PanelContainer.new()
	plate.theme_type_variation = &"ToySettingRow"
	plate.set_meta(&"task_type", row.type)
	var line := HBoxContainer.new()
	line.theme_type_variation = &"ToyRowTwelve"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(line)
	var task_name := UiParts.styled_label(name_of(row), &"ToySettingRowText")
	task_name.name = "Name"
	task_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	task_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(task_name)
	var count := UiParts.styled_label(counter_text(row), &"ToySettingRowValue")
	count.name = "Count"
	count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(count)
	var help := Button.new()
	help.name = "Help"
	help.text = "?"
	help.theme_type_variation = &"ToyKeyRoundButton"
	help.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# Space jumps while the map is open and is also ui_accept: a focused «?» would press with every
	# jump (#488 moves Space out of ui_accept). The mouse presses it.
	help.focus_mode = Control.FOCUS_NONE
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help.pressed.connect(func() -> void: howto_requested.emit(row.type))
	ToyPress.attach(help)
	UiParts.sized(help)
	line.add_child(help)
	return plate


## The room tiles and their zone panels, in board pixels; the board hides with no room.
func _rebuild_rooms() -> void:
	for child: Node in plan.get_children():
		if child != pin and child != here and child != zone_hint:
			plan.remove_child(child)
			child.free()
	_zones.clear()
	_room_labels.clear()
	board.visible = not _data.rooms.is_empty()
	var pixels_per_metre := _data.scale_for(BOARD_SIZE)
	var at := 0
	for room: MapData.Room in _data.rooms:
		var tile := PanelContainer.new()
		tile.name = "Room_%s" % room.id
		tile.theme_type_variation = &"ToyMapRoom"
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.position = _data.to_board(room.rect.position, BOARD_SIZE)
		tile.size = room.rect.size * pixels_per_metre
		# The zone first, so the room's name draws over the light; the tile stacks both full size.
		var zone := Panel.new()
		zone.name = "Zone_%s" % room.id
		zone.theme_type_variation = &"ToyMapZone"
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone.visible = false
		tile.add_child(zone)
		_zones[room.id] = zone
		var label := UiParts.styled_label(_room_name(room.id), &"ToyMapRoomText")
		label.name = "Name"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		tile.add_child(label)
		_room_labels[room.id] = label
		plan.add_child(tile)
		plan.move_child(tile, at)
		at += 1


func _room_name(id: StringName) -> String:
	return _translated("room.%s" % id, String(id))


## The zone's chip in the first lit room: the deck's `map.zone_hint.<type>`, else
## `map.zone_hint`.
func _show_zone_hint() -> void:
	var rooms := _data.zone_of(_lit) if not _lit.is_empty() else PackedStringArray()
	zone_hint.visible = not rooms.is_empty()
	if rooms.is_empty():
		return
	_zone_hint_label.text = _translated(
		"map.zone_hint.%s" % _lit, String(TranslationServer.translate("map.zone_hint"))
	)
	# Inside the first lit room: wrapped to its width when the words (a long language) are wider.
	var tile := _zones[StringName(rooms[0])].get_parent() as Control
	var room_width := tile.size.x - 2.0 * ZONE_HINT_GAP
	_zone_hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_zone_hint_label.custom_minimum_size = Vector2.ZERO
	var chip_width := zone_hint.get_combined_minimum_size().x
	var padding := chip_width - _zone_hint_label.get_combined_minimum_size().x
	if chip_width > room_width:
		_zone_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_zone_hint_label.custom_minimum_size.x = maxf(room_width - padding, 1.0)
	zone_hint.reset_size()
	zone_hint.position = tile.position + Vector2.ONE * ZONE_HINT_GAP
	# A wrapped label knows its height only once laid out at its width: shrink the chip again then.
	if _zone_hint_label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		_refit_zone_hint.call_deferred()


func _refit_zone_hint() -> void:
	zone_hint.reset_size()


## The own pin at the own place, pointing the own heading, with its chip; hidden with no place or
## no map.
func _place_pin() -> void:
	var shown := _local.placed and not _data.rooms.is_empty()
	pin.visible = shown
	here.visible = shown
	if not shown:
		return
	var centre := _data.to_board(MapData.plan_of(_local.position), BOARD_SIZE)
	var pin_size := UiParts.size_of(pin)
	pin.size = pin_size
	pin.position = centre - pin_size / 2.0
	# The pin's sharp corner is its top-left: a quarter turn of 45 degrees points it north.
	pin.rotation = PI / 4.0 + _local.heading
	here.reset_size()
	here.position = Vector2(pin.position.x + pin_size.x + HERE_GAP.x, pin.position.y + HERE_GAP.y)


## The task type of the row under the mouse, its «?» included; empty for none.
func _row_type_under_mouse() -> StringName:
	var viewport := get_viewport()
	if viewport == null:
		return &""
	var at: Node = viewport.gui_get_hovered_control()
	while at != null and at != self:
		if at.get_parent() == rows_box:
			return at.get_meta(&"task_type", &"") as StringName
		at = at.get_parent()
	return &""
