extends GdUnitTestSuite
## HowtoProgress (#254): the loading screen's how-to card of a task type shows at most twice and
## never after the type's first completion (a task of it finished in a round the player was in),
## the first such type of the round's in their order; kept under user:// across runs, a damaged
## file reading as nothing seen.

const PATH := "user://howto_progress_test.cfg"


func before_test() -> void:
	_remove()


func after_test() -> void:
	_remove()


func test_a_type_shows_twice_then_never() -> void:
	var progress := HowtoProgress.new()
	var types: Array[StringName] = [&"delivery"]
	assert_bool(progress.wants_loading_card(&"delivery")).is_true()
	assert_str(String(progress.loading_pick(types))).is_equal("delivery")
	progress.note_loading_shown(&"delivery")
	assert_str(String(progress.loading_pick(types))).is_equal("delivery")
	progress.note_loading_shown(&"delivery")
	assert_int(progress.loading_shown(&"delivery")).is_equal(HowtoProgress.LOADING_SHOWS)
	assert_int(HowtoProgress.LOADING_SHOWS).is_equal(2)
	assert_bool(progress.wants_loading_card(&"delivery")).is_false()
	assert_str(String(progress.loading_pick(types))).is_empty()


func test_the_first_wanted_type_in_order_and_none_after_a_completion() -> void:
	var progress := HowtoProgress.new()
	var types: Array[StringName] = [&"delivery", &"switches"]
	progress.note_loading_shown(&"delivery")
	progress.note_loading_shown(&"delivery")
	assert_str(String(progress.loading_pick(types))).is_equal("switches")
	var model := ClientModel.new(null)
	_task(model, 1, &"switches", 2, 3)
	assert_bool(progress.follow(model)).is_false()
	assert_bool(progress.completed(&"switches")).is_false()
	_task(model, 1, &"switches", 3, 3)
	assert_bool(progress.follow(model)).is_true()
	assert_bool(progress.completed(&"switches")).is_true()
	assert_bool(progress.follow(model)).is_false()
	assert_str(String(progress.loading_pick(types))).is_empty()
	# Completed before its card ever showed: a veteran never sees it.
	var veteran := HowtoProgress.new()
	_task(model, 2, &"delivery", 6, 6)
	veteran.follow(model)
	assert_bool(veteran.wants_loading_card(&"delivery")).is_false()


func test_a_task_with_no_subtasks_completes_nothing() -> void:
	var progress := HowtoProgress.new()
	var model := ClientModel.new(null)
	_task(model, 1, &"delivery", 0, 0)
	assert_bool(progress.follow(model)).is_false()
	assert_bool(progress.completed(&"delivery")).is_false()


func test_it_is_kept_under_user_across_runs() -> void:
	var progress := HowtoProgress.new(PATH)
	progress.note_loading_shown(&"delivery")
	var model := ClientModel.new(null)
	_task(model, 1, &"switches", 1, 1)
	progress.follow(model)
	var back := HowtoProgress.new(PATH)
	assert_int(back.read()).is_equal(OK)
	assert_int(back.loading_shown(&"delivery")).is_equal(1)
	assert_bool(back.completed(&"delivery")).is_false()
	assert_bool(back.completed(&"switches")).is_true()
	assert_int(back.loading_shown(&"switches")).is_equal(0)
	# In memory only: no file.
	var memory := HowtoProgress.new()
	memory.note_loading_shown(&"delivery")
	assert_int(memory.read()).is_equal(ERR_FILE_NOT_FOUND)
	assert_int(memory.loading_shown(&"delivery")).is_equal(0)
	assert_str(HowtoProgress.FILE).is_equal("user://howto.cfg")


func test_two_windows_of_one_pc_keep_each_others_progress() -> void:
	var host := HowtoProgress.new(PATH)
	host.read()
	var joiner := HowtoProgress.new(PATH)
	joiner.read()
	host.note_loading_shown(&"delivery")
	var model := ClientModel.new(null)
	_task(model, 1, &"switches", 1, 1)
	joiner.follow(model)
	joiner.note_loading_shown(&"delivery")
	var back := HowtoProgress.new(PATH)
	back.read()
	assert_int(back.loading_shown(&"delivery")).is_equal(2)
	assert_bool(back.completed(&"switches")).is_true()
	# The host never read the joiner's completion or showing, and writes them back all the same.
	host.note_loading_shown(&"delivery")
	back.read()
	assert_int(back.loading_shown(&"delivery")).is_equal(3)
	assert_bool(back.completed(&"switches")).is_true()
	assert_bool(host.completed(&"switches")).is_true()


func test_a_damaged_file_reads_as_nothing_seen() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('[delivery]\nloading_shown="many"\ncompleted="yes"\n')
	file.close()
	var progress := HowtoProgress.new(PATH)
	assert_int(progress.read()).is_equal(OK)
	assert_int(progress.loading_shown(&"delivery")).is_equal(0)
	assert_bool(progress.completed(&"delivery")).is_false()
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("not a config [[[")
	file.close()
	progress.read()
	assert_bool(progress.wants_loading_card(&"delivery")).is_true()


static func _task(model: ClientModel, id: int, type: StringName, done: int, total: int) -> void:
	model.fold(&"TaskState", {"task": id, "type": type, "done": done, "total": total})


static func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
