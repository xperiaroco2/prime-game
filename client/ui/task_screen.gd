class_name TaskScreen
extends Control
## The Tab task screen (ARCHITECTURE §4.7, M4-8), while Tab is held in the round, for the living,
## the downed and the dead alike: each task of the match (TaskState) with its type's display name
## and description from the client's own mode and its shared progress, then the match's shared
## progress (TaskProgress). No map, and no position of an item, a player or a spawn point (answer
## 2 on PR #133; the M4 ADR's §3 item 4). Styled only through the shared theme (TaskPanel, Title,
## TaskRow, TaskDescription).

## The descriptions' wrapping width in pixels (layout, not style).
const TEXT_WIDTH := 867.0

var progress_label := UiParts.styled_label("", &"TaskRow")
var rows_box := VBoxContainer.new()

## The rows last built, so a refresh with the same rows builds nothing.
var _shown: Array[PackedStringArray] = []


func _init() -> void:
	name = "TaskScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"TaskPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"ScreenColumn"
	panel.add_child(column)
	column.add_child(UiParts.heading("Tasks"))
	rows_box.theme_type_variation = &"ScreenColumn"
	column.add_child(rows_box)
	column.add_child(progress_label)


func refresh(model: ClientModel, mode: GameMode) -> void:
	progress_label.text = progress_text(model)
	var made := rows(model, mode)
	if made == _shown:
		return
	_shown = made
	for child: Node in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	for row: PackedStringArray in made:
		var title := UiParts.styled_label(row[0], &"TaskRow")
		rows_box.add_child(title)
		var description := UiParts.styled_label(row[1], &"TaskDescription")
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size = Vector2(TEXT_WIDTH, 0.0)
		description.visible = not row[1].is_empty()
		rows_box.add_child(description)


## One row per task, by task id: [its title with its progress, its type's description].
static func rows(model: ClientModel, mode: GameMode) -> Array[PackedStringArray]:
	var ids: Array[int] = []
	ids.assign(model.tasks.keys())
	ids.sort()
	var made: Array[PackedStringArray] = []
	for id: int in ids:
		var task := model.tasks[id]
		var type := mode.find_task_type(task.type)
		var title := type.display_name if type != null else String(task.type)
		var description := type.description if type != null else ""
		made.append(
			PackedStringArray(["%s  %d / %d" % [title, task.done, task.total], description])
		)
	if made.is_empty():
		made.append(PackedStringArray(["No tasks yet", ""]))
	return made


## The match's shared progress (TaskProgress), or empty before it.
static func progress_text(model: ClientModel) -> String:
	if model.tasks_total <= 0:
		return ""
	return "Shared progress: %d / %d" % [model.tasks_done, model.tasks_total]
