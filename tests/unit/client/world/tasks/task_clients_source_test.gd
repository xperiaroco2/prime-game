extends GdUnitTestSuite
## Only the task types' clients test a task type's class (#1260, ARCHITECTURE §4.7.59): no
## client/ file outside client/world/tasks/ has `is` or `as` of a core TaskType subclass (every
## global class outside the tests whose base chain reaches TaskType; TaskType itself passes), so
## a new task type's client code goes into its TaskClient. Comments and strings are stripped first
## ("as PhotoTask's" in a doc line passes) and the names matched word-bounded (CookingViews
## passes). The per-type special cases that stay outside the registry (#1260's proposal: the hums,
## the sound choice, the camera and box keys, the item looks) are the named EXCEPTIONS; they reach
## their types through the *Use helpers, whose scans are the clients'.

const BOUNDARY := preload("res://tests/unit/client/app/client_boundary_test.gd")
const CLIENT := "res://client"
const TASKS := "res://client/world/tasks/"
## The files that keep per-type code outside client/world/tasks/ (each must still exist).
const EXCEPTIONS: Array[String] = [
	"res://client/world/station_hums.gd",
	"res://client/world/sound_chooser.gd",
	"res://client/world/item_interactions.gd",
	"res://client/world/item_view.gd",
	"res://client/world/item_views.gd",
]


func test_no_client_file_outside_the_task_clients_tests_a_task_type_class() -> void:
	var classes := _task_type_classes()
	assert_array(classes).contains(["Delivery", "Generator", "PhotoTask"])
	var files := BOUNDARY._client_files(CLIENT)
	var found := PackedStringArray()
	for path: String in files:
		if path.begins_with(TASKS) or EXCEPTIONS.has(path):
			continue
		for hit: String in problems(FileAccess.get_file_as_string(path), classes):
			found.append("%s: %s" % [path, hit])
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


func test_every_exception_exists() -> void:
	var files := BOUNDARY._client_files(CLIENT)
	for path: String in EXCEPTIONS:
		assert_bool(files.has(path)).override_failure_message(path + " is gone").is_true()


func test_it_rejects_the_planted_tests_and_accepts_the_look_alikes() -> void:
	var classes: Array[String] = ["Cooking", "PhotoTask"]
	assert_array(problems("\tif type is Cooking:\n\t\tpass", classes)).has_size(1)
	assert_array(problems("\tvar p := type as PhotoTask", classes)).has_size(1)
	assert_array(problems("\tif type is not Cooking:\n\t\tpass", classes)).has_size(1)
	assert_array(problems("\tif not type is  PhotoTask:\n\t\tpass", classes)).has_size(1)
	# Look-alikes and mentions pass: other names, comments and strings.
	var look_alikes := (
		"## as PhotoTask's lens\n"
		+ "var v := node as CookingViews  # is Cooking\n"
		+ 'var s := "is Cooking"\n'
		+ "for type: TaskType in mode.task_types:\n"
		+ "\tif type is TaskType:\n"
		+ "\t\tCookingUse.types_of(mode)\n"
	)
	assert_array(problems(look_alikes, classes)).is_empty()


## The `is`/`as` tests of a class of `classes` in `source`, comments and strings stripped.
static func problems(source: String, classes: Array[String]) -> PackedStringArray:
	var found := PackedStringArray()
	if classes.is_empty():
		return found
	var test := RegEx.create_from_string(
		"\\b(is|as)\\s+(not\\s+)?(%s)\\b" % "|".join(PackedStringArray(classes))
	)
	for hit: RegExMatch in test.search_all(BOUNDARY.strip(source)):
		found.append(hit.get_string())
	return found


## Every global class outside res://tests/ whose base chain reaches TaskType (TaskType itself not).
static func _task_type_classes() -> Array[String]:
	var bases: Dictionary[String, String] = {}
	var paths: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		bases[str(entry["class"])] = str(entry["base"])
		paths[str(entry["class"])] = str(entry["path"])
	var found: Array[String] = []
	for class_id: String in bases:
		if paths[class_id].begins_with("res://tests/"):
			continue
		var at: String = bases.get(class_id, "")
		while at != "" and at != "TaskType":
			at = bases.get(at, "")
		if at == "TaskType":
			found.append(class_id)
	return found
