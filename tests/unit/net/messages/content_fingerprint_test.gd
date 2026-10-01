extends GdUnitTestSuite
## ContentFingerprint (ARCHITECTURE §4.3 "The content", E1, #118): the same mode and files give
## the same value; a changed byte of a level file, of a scene or resource a level reaches, or of
## the mode, gives another; the walk follows uids, leaves scripts out, walks a file once and names
## a missing dependency.

## Committed fixtures: a map instancing a room and a crate, the room a wall shape, the crate and a
## script (left out), the crate an imported texture.
const FIXTURES := "res://tests/fixtures/net/"
const MAP := FIXTURES + "fingerprint_map.tscn"

var _dir := ""


func before_test() -> void:
	# The process id keeps two worktrees' runs, which share user://, apart.
	_dir = "user://content_fingerprint_test_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_dir)
	_write("lobby.tscn", _scene("Lobby", [], 0))
	_write("map.tscn", _scene("Map", [], 0))


func after_test() -> void:
	for file: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file))
	DirAccess.remove_absolute(_dir)


func test_the_same_mode_and_files_give_the_same_value() -> void:
	assert_int(_of(_mode())).is_equal(_of(_mode()))


func test_a_changed_level_file_gives_another_value() -> void:
	var before := _of(_mode())
	_write("map.tscn", _scene("Map", [], 1))
	assert_int(_of(_mode())).is_not_equal(before)
	_write("map.tscn", _scene("Map", [], 0))
	assert_int(_of(_mode())).is_equal(before)
	_write("lobby.tscn", _scene("Lobby", [], 2))
	assert_int(_of(_mode())).is_not_equal(before)


func test_a_changed_mode_gives_another_value() -> void:
	var before := _of(_mode())
	var mode := _mode()
	mode.player_rules.walk_speed_mps += 0.5
	assert_int(_of(mode)).is_not_equal(before)


func test_a_missing_level_file_gives_another_value() -> void:
	var before := _of(_mode())
	DirAccess.remove_absolute(_dir.path_join("map.tscn"))
	assert_int(_of(_mode())).is_not_equal(before)


func test_the_content_mode_has_a_fingerprint() -> void:
	var mode: GameMode = load("res://content/modes/base_mode.tres")
	assert_int(_of(mode)).is_equal(_of(mode))
	assert_int(_of(mode)).is_not_equal(ContentHash.of(mode))


## Levels that instance nothing keep the value they had before the walk (the MVP's lobby and
## greybox today): no `file` line.
func test_levels_that_reach_nothing_hash_their_own_files_alone() -> void:
	var mode := _mode()
	var text := (
		"\n"
		. join(
			PackedStringArray(
				[
					"mode %d" % ContentHash.of(mode),
					"level %s %s" % [mode.lobby_level, FileAccess.get_sha256(mode.lobby_level)],
					"level %s %s" % [mode.maps[0], FileAccess.get_sha256(mode.maps[0])],
				]
			)
		)
	)
	assert_str(_text_of(mode)).is_equal(text)
	assert_int(_of(mode)).is_equal(text.sha256_buffer().decode_s64(0))


func test_the_walk_reaches_every_scene_and_resource_by_path_and_no_script() -> void:
	var reached := ContentFingerprint.reached_from(PackedStringArray([MAP]))
	(
		assert_array(Array(reached))
		. contains_exactly(
			[
				"res://icon.svg",
				"res://icon.svg.import",
				FIXTURES + "fingerprint_crate.tscn",
				FIXTURES + "fingerprint_room.tscn",
				FIXTURES + "fingerprint_wall.tres",
			]
		)
	)


func test_the_same_files_give_the_same_hash() -> void:
	var mode := _mode()
	mode.maps = PackedStringArray([MAP])
	assert_int(_of(mode)).is_equal(_of(mode))
	var text := _text_of(mode)
	assert_str(text).contains("\nfile %s%s " % [FIXTURES, "fingerprint_wall.tres"])
	assert_str(text).not_contains("fingerprint_room.gd")


## A designer moves a prop inside a room the map instances: no map byte changes, the hash does.
func test_a_changed_sub_scene_changes_the_hash() -> void:
	_write("prop.tscn", _scene("Prop", [], 0))
	_write("room.tscn", _scene("Room", [_dir.path_join("prop.tscn")], 0))
	_write("map.tscn", _scene("Map", [_dir.path_join("room.tscn")], 0))
	var before := _of(_mode())
	_write("prop.tscn", _scene("Prop", [], 3))
	assert_int(_of(_mode())).is_not_equal(before)
	_write("prop.tscn", _scene("Prop", [], 0))
	assert_int(_of(_mode())).is_equal(before)
	_write("room.tscn", _scene("Room", [_dir.path_join("prop.tscn")], 4))
	assert_int(_of(_mode())).is_not_equal(before)


func test_a_missing_dependency_is_named() -> void:
	var gone := _dir.path_join("gone.tscn")
	_write("gone.tscn", _scene("Gone", [], 0))
	_write("map.tscn", _scene("Map", [gone], 0))
	var before := _of(_mode())
	DirAccess.remove_absolute(gone)
	assert_str(_text_of(_mode())).contains("\nfile %s missing" % gone)
	assert_int(_of(_mode())).is_not_equal(before)
	var levels := PackedStringArray([_mode().lobby_level, _mode().maps[0]])
	assert_array(Array(ContentFingerprint.missing_from(levels))).contains_exactly([gone])


## Only a reached file that is not there is missing: a mode whose files are all there, and a
## missing level file (the fixture modes' levels), name nothing.
func test_nothing_is_missing_when_every_reached_file_is_there() -> void:
	assert_array(Array(ContentFingerprint.missing_from(PackedStringArray([MAP])))).is_empty()
	var fixture := PackedStringArray([FixtureBaseMode.LOBBY, FixtureBaseMode.MAP])
	assert_array(Array(ContentFingerprint.missing_from(fixture))).is_empty()


## A cycle ends, and a piece the lobby and the map share, or one reached twice, is one line.
func test_a_cycle_and_a_shared_piece_are_walked_once() -> void:
	var a := _dir.path_join("a.tscn")
	var b := _dir.path_join("b.tscn")
	var shared := _dir.path_join("shared.tscn")
	_write("a.tscn", _scene("A", [b, shared], 0))
	_write("b.tscn", _scene("B", [a, shared], 0))
	_write("shared.tscn", _scene("Shared", [], 0))
	_write("lobby.tscn", _scene("Lobby", [shared], 0))
	_write("map.tscn", _scene("Map", [a, shared, _dir.path_join("map.tscn")], 0))
	var mode := _mode()
	var reached := ContentFingerprint.reached_from(
		PackedStringArray([mode.lobby_level, mode.maps[0]])
	)
	assert_array(Array(reached)).contains_exactly([a, b, shared])


## Godot loads a dependency by its uid when the uid is known, else by the fallback path; the walk
## hashes the same file.
func test_a_dependency_is_the_file_its_uid_names_else_its_path() -> void:
	var wall := FIXTURES + "fingerprint_wall.tres"
	var fallback := _dir.path_join("fallback.tres")
	_write("fallback.tres", '[gd_resource type="BoxShape3D" format=3]\n\n[resource]\n')
	var known := ResourceUID.path_to_uid(wall)
	assert_str(known).starts_with("uid://")
	_write("map.tscn", _scene_with_uid("Map", known, fallback))
	var reached := ContentFingerprint.reached_from(PackedStringArray([_mode().maps[0]]))
	assert_array(Array(reached)).contains_exactly([wall])
	_write("map.tscn", _scene_with_uid("Map", "uid://zzzzzzzzzzzz1", fallback))
	reached = ContentFingerprint.reached_from(PackedStringArray([_mode().maps[0]]))
	assert_array(Array(reached)).contains_exactly([fallback])


func _mode() -> GameMode:
	var mode := FixtureBaseMode.mode()
	mode.lobby_level = _dir.path_join("lobby.tscn")
	mode.maps = PackedStringArray([_dir.path_join("map.tscn")])
	return mode


func _write(file: String, text: String) -> void:
	var out := FileAccess.open(_dir.path_join(file), FileAccess.WRITE)
	out.store_string(text)
	out.close()


## A scene named `root` instancing `pieces`, whose root sits at x = `x` (a moved wall).
func _scene(root: String, pieces: Array[String], x: int) -> String:
	var text := "[gd_scene format=3]\n\n"
	for i: int in pieces.size():
		text += '[ext_resource type="PackedScene" path="%s" id="%d_piece"]\n' % [pieces[i], i + 1]
	text += '\n[node name="%s" type="Node3D"]\nposition = Vector3(%d, 0, 0)\n' % [root, x]
	for i: int in pieces.size():
		text += '\n[node name="Piece%d" parent="." instance=ExtResource("%d_piece")]\n' % [i, i + 1]
	return text


## A scene whose one shape is the resource `uid` names, with `fallback` as its path.
func _scene_with_uid(root: String, uid: String, fallback: String) -> String:
	return (
		(
			'[gd_scene format=3]\n\n[ext_resource type="Shape3D" uid="%s" path="%s" id="1_shape"]\n\n'
			% [uid, fallback]
		)
		+ '[node name="%s" type="CollisionShape3D"]\nshape = ExtResource("1_shape")\n' % root
	)


## As server/ and every client call it.
func _of(mode: GameMode) -> int:
	return ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)


func _text_of(mode: GameMode) -> String:
	return ContentFingerprint.text_of(ContentHash.of(mode), mode.lobby_level, mode.maps)
