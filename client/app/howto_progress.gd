class_name HowtoProgress
extends RefCounted
## What the player has seen and done of each task type, for the loading screen's how-to card
## (#254): it shows the card of a task type the player has not completed yet, at most
## LOADING_SHOWS times, and never after the first completion, so a veteran never sees it. Kept per
## player (the person, as Controls: one file for every window of one PC) in a ConfigFile under
## user://, written on each change.
##
## A completion is the player's first round in which a task of that type was finished: its shared
## counter (TaskState) reached its total while the player was in the round. Tasks are shared
## (#79) and no event names who did a subtask, so this is what the client can see (the reading
## under "Needs the engineer" on #254's PR).

## The issue's "at most twice".
const LOADING_SHOWS := 2
const FILE := "user://howto.cfg"
const SHOWN := "loading_shown"
const COMPLETED := "completed"

## The file, under user://; "" keeps the progress in memory only (read() and write() touch no
## file).
var path := ""

var _shown: Dictionary[StringName, int] = {}
var _completed: Dictionary[StringName, bool] = {}


func _init(at := "") -> void:
	path = at


## The player's progress: FILE, read if it exists.
static func for_this_player() -> HowtoProgress:
	var progress := HowtoProgress.new(FILE)
	progress.read()
	return progress


## How many times the loading screen showed `type`'s card.
func loading_shown(type: StringName) -> int:
	return _shown.get(type, 0)


func completed(type: StringName) -> bool:
	return _completed.get(type, false)


## Whether the loading screen may show `type`'s card: not completed, shown fewer than
## LOADING_SHOWS times.
func wants_loading_card(type: StringName) -> bool:
	return not completed(type) and loading_shown(type) < LOADING_SHOWS


## The first of `types` (in their order) whose card the loading screen may show; &"" for none.
func loading_pick(types: Array[StringName]) -> StringName:
	for type: StringName in types:
		if wants_loading_card(type):
			return type
	return &""


## The loading screen showed `type`'s card; written at once. Counted on top of the file as it is
## now, so another window's showings add up with this one's.
func note_loading_shown(type: StringName) -> void:
	if not path.is_empty():
		_merge_file()
	_shown[type] = loading_shown(type) + 1
	write()


## Marks each task type of `model`'s round whose task is finished (done == total > 0) as
## completed, and writes when one is new. Returns whether one was.
func follow(model: ClientModel) -> bool:
	var changed := false
	for id: int in model.tasks:
		var task: ClientModel.Task = model.tasks[id]
		if task.total > 0 and task.done >= task.total and not completed(task.type):
			_completed[task.type] = true
			changed = true
	if changed:
		write()
	return changed


func read() -> Error:
	_shown.clear()
	_completed.clear()
	if path.is_empty():
		return ERR_FILE_NOT_FOUND
	return _merge_file()


## Writes the progress, merged first with the file as it is now: another window of this PC (the
## `host` and `join` dev commands each read the file at start) may have written since this one
## read it, so a show count takes the larger and a completion stays.
func write() -> Error:
	if path.is_empty():
		return OK
	_merge_file()
	var file := ConfigFile.new()
	for type: StringName in _shown:
		file.set_value(String(type), SHOWN, _shown[type])
	for type: StringName in _completed:
		file.set_value(String(type), COMPLETED, true)
	return file.save(path)


## Folds the file's progress into this one: the larger show count, any completion.
func _merge_file() -> Error:
	var file := ConfigFile.new()
	var code := file.load(path)
	if code != OK:
		return code
	for section: String in file.get_sections():
		var type := StringName(section)
		var shown: Variant = file.get_value(section, SHOWN, 0)
		if shown is int and (shown as int) > loading_shown(type):
			_shown[type] = shown as int
		var done: Variant = file.get_value(section, COMPLETED, false)
		if done is bool and done:
			_completed[type] = true
	return OK
