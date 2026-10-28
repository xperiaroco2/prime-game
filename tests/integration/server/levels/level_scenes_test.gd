extends GdUnitTestSuite
## LevelScenes (ARCHITECTURE §4.5 Starting, #1068): one load of each level scene per host start.
## `reads` is a process-wide count, so every check compares it before and after.

const ROOM := "res://tests/fixtures/levels/platform_room.tscn"
const LEVEL := "res://tests/fixtures/levels/wall_ledge_crate.tscn"
const MISSING := "res://tests/fixtures/levels/no_such_level.tscn"


func test_a_held_scene_is_read_once_and_shared() -> void:
	var scenes := LevelScenes.new()
	var before := _reads(ROOM)
	var first := scenes.scene(ROOM)
	var again := scenes.scene(ROOM)
	assert_object(first).is_not_null()
	assert_object(again).is_same(first)
	assert_int(_reads(ROOM) - before).is_equal(1)


func test_each_path_is_read_on_its_own() -> void:
	var scenes := LevelScenes.new()
	var room := _reads(ROOM)
	var level := _reads(LEVEL)
	assert_object(scenes.scene(ROOM)).is_not_same(scenes.scene(LEVEL))
	assert_int(_reads(ROOM) - room).is_equal(1)
	assert_int(_reads(LEVEL) - level).is_equal(1)


func test_a_direct_load_counts_every_call() -> void:
	var before := _reads(ROOM)
	assert_object(LevelScenes.load_packed(ROOM)).is_not_null()
	assert_object(LevelScenes.scene_of(ROOM, null)).is_not_null()
	assert_int(_reads(ROOM) - before).is_equal(2)


func test_a_missing_scene_is_null_and_no_read() -> void:
	var scenes := LevelScenes.new()
	assert_object(scenes.scene(MISSING)).is_null()
	assert_object(scenes.scene(MISSING)).is_null()
	assert_object(LevelScenes.load_packed(MISSING)).is_null()
	assert_bool(LevelScenes.reads.has(MISSING)).is_false()


func test_release_frees_the_scenes_and_the_next_ask_reads_again() -> void:
	var scenes := LevelScenes.new()
	var before := _reads(ROOM)
	var held := _weak_scene(scenes, ROOM)
	# Booleans, not assert_object: an object assert keeps its value alive.
	assert_bool(held.get_ref() != null).is_true()
	scenes.release()
	assert_bool(held.get_ref() == null).is_true()
	assert_object(scenes.scene(ROOM)).is_not_null()
	assert_int(_reads(ROOM) - before).is_equal(2)


# A weak reference to the scene `scenes` holds, with no strong one left in the caller.
func _weak_scene(scenes: LevelScenes, path: String) -> WeakRef:
	return weakref(scenes.scene(path))


func _reads(path: String) -> int:
	return LevelScenes.reads.get(path, 0)
