extends GdUnitTestSuite
## The command logs a debug-build host writes (ARCHITECTURE §4.5, E13): one file per session when
## it ends, the newest 10 kept, read back for Match.replay. In a folder of this suite's own under
## user://, removed after each test.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")
const DIR := "user://test_replays_100"

var _h: Harness


func before_test() -> void:
	_clear()


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null
	_clear()


func test_a_session_writes_its_log_when_it_ends_and_it_replays() -> void:
	_h = Harness.new()
	_h.session.replay_dir = DIR
	_h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 600)).is_true()
	_h.pump_seconds(1)
	assert_array(Array(ReplayFiles.list(DIR))).is_empty()
	var recorded := _h.session.game.command_log.to_dict()
	_h.session.close()
	assert_str(_h.session.replay_path).starts_with(DIR)
	assert_array(Array(ReplayFiles.list(DIR))).is_equal([_h.session.replay_path])
	var read := ReplayFiles.read(_h.session.replay_path)
	assert_object(read).is_not_null()
	assert_dict(read.to_dict()).is_equal(recorded)
	var replayed := Match.replay(read, _h.mode)
	assert_array(Array(replayed.refusals)).is_empty()
	assert_dict(replayed.command_log.to_dict()).is_equal(recorded)
	assert_array(FixtureModes.names(replayed)).is_equal(FixtureModes.names(_h.session.game))
	# The log holds the seed and stays on the host's disk: the content hash a joiner sends too.
	assert_int(read.session_seed).is_equal(Harness.SEED)
	assert_int(read.content_hash).is_equal(_h.session.content_hash)


func test_only_the_newest_logs_are_kept() -> void:
	var written: Array[String] = []
	for _i in ReplayFiles.KEEP + 2:
		written.append(ReplayFiles.write(CommandLog.new(), DIR))
	assert_array(Array(ReplayFiles.list(DIR))).is_equal(written.slice(2))


func test_no_log_without_a_folder() -> void:
	_h = Harness.new()
	_h.session.close()
	assert_str(_h.session.replay_path).is_empty()


func test_a_file_that_is_not_a_log_reads_as_null() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join("broken.cmdlog")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not a log")
	file.close()
	assert_object(ReplayFiles.read(path)).is_null()
	assert_object(ReplayFiles.read(DIR.path_join("missing.cmdlog"))).is_null()


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for file_name: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file_name))
	DirAccess.remove_absolute(DIR)
