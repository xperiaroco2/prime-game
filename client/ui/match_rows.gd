class_name MatchRows
extends RefCounted
## Which match settings a page shows and what each row reads (#1601, #1604), one answer for the
## Esc menu's Lobby page (LobbyPanel) and the ship's match console (ConsoleScreen), built once per
## mode from the client's own copy of it:
## - A whole number shows only with more than one allowed value and a part of the mode reading it
##   (`GameMode.read_settings()`: the base mode's knives in the M8 slice, #1525).
## - A task type's own setting (`TaskType.subtasks_setting`) shows only on a map one of its types
##   plays; the task count (TASK_COUNT) only with more types playing there than its least value.
## - A row's name is its deck key (ROWS); a task type's own setting with no key of its own reads
##   "<the task>: step count" (STEPS_LABEL) in the language now; any other the spec's name.

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
## The task count's setting (DealTasks' `tasks_setting` in the base mode): one per task type the
## picked map plays, so with one such type it has nothing to choose (#1601).
const TASK_COUNT := &"tasks"
## A task type's own step count with no row key of its own: "<the task>: step count" (#1601).
const STEPS_LABEL := "lobby.setting.task_steps"

var mode: GameMode
## Each whole-number setting and whether it shows on any map (bounds and a reader).
var _shown: Dictionary[StringName, bool] = {}
## A task type's own setting -> the types reading it.
var _types_of: Dictionary[StringName, Array] = {}
## A row named after its one task type (STEPS_LABEL) -> that type's id.
var _steps: Dictionary[StringName, StringName] = {}


func _init(game_mode: GameMode) -> void:
	mode = game_mode
	if mode == null:
		return
	for task: TaskType in mode.task_types:
		if task != null and not task.subtasks_setting.is_empty():
			if not _types_of.has(task.subtasks_setting):
				_types_of[task.subtasks_setting] = []
			_types_of[task.subtasks_setting].append(task)
	var read := mode.read_settings()
	for spec: SettingSpec in mode.settings:
		var types: Array = _types_of.get(spec.id, [])
		if str(row_of(spec.id)[1]).is_empty() and types.size() == 1:
			_steps[spec.id] = (types[0] as TaskType).id
		if spec.is_number():
			_shown[spec.id] = spec.min_value < spec.max_value and read.has(spec.id)


## The row of setting `id`: [node name, deck key or "", value key or ""].
static func row_of(id: StringName) -> Array:
	return ROWS.get(id, [String(id).to_pascal_case(), "", ""])


## Whether the whole-number setting `id` shows on `on_map` (a map's path, "" for none known).
func shown_on(id: StringName, on_map: String) -> bool:
	if not _shown.get(id, false):
		return false
	if (
		_types_of.has(id)
		and not _types_of[id].any(func(task: TaskType) -> bool: return task.plays_on(on_map))
	):
		return false
	if id == TASK_COUNT:
		var playing := 0
		for task: TaskType in mode.task_types:
			if task != null and task.plays_on(on_map):
				playing += 1
		return playing > mode.find_setting(id).min_value
	return true


## Whether row `id` is named after its one task type in code (label() then reads the language now).
func names_task(id: StringName) -> bool:
	return _steps.has(id)


## The name row `id` shows: a deck key a Label translates itself, or for names_task() rows the
## text in the language now (set with auto-translate off).
func label(id: StringName) -> String:
	if _steps.has(id):
		var task := ContentNames.text(ContentNames.task(_steps[id], mode))
		return String(TranslationServer.translate(STEPS_LABEL)).format({"task": task})
	var key := str(row_of(id)[1])
	if not key.is_empty():
		return key
	var spec := mode.find_setting(id) if mode != null else null
	return spec.display_name if spec != null else String(id)
