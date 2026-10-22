extends GdUnitTestSuite
## TaskClients (client/world/tasks/task_clients.gd; #1260, ARCHITECTURE §4.7.59): every global
## class outside the tests whose base chain reaches TaskType has a TaskClient, and so does every
## task type of every mode in content/modes/; a class with no row has none and is reported once.
## Loads `content/` on purpose, as the how-to cards' check does (§9.6).

const MODES := "res://content/modes/"
## The core task type classes whose client is not built yet (#1260's migration moves one a
## commit): the checks skip them and fail when one has a client.
const UNMIGRATED: Array[String] = [
	"Generator",
	"Cooking",
	"CarRepair",
	"PhotoTask",
]
## Today's core task type classes, so the global class list's walk is seen to find them.
const CORE_TYPES: Array[String] = [
	"Delivery",
	"DeliveryByMeaning",
	"Generator",
	"Cooking",
	"CarRepair",
	"PhotoTask",
]


## A task type class with no row (and no global name, so the class list never lists it).
class StrayType:
	extends TaskType


## A subclass of a class with a row, with none of its own.
class SubDelivery:
	extends Delivery


func test_every_global_task_type_class_has_a_client() -> void:
	var bases: Dictionary[String, String] = {}
	var paths: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		bases[str(entry["class"])] = str(entry["base"])
		paths[str(entry["class"])] = str(entry["path"])
	var found: Array[String] = []
	var problems: Array[String] = []
	for class_id: String in bases:
		if paths[class_id].begins_with("res://tests/") or not _reaches_task_type(class_id, bases):
			continue
		found.append(class_id)
		var has_client := TaskClients.client_script_of(load(paths[class_id]) as Script) != null
		if not has_client and not UNMIGRATED.has(class_id):
			problems.append("%s (%s) has no TaskClient" % [class_id, paths[class_id]])
		elif has_client and UNMIGRATED.has(class_id):
			problems.append("%s has a TaskClient: drop it from UNMIGRATED" % class_id)
	assert_array(found).contains(CORE_TYPES)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_every_task_type_of_every_mode_has_a_client() -> void:
	var modes := _modes()
	assert_array(modes).is_not_empty()
	var types := 0
	var problems: Array[String] = []
	for mode: GameMode in modes:
		types += mode.task_types.size()
		for type: TaskType in mode.task_types:
			if UNMIGRATED.has((type.get_script() as Script).get_global_name()):
				continue
			if TaskClients.of(type) == null:
				problems.append("%s: %s has no TaskClient" % [mode.resource_path, type.id])
	assert_int(types).is_greater(0)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_a_subclass_falls_back_to_its_base_class_client() -> void:
	assert_object(TaskClients.client_script_of(SubDelivery)).is_same(DeliveryClient)
	assert_object(TaskClients.of(SubDelivery.new())).is_same(TaskClients.of(Delivery.new()))
	assert_bool(TaskClients.of(Delivery.new()) is DeliveryClient).is_true()


func test_a_class_with_no_row_has_no_client_and_is_reported_once() -> void:
	var stray := StrayType.new()
	stray.id = &"stray"
	assert_object(TaskClients.of(stray)).is_null()
	assert_object(TaskClients.of(null)).is_null()
	var mode := GameMode.new()
	mode.task_types.append(stray)
	var first := TaskClients.report_missing(mode)
	assert_int(first.size()).is_equal(1)
	assert_str(first[0]).contains("stray")
	assert_array(TaskClients.report_missing(mode)).is_empty()


## Whether global class `class_id`'s base chain in `bases` reaches TaskType (TaskType itself not).
func _reaches_task_type(class_id: String, bases: Dictionary[String, String]) -> bool:
	var at: String = bases.get(class_id, "")
	while at != "":
		if at == "TaskType":
			return true
		at = bases.get(at, "")
	return false


func _modes() -> Array[GameMode]:
	var found: Array[GameMode] = []
	for file: String in DirAccess.get_files_at(MODES):
		if file.ends_with(".tres"):
			found.append(load(MODES + file) as GameMode)
	return found
