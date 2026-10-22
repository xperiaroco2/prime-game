class_name TaskClients
extends RefCounted
## The client's one table from a core task type class to its TaskClient (#1260, ARCHITECTURE
## §4.7.59), client-only: `core/` and the content `.tres` name no client. A type's client is its
## class's row, else its base class's, along `get_base_script()` (a subclass falls back to its
## base); none: null, and ItemWorld reports the type once (`report_missing`). A new task type is
## one TaskClient subclass in `client/world/tasks/` plus its row here; `task_clients_test.gd`
## fails while a global class reaching TaskType has none.

## The core script of each task type class to its TaskClient script, in the order ItemWorld adds
## their views (make_views).
static var _by_script: Dictionary[Script, GDScript] = {
	Delivery: DeliveryClient,
	DeliveryByMeaning: DeliveryByMeaningClient,
	ZoneTask: ZoneTaskClient,
	Generator: GeneratorClient,
}
## One client per TaskClient script, made on first use (a client holds no state).
static var _clients: Dictionary[GDScript, TaskClient] = {}
## The core scripts report_missing has named, so each is named once.
static var _reported: Dictionary[Script, bool] = {}


## The TaskClient script of core script `script`: its row, else its nearest base's; null for none.
static func client_script_of(script: Script) -> GDScript:
	var at := script
	while at != null and not _by_script.has(at):
		at = at.get_base_script()
	return _by_script[at] if at != null else null


## The client of `type`'s class (see the class doc), or null.
static func of(type: TaskType) -> TaskClient:
	return of_script(type.get_script() as Script) if type != null else null


## The client of core script `script` (its row, else its nearest base's), or null.
static func of_script(script: Script) -> TaskClient:
	var client_script := client_script_of(script)
	if client_script == null:
		return null
	if not _clients.has(client_script):
		_clients[client_script] = client_script.new() as TaskClient
	return _clients[client_script]


## A new view of every row's client that makes one, keyed by the row's core script, in the
## table's order: every row, not only the mode's types, as ItemWorld always held them.
static func make_views() -> Dictionary[Script, Node3D]:
	var views: Dictionary[Script, Node3D] = {}
	for core: Script in _by_script:
		var view := of_script(core).make_view()
		if view != null:
			views[core] = view
	return views


## Pushes an error for each task type of `mode` with no client, once per class for the process,
## so a missing row is never skipped silently; returns the messages it pushed now.
static func report_missing(mode: GameMode) -> Array[String]:
	var pushed: Array[String] = []
	if mode == null:
		return pushed
	for type: TaskType in mode.task_types:
		if type == null or of(type) != null:
			continue
		var core := type.get_script() as Script
		if _reported.has(core):
			continue
		_reported[core] = true
		var message := "task type %s (%s) has no TaskClient" % [type.id, core.resource_path]
		push_error(message)
		pushed.append(message)
	return pushed
