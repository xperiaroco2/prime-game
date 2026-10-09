class_name MapScreen
extends Control
## The map and tasks screen (#253, ARCHITECTURE §4.7.33), opened and closed with the `map` action
## (M) in the round, for the living, the downed and the dead alike; it replaced the hold-Tab task
## screen of M4-8. Its look is the Toy one of prime-game-ui's s08 handoff at ui-0.4.0 (#490,
## §4.7.41), node for node: `Dim`, then `Tasks` (raised, top left: the title, one row per task type
## with its name, its shared counter and a «?», then the clock) and `Board` (raised: `Rooms`, the
## level's rooms from MapData with their pictogram and name, the zones of the hovered or focused
## row's type and their tag, the own pin with "you are here"). A «?» opens its type's how-to card
## (#254, s8's `guide`) over the map on `Dim2`: Close, Esc or the map key closes only the card (Esc
## and the key through GameUi.overlays, its `howto_card` on top of the map, #488's rules 2 and 3);
## while it is open the task list and the board take no focus. No focus on open; the first ui_down
## or ui_up focuses the first row's «?»; a card opened by the keyboard or the gamepad gives Close
## the focus and gives it back to that «?» on close, one opened with the mouse drops it.
##
## Never another player's place, an item's or a circle's: the screen reads only the model's tasks
## and clock, and the own place the game passes in (HudText.Local); zones are level data (the M4
## ADR's §3 item 4 as revised by #253). Styled only through the shared theme's Toy variations.

## Asked when a task row's «?» is pressed: the how-to card of `task_type`; the screen opens it.
signal howto_requested(task_type: StringName)

## The handoff's places at the 1920x1080 base (layout, not style): the raised task list's left,
## top and right edges (it grows down to its content), and the raised board's rect.
const TASKS_OFFSETS := Vector3(80, 88, 688)
const BOARD_RECT := Rect2(744, 88, 1096, 904)
## `Rooms` inside the board's border: the room rects and the pin are placed for this size.
const ROOMS_SIZE := Vector2(1088, 896)
## A task row's height and its «?»'s size (the handoff's minimum sizes; 42 keeps the «?» round
## at large text, where the glyph makes it 42 tall).
const ROW_HEIGHT := 64.0
const HELP_SIZE := Vector2(42, 42)
## A room's pictogram and its name's least width.
const ROOM_ICON_SIZE := Vector2(48, 48)
const ROOM_NAME_WIDTH := 120.0
## The "you are here" chip's gap to the pin, in pixels (layout).
const HERE_GAP := Vector2(8, -3)
## The zone's tag: its gap under the first lit room, in pixels (layout).
const ZONE_HINT_GAP := 12.0
## The how-to card's width over the map (the handoff's Card), in pixels (layout).
const HOWTO_WIDTH := 1536.0
## The pack's room pictograms, by room id (prime-game-ui `dist/pack/icons/room/`).
const ROOM_ICON := &"room/%s"


## One row of the task list: a task type, its name and its shared counter.
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
## The raised task list: its face `Tasks` and its ToyRaised wrapper (placement, visibility).
var tasks_panel := PanelContainer.new()
var tasks_raised: ToyRaised
## The raised board: its face `Board` and its wrapper, hidden with no room.
var board := PanelContainer.new()
var board_raised: ToyRaised
## `Rooms`: the rooms, the zones' tag and the pin, placed in ROOMS_SIZE pixels.
var plan := Control.new()
var pin := Panel.new()
var here := PanelContainer.new()
## The lit zones' tag (`Zone<Type>Tag` while shown).
var zone_hint := PanelContainer.new()
## Under the how-to card: dims the map and stops the mouse (Dim2), and centres the card (Guide).
var howto_dim: Panel
var howto_center := CenterContainer.new()
## The open how-to card (a ToyRaised of HowtoCardView); null while none is open.
var howto: ToyRaised
## The task type whose card is open; &"" while none is.
var howto_type: StringName = &""

var _data := MapData.new()
## Room id -> its tile, and its name's label.
var _tiles: Dictionary[StringName, PanelContainer] = {}
var _room_labels: Dictionary[StringName, Label] = {}
var _zone_hint_label := UiParts.styled_label("", &"ToyChipLightText")
var _lit: StringName = &""
## The task type the hover or the keyboard focus asked for in the last frame, so it lights once.
var _wanted: StringName = &""
## The rows last built, so a refresh with the same types builds nothing.
var _shown: Array[Row] = []
## The «?» that opened the card by keyboard or gamepad, which takes the focus back; else null.
var _focus_back: Button
var _model: ClientModel
var _mode: GameMode
var _host_tick := 0.0
var _local := HudText.Local.new()


func _init() -> void:
	name = "MapScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := UiParts.backdrop(self, &"ToyBackdropDeep")
	dim.name = "Dim"
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tasks()
	_build_board()
	set_data(_data)
	howto_dim = UiParts.backdrop(self, &"ToyBackdrop")
	howto_dim.name = "Dim2"
	howto_dim.visible = false
	howto_center.name = "Guide"
	howto_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	howto_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	howto_center.visible = false
	add_child(howto_center)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var wanted := _row_type_under_mouse()
	if wanted.is_empty():
		wanted = _row_type_focused()
	if wanted == _wanted:
		return
	_wanted = wanted
	if wanted.is_empty():
		unlight()
	else:
		light(wanted)


## With no focus on the screen, the first ui_down or ui_up focuses the first row's «?» (Godot
## moves a focus only once one exists). The arrows and the d-pad only: the movement keys walk.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or howto != null:
		return
	if not (event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"ui_up")):
		return
	if get_viewport().gui_get_focus_owner() != null or not focus_help():
		return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_tint_icons()
		_place_pin()
		_show_zone_hint()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		# The map closed (its key, the Esc menu, the end of the round): its card with it.
		close_howto()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		# The words in place: nothing is freed while the notification walks the tree.
		_retext()


## Gives the keyboard focus to `type`'s «?», or with no type to the first row's (as the first
## ui_down does); false when there is no such row.
func focus_help(type: StringName = &"") -> bool:
	var help: Button = null
	if type.is_empty():
		var helps := rows_box.find_children("Help", "Button", true, false)
		help = helps[0] as Button if not helps.is_empty() else null
	else:
		help = _help_of(type)
	if help == null:
		return false
	help.grab_focus()
	return true


## Opens `type`'s how-to card over the map (HowtoCards); false when the type has none. Opened
## `by_keyboard` (or gamepad), Close takes the focus and gives it back to that type's «?» on close.
func open_howto(type: StringName, by_keyboard := false) -> bool:
	var card := HowtoCards.of_task(type)
	if card == null:
		return false
	close_howto()
	howto = HowtoCardView.raised(card, HowtoCardView.MAP_ART, ToyHints.LIGHT, true)
	howto.custom_minimum_size = Vector2(HOWTO_WIDTH, 0)
	var face := HowtoCardView.face_of(howto)
	face.close_requested.connect(close_howto)
	howto_center.add_child(howto)
	howto_type = type
	howto_dim.visible = true
	howto_center.visible = true
	_focus_back = _help_of(type) if by_keyboard else null
	for each: Control in [tasks_panel, board]:
		each.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	if by_keyboard and face.close_button.is_visible_in_tree():
		face.close_button.grab_focus()
	return true


## Closes the how-to card, if one is open. Opened by keyboard, the focus goes back to its «?»;
## else a focus in the card or on the map goes (a mouse press focused the «?»). A focus outside
## the map (the Esc menu, which opens before the map closes) stays.
func close_howto() -> void:
	if howto == null:
		return
	var back := _focus_back
	_focus_back = null
	var viewport := get_viewport()
	var focused := viewport.gui_get_focus_owner() if viewport != null else null
	var ours := focused != null and is_ancestor_of(focused)
	howto_center.remove_child(howto)
	howto.queue_free()
	howto = null
	howto_type = &""
	howto_dim.visible = false
	howto_center.visible = false
	for each: Control in [tasks_panel, board]:
		each.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	if is_instance_valid(back) and back.is_visible_in_tree():
		back.grab_focus()
	elif ours:
		viewport.gui_release_focus()


func howto_open() -> bool:
	return howto != null


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


## Lights the zones of `task_type` (the rooms where its items may lie) and the tag that says so.
func light(task_type: StringName) -> void:
	_clear_zones()
	_lit = task_type
	for room: String in _data.zone_of(task_type):
		var tile: PanelContainer = _tiles.get(StringName(room))
		if tile == null:
			continue
		# A whole room's zone: its first child, so it fills the room under the pictogram and name.
		var zone := Panel.new()
		zone.name = _zone_name(task_type)
		zone.theme_type_variation = &"ToyMapZone"
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(zone)
		tile.move_child(zone, 0)
	_show_zone_hint()


func unlight() -> void:
	_clear_zones()
	_lit = &""
	_show_zone_hint()


## The task type whose zones are lit; empty for none.
func lit() -> StringName:
	return _lit


## One row per task type of the match, in the order of its first task's id: the type's name in the
## own mode and its tasks' shared counters together (DealTasks deals each type once, so a type has
## one task in a round).
static func rows(model: ClientModel, mode: GameMode) -> Array[Row]:
	var ids: Array[int] = []
	ids.assign(model.tasks.keys())
	ids.sort()
	var made: Array[Row] = []
	var by_type: Dictionary[StringName, Row] = {}
	for id: int in ids:
		var task := model.tasks[id]
		var row: Row = by_type.get(task.type)
		if row == null:
			var type := mode.find_task_type(task.type) if mode != null else null
			row = Row.new()
			row.type = task.type
			row.fallback = type.display_name if type != null else String(task.type)
			by_type[task.type] = row
			made.append(row)
		row.done += task.done
		row.total += task.total
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


## `Zone<Type>`: a lit zone's name; its tag adds `Tag`.
static func _zone_name(task_type: StringName) -> String:
	return "Zone%s" % String(task_type).to_pascal_case()


## Tasks: the raised ToyPanelMenu at the top left, growing down to its rows and the clock.
func _build_tasks() -> void:
	tasks_panel.name = "Tasks"
	tasks_panel.theme_type_variation = &"ToyPanelMenu"
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnTwentyFour"
	tasks_panel.add_child(column)
	title.name = "Title"
	column.add_child(title)
	rows_box.name = "Rows"
	rows_box.theme_type_variation = &"ToyColumnEight"
	column.add_child(rows_box)
	time_label.name = "Time"
	time_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(time_label)
	tasks_raised = UiParts.raised(tasks_panel, ToyHints.LIGHT)
	tasks_raised.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tasks_raised.offset_left = TASKS_OFFSETS.x
	tasks_raised.offset_top = TASKS_OFFSETS.y
	tasks_raised.offset_right = TASKS_OFFSETS.z
	tasks_raised.offset_bottom = TASKS_OFFSETS.y
	tasks_raised.grow_horizontal = Control.GROW_DIRECTION_END
	tasks_raised.grow_vertical = Control.GROW_DIRECTION_END
	add_child(tasks_raised)


## Board: the raised ToyMapBoard holding `Rooms`, with the pin, its chip and the zones' tag.
func _build_board() -> void:
	board.name = "Board"
	board.theme_type_variation = &"ToyMapBoard"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plan.name = "Rooms"
	plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(plan)
	zone_hint.name = "ZoneTag"
	zone_hint.theme_type_variation = &"ToyChipLight"
	zone_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_hint_label.name = "Text"
	_zone_hint_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	zone_hint.add_child(_zone_hint_label)
	plan.add_child(zone_hint)
	pin.name = "Pin"
	pin.theme_type_variation = &"ToyMapPin"
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiParts.sized(pin)
	plan.add_child(pin)
	here.name = "Here"
	here.theme_type_variation = &"ToyChipPlate"
	here.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var here_text := UiParts.styled_label("map.you_are_here", &"ToyHudCaption")
	here_text.name = "Text"
	here.add_child(here_text)
	plan.add_child(here)
	board_raised = UiParts.raised(board, ToyHints.LIGHT)
	board_raised.set_anchors_preset(Control.PRESET_TOP_LEFT)
	board_raised.offset_left = BOARD_RECT.position.x
	board_raised.offset_top = BOARD_RECT.position.y
	board_raised.offset_right = BOARD_RECT.end.x
	board_raised.offset_bottom = BOARD_RECT.end.y
	board_raised.grow_horizontal = Control.GROW_DIRECTION_END
	board_raised.grow_vertical = Control.GROW_DIRECTION_END
	add_child(board_raised)


func _refresh_now() -> void:
	if _model == null:
		return
	time_label.text = time_text(_model, _host_tick)
	time_label.visible = not time_label.text.is_empty()
	var made := rows(_model, _mode)
	var same_types := made.size() == _shown.size()
	for i in mini(made.size(), _shown.size()):
		same_types = same_types and made[i].type == _shown[i].type
	_shown = made
	if same_types:
		# The counters in place: a rebuild would take a «?»'s focus while the map is open, and
		# every frame must not lay the zones' tag out again.
		_retext_rows()
	else:
		_rebuild_rows()
	_place_pin()


## The words built in code again, in the language now: the rows', the rooms', the clock's and
## the zones' tag.
func _retext() -> void:
	_retext_rows()
	for id: StringName in _room_labels:
		_room_labels[id].text = _room_name(id)
	if _model != null:
		time_label.text = time_text(_model, _host_tick)
	_show_zone_hint()


## The rows' names and counters only: all that a counter change touches.
func _retext_rows() -> void:
	var plates := rows_box.get_children()
	for i in mini(plates.size(), _shown.size()):
		(plates[i].find_child("Name", true, false) as Label).text = name_of(_shown[i])
		(plates[i].find_child("Count", true, false) as Label).text = counter_text(_shown[i])


func _rebuild_rows() -> void:
	for child: Node in rows_box.get_children():
		rows_box.remove_child(child)
		child.free()
	for row: Row in _shown:
		rows_box.add_child(_task_row(row), true)


## A task row (ToySettingRow): its name, its counter and its «?»; hovering the row or focusing its
## «?» lights its zones.
func _task_row(row: Row) -> Control:
	var plate := PanelContainer.new()
	plate.name = String(row.type).to_pascal_case()
	plate.theme_type_variation = &"ToySettingRow"
	plate.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	plate.set_meta(&"task_type", row.type)
	var line := HBoxContainer.new()
	line.name = "H"
	line.theme_type_variation = &"ToyRowTwelve"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(line)
	var task_name := UiParts.styled_label(name_of(row), &"ToySettingRowValue")
	task_name.name = "Name"
	task_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	task_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(task_name)
	var count := UiParts.styled_label(counter_text(row), &"ToySettingRowText")
	count.name = "Count"
	count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(count)
	var help := Button.new()
	help.name = "Help"
	help.text = "?"
	help.theme_type_variation = &"ToyKeyRoundButton"
	help.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# The arrows and the d-pad reach it; Space is out of ui_accept (#488), so a jump never presses
	# it. A mouse press focuses it hidden (has_focus(true) is false), a key's shows.
	help.focus_mode = Control.FOCUS_ALL
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help.custom_minimum_size = HELP_SIZE
	help.pressed.connect(_on_help.bind(help, row.type))
	ToyPress.attach(help)
	line.add_child(help)
	return plate


func _on_help(help: Button, type: StringName) -> void:
	howto_requested.emit(type)
	open_howto(type, help.has_focus(true))


## The «?» of `type`'s row; null for none.
func _help_of(type: StringName) -> Button:
	for plate: Node in rows_box.get_children():
		if plate.get_meta(&"task_type", &"") == type:
			return plate.find_child("Help", true, false) as Button
	return null


## The room tiles in ROOMS_SIZE pixels, before the tag, the pin and its chip; the board hides
## with no room.
func _rebuild_rooms() -> void:
	_clear_zones()
	for tile: PanelContainer in _tiles.values():
		plan.remove_child(tile)
		tile.free()
	_tiles.clear()
	_room_labels.clear()
	board_raised.visible = not _data.rooms.is_empty()
	var pixels_per_metre := _data.scale_for(ROOMS_SIZE)
	var at := 0
	for room: MapData.Room in _data.rooms:
		var tile := _room_tile(room.id)
		tile.position = _data.to_board(room.rect.position, ROOMS_SIZE)
		tile.size = room.rect.size * pixels_per_metre
		plan.add_child(tile, true)
		plan.move_child(tile, at)
		_tiles[room.id] = tile
		at += 1
	_tint_icons()


## A room (ToyMapRoom): its pictogram drawn in ink and its name, centred in a column.
func _room_tile(id: StringName) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.name = String(id).to_pascal_case()
	tile.theme_type_variation = &"ToyMapRoom"
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.name = "V"
	column.theme_type_variation = &"ToyColumnFour"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(column)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.custom_minimum_size = ROOM_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = _room_icon(id)
	# A room the pack draws no pictogram for shows its name only.
	icon.visible = icon.texture != null
	column.add_child(icon)
	var label := UiParts.styled_label(_room_name(id), &"ToyMapRoomText")
	label.name = "Name"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.custom_minimum_size = Vector2(ROOM_NAME_WIDTH, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	_room_labels[id] = label
	return tile


## The pack's pictogram of room `id`; null when the pack draws none for it (no warning: a level's
## room ids are its own, #306).
static func _room_icon(id: StringName) -> Texture2D:
	var icon := StringName(ROOM_ICON % id)
	if not (
		ResourceLoader.exists(ToyIcons.IMPORTED % icon)
		or FileAccess.file_exists(ToyIcons.PINNED % icon)
	):
		return null
	return ToyIcons.texture(icon)


## The pictograms in ink: the room names' colour (the pack's copy is white).
func _tint_icons() -> void:
	if not is_inside_tree():
		return
	for tile: PanelContainer in _tiles.values():
		var icon := tile.find_child("Icon", true, false) as TextureRect
		icon.self_modulate = icon.get_theme_color(&"font_color", &"ToyMapRoomText")


func _clear_zones() -> void:
	if _lit.is_empty():
		return
	for tile: PanelContainer in _tiles.values():
		var zone := tile.get_node_or_null(_zone_name(_lit))
		if zone != null:
			tile.remove_child(zone)
			zone.free()


func _room_name(id: StringName) -> String:
	return _translated("room.%s" % id, String(id))


## The zones' tag under the first lit room, its left edge on the room's: the deck's
## `map.zone_hint.<type>`, else `map.zone_hint`; on one line, wider than the room if it must,
## and wrapped only where it would pass the board's right edge.
func _show_zone_hint() -> void:
	var rooms := _data.zone_of(_lit) if not _lit.is_empty() else PackedStringArray()
	var tile: PanelContainer = _tiles.get(StringName(rooms[0])) if not rooms.is_empty() else null
	zone_hint.visible = tile != null
	if tile == null:
		zone_hint.name = "ZoneTag"
		return
	zone_hint.name = _zone_name(_lit) + "Tag"
	_zone_hint_label.text = _translated(
		"map.zone_hint.%s" % _lit, String(TranslationServer.translate("map.zone_hint"))
	)
	_zone_hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_zone_hint_label.custom_minimum_size = Vector2.ZERO
	var chip_width := zone_hint.get_combined_minimum_size().x
	var padding := chip_width - _zone_hint_label.get_combined_minimum_size().x
	var room_for := ROOMS_SIZE.x - tile.position.x
	if chip_width > room_for:
		_zone_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_zone_hint_label.custom_minimum_size.x = maxf(room_for - padding, 1.0)
	zone_hint.reset_size()
	zone_hint.position = tile.position + Vector2(0, tile.size.y + ZONE_HINT_GAP)
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
	var centre := _data.to_board(MapData.plan_of(_local.position), ROOMS_SIZE)
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
	return _row_type_of(viewport.gui_get_hovered_control())


## The task type of the row whose «?» has the keyboard's focus (not a mouse press's); empty for
## none.
func _row_type_focused() -> StringName:
	var viewport := get_viewport()
	var focused := viewport.gui_get_focus_owner() if viewport != null else null
	if focused == null or not focused.has_focus(true):
		return &""
	return _row_type_of(focused)


func _row_type_of(control: Node) -> StringName:
	var at := control
	while at != null and at != self:
		if at.get_parent() == rows_box:
			return at.get_meta(&"task_type", &"") as StringName
		at = at.get_parent()
	return &""
