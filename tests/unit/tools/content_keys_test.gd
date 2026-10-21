extends GdUnitTestSuite
## The unknown-key check of content .tres files (tools/check/content_keys.gd, #1238): a misspelled
## key in a [sub_resource] or the [resource] is reported with its file, line, section and class;
## stored keys, `script` and `metadata/` are not; a multi-line string or dictionary value never
## reads as a key; a section whose script or type does not load is left to the load check; and
## every shipped content .tres passes. The fixtures are text: the editor or `normalize` would drop
## a misspelled key from a .tres file.

const ContentKeys := preload("res://tools/check/content_keys.gd")
const PATH := "res://content/roles/fixture.tres"
const HEAD := """[gd_resource type="Resource" script_class="Rule" format=3]

[ext_resource type="Script" path="res://core/content/rule.gd" id="1_rule"]
[ext_resource type="Script" path="res://core/content/condition.gd" id="2_condition"]
"""

var _keys: ContentKeys


func before_test() -> void:
	_keys = ContentKeys.new()


func test_a_misspelled_key_in_a_sub_resource_is_reported_with_its_line() -> void:
	var text := (
		HEAD
		+ """
[sub_resource type="Resource" id="Condition_a"]
script = ExtResource("2_condition")
negate_ = true

[resource]
script = ExtResource("1_rule")
conditions = [SubResource("Condition_a")]
"""
	)
	var problems := _keys.unknown_keys_in(PATH, text)
	assert_array(problems).has_size(1)
	assert_str(problems[0]).starts_with(
		(
			'res://content/roles/fixture.tres:8: unknown property "negate_" in'
			+ ' [sub_resource id="Condition_a"] (Condition):'
		)
	)


func test_a_misspelled_key_in_the_resource_is_reported() -> void:
	var text := HEAD + '\n[resource]\nscript = ExtResource("1_rule")\ntriger = &"round_start"\n'
	var problems := _keys.unknown_keys_in(PATH, text)
	assert_array(problems).has_size(1)
	assert_str(problems[0]).contains(':8: unknown property "triger" in [resource] (Rule)')


func test_stored_keys_script_and_metadata_pass() -> void:
	var text := (
		HEAD
		+ """
[sub_resource type="Resource" id="Condition_a"]
script = ExtResource("2_condition")
negate = true
resource_name = "a"
metadata/note = "kept by Godot"

[resource]
script = ExtResource("1_rule")
trigger = &"round_start"
conditions = [SubResource("Condition_a")]
effects = []
"""
	)
	assert_array(_keys.unknown_keys_in(PATH, text)).is_empty()


func test_a_multi_line_value_never_reads_as_a_key_or_a_header() -> void:
	var text := (
		HEAD
		+ """
[resource]
script = ExtResource("1_rule")
resource_name = "a name with \\" and
not_a_key = 1
[sub_resource type=\\"Resource\\" id=\\"X\\"]
still the string"
metadata/table = {
"oops_ = ": 1,
nested = [
2
]
}
trigger = &"round_start"
"""
	)
	assert_array(_keys.unknown_keys_in(PATH, text)).is_empty()


func test_an_indented_or_quoted_key_is_compared_like_godot_reads_it() -> void:
	var text := (
		HEAD
		+ """
  [resource]
script = ExtResource("1_rule")
  triger = &"round_start"
"trigr" = &"round_start"
"trigger" = &"round_start"
"""
	)
	var problems := _keys.unknown_keys_in(PATH, text)
	assert_array(problems).has_size(2)
	assert_str(problems[0]).contains(':8: unknown property "triger"')
	assert_str(problems[1]).contains(':9: unknown property "trigr"')


func test_a_comment_neither_hides_a_key_nor_unbalances_the_scan() -> void:
	var text := (
		HEAD
		+ """
[resource]
script = ExtResource("1_rule")
; a comment with a quote " and a bracket [ and a brace {
trigger = &"round_start" ; a trailing comment with a (
triger = &"round_start"
resource_name = "a ; inside a string"
trigr = 1
"""
	)
	var problems := _keys.unknown_keys_in(PATH, text)
	assert_array(problems).has_size(2)
	assert_str(problems[0]).contains(':10: unknown property "triger"')
	assert_str(problems[1]).contains(':12: unknown property "trigr"')


func test_a_native_sub_resource_is_compared_with_its_class() -> void:
	var text := (
		HEAD
		+ """
[sub_resource type="Gradient" id="Gradient_a"]
offsets = PackedFloat32Array(0, 1)
ofsets = PackedFloat32Array(0, 1)

[resource]
script = ExtResource("1_rule")
"""
	)
	var problems := _keys.unknown_keys_in(PATH, text)
	assert_array(problems).has_size(1)
	assert_str(problems[0]).contains('"ofsets" in [sub_resource id="Gradient_a"] (Gradient)')


func test_a_section_whose_class_does_not_load_is_left_to_the_load_check() -> void:
	var text := """[gd_resource type="Resource" format=3]

[ext_resource type="Script" path="res://core/content/no_such_part.gd" id="1_gone"]

[sub_resource type="NoSuchClass" id="Odd_a"]
whatever = 1

[resource]
script = ExtResource("1_gone")
anything = 2
"""
	assert_array(_keys.unknown_keys_in(PATH, text)).is_empty()


func test_only_content_tres_files_are_compared() -> void:
	assert_bool(ContentKeys.applies_to("res://content/roles/crew.tres")).is_true()
	assert_bool(ContentKeys.applies_to("res://content/modes/base_mode.tscn")).is_false()
	assert_bool(ContentKeys.applies_to("res://tests/fixtures/tasks/a_mode.tres")).is_false()
	assert_bool(ContentKeys.applies_to("res://levels/kit/house_kit/wall.tres")).is_false()


func test_every_shipped_content_tres_has_only_known_keys() -> void:
	var files: PackedStringArray = []
	_collect("res://content", files)
	assert_int(files.size()).is_greater(50)
	var problems: PackedStringArray = []
	for path: String in files:
		problems.append_array(_keys.unknown_keys(path))
	assert_array(problems).is_empty()


func _collect(dir: String, out: PackedStringArray) -> void:
	for file: String in DirAccess.get_files_at(dir):
		if ContentKeys.applies_to(dir.path_join(file)):
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), out)
