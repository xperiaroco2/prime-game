extends GdUnitTestSuite
## ContentFingerprintCache (#1172): the same parts give ContentFingerprint's value, hashed once; a
## level file whose modified time or size changed, another mode hash or another level list is
## hashed again; a missing level is kept too; `of` is the process's one cache.

## A mode hash of the test's own (the cache takes the mode's parts, not the mode).
const MODE_HASH := 1172

var _dir := ""
## The fake modified time the stamper of `_faked` reports for every level.
var _fake_time := 1000


func before_test() -> void:
	# The process id keeps two runs of this worktree apart.
	_dir = "res://tests/scratch/content_fingerprint_cache_test_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_dir)
	_write("lobby.tscn", _scene("Lobby", 0))
	_write("map.tscn", _scene("Map", 0))


func after_test() -> void:
	for file: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file))
	DirAccess.remove_absolute(_dir)


func test_the_same_parts_are_hashed_once_and_give_the_fingerprint() -> void:
	var cache := ContentFingerprintCache.new()
	var value := _cached(cache, MODE_HASH)
	assert_int(cache.computed).is_equal(1)
	assert_int(value).is_equal(_fingerprint(MODE_HASH))
	assert_int(_cached(cache, MODE_HASH)).is_equal(value)
	assert_int(_cached(cache, MODE_HASH)).is_equal(value)
	assert_int(cache.computed).is_equal(1)


func test_a_level_file_of_another_size_is_hashed_again() -> void:
	var cache := ContentFingerprintCache.new()
	var value := _cached(cache, MODE_HASH)
	_write("map.tscn", _scene("Map", 10))
	var changed := _cached(cache, MODE_HASH)
	assert_int(cache.computed).is_equal(2)
	assert_int(changed).is_not_equal(value)
	assert_int(changed).is_equal(_fingerprint(MODE_HASH))
	assert_int(_cached(cache, MODE_HASH)).is_equal(changed)
	assert_int(cache.computed).is_equal(2)


## The stamp decides, not the bytes: a level rewritten with the same size is hashed again only
## once its modified time changed (a fake clock: the real one counts whole seconds).
func test_a_level_file_with_a_later_modified_time_is_hashed_again() -> void:
	var cache := ContentFingerprintCache.new(_faked)
	var value := _cached(cache, MODE_HASH)
	_write("lobby.tscn", _scene("Lobby", 1))
	assert_int(_cached(cache, MODE_HASH)).is_equal(value)
	assert_int(cache.computed).is_equal(1)
	_fake_time += 1
	var changed := _cached(cache, MODE_HASH)
	assert_int(cache.computed).is_equal(2)
	assert_int(changed).is_not_equal(value)
	assert_int(changed).is_equal(_fingerprint(MODE_HASH))


func test_the_stamps_are_each_levels_modified_time_and_size() -> void:
	var lobby := _dir.path_join("lobby.tscn")
	var gone := _dir.path_join("gone.tscn")
	var stamps := ContentFingerprintCache.stamps_of(PackedStringArray([lobby, gone]))
	assert_array(Array(stamps)).contains_exactly(
		[FileAccess.get_modified_time(lobby), _scene("Lobby", 0).length(), 0, -1]
	)
	assert_int(stamps[0]).is_greater(0)


func test_another_mode_hash_or_level_list_has_its_own_value() -> void:
	var cache := ContentFingerprintCache.new()
	var value := _cached(cache, MODE_HASH)
	var other := _cached(cache, MODE_HASH + 1)
	assert_int(other).is_not_equal(value)
	assert_int(other).is_equal(_fingerprint(MODE_HASH + 1))
	var lobby_only := cache.fingerprint(
		MODE_HASH, _dir.path_join("lobby.tscn"), PackedStringArray()
	)
	assert_int(lobby_only).is_not_equal(value)
	assert_int(cache.computed).is_equal(3)
	# Each is kept: going back to the first hashes nothing.
	assert_int(_cached(cache, MODE_HASH)).is_equal(value)
	assert_int(cache.computed).is_equal(3)


## A fixture mode's levels need not exist: hashed as missing, once, and again once one is there.
func test_a_missing_level_is_kept_until_it_is_there() -> void:
	DirAccess.remove_absolute(_dir.path_join("map.tscn"))
	var cache := ContentFingerprintCache.new()
	var missing := _cached(cache, MODE_HASH)
	assert_int(_cached(cache, MODE_HASH)).is_equal(missing)
	assert_int(cache.computed).is_equal(1)
	_write("map.tscn", _scene("Map", 0))
	var there := _cached(cache, MODE_HASH)
	assert_int(cache.computed).is_equal(2)
	assert_int(there).is_not_equal(missing)
	assert_int(there).is_equal(_fingerprint(MODE_HASH))


func test_of_is_the_processs_one_cache() -> void:
	var lobby := _dir.path_join("lobby.tscn")
	var value := ContentFingerprintCache.of(MODE_HASH, lobby, _maps())
	var before := ContentFingerprintCache.shared().computed
	assert_int(ContentFingerprintCache.of(MODE_HASH, lobby, _maps())).is_equal(value)
	assert_int(ContentFingerprintCache.shared().computed).is_equal(before)
	assert_int(value).is_equal(_fingerprint(MODE_HASH))


func _cached(cache: ContentFingerprintCache, mode_hash: int) -> int:
	return cache.fingerprint(mode_hash, _dir.path_join("lobby.tscn"), _maps())


func _fingerprint(mode_hash: int) -> int:
	return ContentFingerprint.of(mode_hash, _dir.path_join("lobby.tscn"), _maps())


func _maps() -> PackedStringArray:
	return PackedStringArray([_dir.path_join("map.tscn")])


## A stamper whose modified time is `_fake_time` for every level, and whose size is the real one.
func _faked(levels: PackedStringArray) -> PackedInt64Array:
	var stamps := PackedInt64Array()
	for path: String in levels:
		stamps.append(_fake_time)
		stamps.append(FileAccess.get_size(path))
	return stamps


func _write(file: String, text: String) -> void:
	var out := FileAccess.open(_dir.path_join(file), FileAccess.WRITE)
	out.store_string(text)
	out.close()


## A scene named `root` whose root sits at x = `x`: 0 to 9 give files of one size.
func _scene(root: String, x: int) -> String:
	return (
		'[gd_scene format=3]\n\n[node name="%s" type="Node3D"]\nposition = Vector3(%d, 0, 0)\n'
		% [root, x]
	)
